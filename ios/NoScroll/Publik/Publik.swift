// Publik.swift — Sign in with publik, usage counting, and publik API as one provider option.
// The publik module from https://publikhq.com/sdk/publik.swift.md, for iOS (the iPhone app of NoScroll).
// At launch, before any screen of the app's own: `let gate = await Publik.ensureSignedIn(ui)`. It
//   1. loads or provisions this device's publik key (POST /api/v1/installs);
//   2. shows Sign in with publik until GET /api/v1/wallet says "claimed" (no other way past it);
//   3. when usesAI: asks once how the app pays for AI and stores the answer (setChoice changes it);
//   4. starts usage counting: app_opened now, active_session every 30 minutes (POST /api/v1/telemetry).
// iOS changes from the macOS page: os is "ios", the device name comes from UIDevice, the version comes
// from the bundle, there is no terminal UI, and PUBLIK_API_BASE_URL (environment or launch argument)
// points the module at a test publik.
import Foundation
import UIKit

/// show(): draw the screen and return the button pressed. When the task is cancelled (the gate saw the sign-in), close it and return nil.
protocol PublikGateUI: Sendable {
    func show(_ screen: Publik.Screen) async -> String?
    func open(_ url: URL)
}

enum Publik {
    static let appSlug = "noscroll"
    /// The release version: MARKETING_VERSION of the app target.
    static let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    /// false: the app calls no model. It still signs in and counts users; it skips the plan screen.
    static let usesAI = false
    /// The test hook of the blind test: PUBLIK_API_BASE_URL in the environment, or the launch argument
    /// `-PUBLIK_API_BASE_URL <url>`, for example http://127.0.0.1:8787/api/v1. Unset: publik itself.
    static let testBaseURL: String? = {
        let raw = ProcessInfo.processInfo.environment["PUBLIK_API_BASE_URL"] ?? UserDefaults.standard.string(forKey: "PUBLIK_API_BASE_URL")
        guard var base = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }()
    static let origin: String = {
        if let base = testBaseURL { return base.hasSuffix("/api/v1") ? String(base.dropLast("/api/v1".count)) : base }
        return ProcessInfo.processInfo.environment["PUBLIK_ORIGIN"] ?? "https://publikhq.com" // PUBLIK_ORIGIN: tests only
    }()
    static let defaultBaseURL = "\(origin)/api/v1"
    /// Ask for a tier, never a vendor model name.
    static let models = (fast: "publik-fast", balanced: "publik-balanced", smart: "publik-smart")

    struct Credential: Codable { var key: String; var base_url: String; var install_id: String; var claim_url: String?; var choice: String? }
    struct Wallet: Sendable { var claimed: Bool; var claimURL: String?; var handle: String?; var planKind: String; var planLabel: String?; var balanceMicros: Int; var topUpURL: String }
    struct Screen: Sendable { let id: String; let title: String; let body: String; let note: String?; let buttons: [(action: String, label: String)] }
    enum Provider { case own(baseURL: String, apiKey: String), publik(baseURL: String, apiKey: String), needsOwnKey }
    struct PublikError: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// PUBLIK_APP_TOKEN, else publik-app-token.txt in the app bundle (the "publik app token" build phase puts it there).
    static var appToken: String {
        if let env = ProcessInfo.processInfo.environment["PUBLIK_APP_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty { return env }
        guard let url = Bundle.main.url(forResource: "publik-app-token", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #if arch(arm64)
    static let arch: String? = "arm64"
    #elseif arch(x86_64)
    static let arch: String? = "x64"
    #else
    static let arch: String? = nil
    #endif

    /// <app container>/Library/Application Support/publik.
    static var publikDir: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("publik") }
    static var credentialURL: URL { publikDir.appendingPathComponent("apps/\(appSlug).json") }

    static func readCredential() -> Credential? {
        guard let data = try? Data(contentsOf: credentialURL), let c = try? JSONDecoder().decode(Credential.self, from: data), c.key.hasPrefix("pk_") else { return nil }
        return c
    }
    private static func write(_ c: Credential?) throws {
        try FileManager.default.createDirectory(at: credentialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (c.map { try JSONEncoder().encode($0) } ?? Data("{}".utf8)).write(to: credentialURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialURL.path)
    }
    /// The person's answer to the plan screen: "publik", "own_key", or nil to ask again. Settings call it.
    static func setChoice(_ choice: String?) { if var c = readCredential() { c.choice = choice; try? write(c) } }

    /// The key this app uses: the stored choice decides. PUBLIK_API_KEY / PUBLIK_API_BASE_URL override (development).
    static func resolveProvider(userKey: (baseURL: String, apiKey: String)?) -> Provider {
        let env = ProcessInfo.processInfo.environment
        if let key = env["PUBLIK_API_KEY"], !key.isEmpty { return .publik(baseURL: defaultBaseURL, apiKey: key) } // defaultBaseURL follows PUBLIK_API_BASE_URL
        if let c = readCredential(), c.choice == "publik" { return .publik(baseURL: c.base_url, apiKey: c.key) }
        if let u = userKey, !u.apiKey.isEmpty { return .own(baseURL: u.baseURL, apiKey: u.apiKey) }
        return .needsOwnKey
    }

    private static func request(_ method: String, _ url: String, body: [String: Any]? = nil, key: String? = nil, timeout: TimeInterval = 20) async throws -> (Int, [String: Any]) {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let key { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }

    /// POST /api/v1/installs: this device's publik key. Throws a readable message (URLError when publik is not reachable).
    static func provision() async throws -> Credential {
        let token = appToken
        guard token.hasPrefix("pat_") else { throw PublikError(message: "This build has no publik app token. Ask the developer for a new build.") }
        let prior = readCredential()
        var installID = prior?.install_id ?? UUID().uuidString.lowercased()
        let deviceName = await MainActor.run { UIDevice.current.name }
        for _ in 0..<2 {
            var fields: [String: Any] = ["app_token": token, "app_slug": appSlug, "app_version": appVersion, "os": "ios", "install_id": installID,
                                         "device_name": String(deviceName.prefix(120)), "disclosure_version": 1, "dialects": ["chat_completions"]]
            if let arch { fields["arch"] = arch }
            let (status, body) = try await request("POST", "\(origin)/api/v1/installs", body: fields)
            let error = body["error"] as? [String: Any]
            if status == 200 || status == 201, let key = (body["key"] as? String) ?? (status == 200 ? prior?.key : nil) {
                let c = Credential(key: key, base_url: body["base_url"] as? String ?? defaultBaseURL, install_id: body["install_id"] as? String ?? installID,
                                   claim_url: body["claim_url"] as? String, choice: prior?.choice)
                try write(c) // the key reaches disk before anything else sees it
                return c
            }
            if status == 200 || error?["type"] as? String == "install_revoked" { installID = UUID().uuidString.lowercased(); continue }
            throw PublikError(message: error?["message"] as? String ?? "publik could not set up this device (\(status)).")
        }
        throw PublikError(message: "publik could not set up this device.")
    }

    /// GET /api/v1/wallet: (status, wallet or nil, message). Throws when publik is not reachable.
    static func readWallet(_ key: String) async throws -> (Int, Wallet?, String?) {
        let (status, b) = try await request("GET", "\(origin)/api/v1/wallet", key: key, timeout: 15)
        guard status == 200, let state = b["claim_state"] as? String else { return (status, nil, (b["error"] as? [String: Any])?["message"] as? String) }
        let plan = b["plan"] as? [String: Any]
        return (status, Wallet(claimed: state == "claimed", claimURL: b["claim_url"] as? String, handle: (b["account"] as? [String: Any])?["handle"] as? String,
                               planKind: plan?["kind"] as? String ?? "none", planLabel: plan?["label"] as? String, balanceMicros: b["balance_micros"] as? Int ?? 0,
                               topUpURL: b["top_up_url"] as? String ?? "\(origin)/wallet"), nil)
    }

    /// The words of the gate. The same in every publik module.
    static func gateScreen(_ id: String, _ w: Wallet? = nil, note: String? = nil, message: String? = nil) -> Screen {
        if id == "unreachable" { return Screen(id: id, title: "Sign in with publik", body: message ?? "publik is not reachable. Check your connection.", note: note, buttons: [("retry", "Retry")]) }
        if id == "sign_in" {
            return Screen(id: id, title: "Sign in with publik", body: "This app uses your publik account. Click Sign in with publik, then sign in in your browser. This window continues when you are signed in.",
                          note: note, buttons: [("sign_in", "Sign in with publik")])
        }
        let who = w?.handle.map { "You are signed in as @\($0)." } ?? "You are signed in to publik."
        guard let w, w.planKind != "none" || w.balanceMicros > 0 else {
            return Screen(id: id, title: "Choose how to pay for AI", body: "\(who) This app uses AI. Get a publik plan, or use your own key.", note: note,
                          buttons: [("get_plan", "Get a plan"), ("own_key", "Use my own key")])
        }
        let what = w.planKind == "plan" ? "Your plan: \(w.planLabel ?? "publik")." : String(format: "Your balance: $%.2f.", Double(w.balanceMicros) / 1_000_000)
        return Screen(id: id, title: "Connect your plan", body: "\(who) \(what) Connect it to use AI in this app, or use your own key.", note: note,
                      buttons: [("connect", "Connect your plan"), ("own_key", "Use my own key")])
    }

    /// Show a screen; with `until`, poll GET /wallet every 3 s for at most 10 minutes. "done": the poll saw it; "timeout": it did not.
    /// iOS suspends the app in the background, so the poll runs while the app is in the foreground and goes on when it comes back.
    private static func ask(_ ui: PublikGateUI, _ screen: Screen, key: String = "", until: (@Sendable (Wallet) -> Bool)? = nil) async -> String {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await ui.show(screen) }
            if let until {
                group.addTask {
                    for _ in 0..<200 { // 200 x 3 s = 10 minutes
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if Task.isCancelled { return nil }
                        if let w = try? await readWallet(key).1, until(w) { return "done" }
                    }
                    return "timeout"
                }
            }
            defer { group.cancelAll() }
            for await result in group { if let result { return result } }
            return "retry"
        }
    }

    /// The gate (see the top of the file). Returns once the person is signed in; `choice` is nil when usesAI is false.
    static func ensureSignedIn(_ ui: PublikGateUI) async -> (key: String, wallet: Wallet, choice: String?) {
        if ProcessInfo.processInfo.environment["PUBLIK_SELF_TEST"] != nil { print(await selfTest()); exit(0) }
        var signNote: String?, signPoll = true, planNote: String?, planPoll = false
        let signedIn: @Sendable (Wallet) -> Bool = { $0.claimed }, hasPlan: @Sendable (Wallet) -> Bool = { $0.planKind != "none" || $0.balanceMicros > 0 }
        while true {
            let envKey = ProcessInfo.processInfo.environment["PUBLIK_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
            let c: Credential, status: Int, wallet: Wallet?, message: String?
            do {
                if let envKey { c = Credential(key: envKey, base_url: defaultBaseURL, install_id: "") } else if let saved = readCredential() { c = saved } else { c = try await provision() }
                (status, wallet, message) = try await readWallet(c.key)
            } catch {
                _ = await ask(ui, gateScreen("unreachable", message: error is URLError ? nil : error.localizedDescription))
                continue
            }
            if status == 401 && envKey == nil { try? write(nil); continue } // a revoked key: provision again
            guard let w = wallet else { _ = await ask(ui, gateScreen("unreachable", message: message)); continue }
            if !w.claimed {
                let a = await ask(ui, gateScreen("sign_in", w, note: signNote), key: c.key, until: signPoll ? signedIn : nil)
                if a == "sign_in", let url = URL(string: w.claimURL ?? c.claim_url ?? "\(origin)/wallet") {
                    ui.open(url); signNote = "Waiting for you to sign in in your browser."; signPoll = true
                }
                if a == "timeout" { signNote = "No sign-in after 10 minutes. Click Sign in with publik to try again."; signPoll = false }
                continue
            }
            var choice = usesAI ? readCredential()?.choice : nil
            if usesAI && choice == nil {
                if hasPlan(w) { planNote = nil; planPoll = false } // the plan is there: Connect your plan
                let a = await ask(ui, gateScreen("choose", w, note: planNote), key: c.key, until: planPoll ? hasPlan : nil)
                planNote = nil; planPoll = false
                if a == "get_plan", let url = URL(string: w.topUpURL) { ui.open(url); planNote = "Waiting for your plan. Finish in your browser."; planPoll = true }
                if a == "timeout" { planNote = "No plan after 10 minutes. Click Get a plan to try again." }
                guard a == "connect" || a == "own_key" else { continue } // "done": the plan is there; the next screen is Connect your plan
                choice = a == "connect" ? "publik" : "own_key"
                setChoice(choice)
            }
            startTelemetry()
            return (c.key, w, choice)
        }
    }

    /// Builder check, run by the BUILT app: PUBLIK_SELF_TEST=1 makes ensureSignedIn() print this line and exit.
    /// In the Simulator: `SIMCTL_CHILD_PUBLIK_SELF_TEST=1 xcrun simctl launch --console-pty booted app.noscroll`.
    static func selfTest() async -> String {
        do {
            let (status, w, message) = try await readWallet(try await provision().key)
            guard w != nil else { throw PublikError(message: message ?? "GET /wallet answered \(status)") }
            return "publik self-test: ok \(appSlug) \(appVersion)"
        } catch is URLError { return "publik self-test: failed: publik is not reachable. Check your connection." }
        catch { return "publik self-test: failed: \(error.localizedDescription)" }
    }

    // ---------- usage counting: /skills/telemetry.md sections 3-5 ----------
    nonisolated(unsafe) private static var telemetryStarted = false

    private static func usageOff() -> Bool {
        let env = ProcessInfo.processInfo.environment
        let dnt = (env["DO_NOT_TRACK"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if !["", "0", "false"].contains(dnt) || ["0", "false", "off"].contains((env["PUBLIK_TELEMETRY"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()) { return true }
        guard let data = try? Data(contentsOf: publikDir.appendingPathComponent("consent.json")),
              let consent = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return consent["usage"] as? Bool == false
    }
    /// One random UUID for this app on this device, in <publik dir>/telemetry.json (mode 0600). iOS keeps it inside the app's own container.
    private static let telemetryInstallID: String = {
        let file = publikDir.appendingPathComponent("telemetry.json")
        func saved() -> String? {
            guard let data = try? Data(contentsOf: file), let id = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["install_id"] as? String,
                  let uuid = UUID(uuidString: id), id.count == 36, Array(id)[14] == "4" else { return nil }
            return uuid.uuidString.lowercased()
        }
        if let id = saved() { return id }
        let fresh = UUID().uuidString.lowercased() // if the file cannot be saved, this ID lasts for this run only
        try? FileManager.default.createDirectory(at: publikDir, withIntermediateDirectories: true)
        let created = ISO8601DateFormatter().string(from: Date())
        let text = Data("{\"install_id\":\"\(fresh)\",\"created_at\":\"\(created)\"}\n".utf8)
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o600) // never over a file that is there
        guard fd >= 0 else { return saved() ?? fresh }
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        h.write(text); try? h.close()
        return fresh
    }()
    private static func sendEvent(_ event: String) async {
        let env = ProcessInfo.processInfo.environment
        func say(_ result: String) { if env["PUBLIK_TELEMETRY_DEBUG"] == "1" { FileHandle.standardError.write(Data("publik-telemetry: \(event) -> \(result)\n".utf8)) } }
        if usageOff() { return say("off (opt-out)") }
        let key = env["PUBLIK_API_KEY"] ?? readCredential()?.key
        var body: [String: Any] = ["v": 1, "app": appSlug, "install_id": telemetryInstallID, "event": event, "app_version": appVersion.hasPrefix("v") ? String(appVersion.dropFirst()) : appVersion, "os": "ios"]
        if let arch { body["arch"] = arch }
        do { say(String(try await request("POST", env["PUBLIK_TELEMETRY_URL"] ?? "\(origin)/api/v1/telemetry", body: body, key: key?.hasPrefix("pk_") == true ? key : nil, timeout: 5).0)) }
        catch { say((error as? URLError).map { "\($0.code.rawValue)" } ?? "error") }
    }
    /// Called by ensureSignedIn(). app_opened now, active_session every 30 minutes; never fails the app, never blocks.
    /// iOS suspends the app in the background, so active_session counts time in the foreground.
    static func startTelemetry() {
        if telemetryStarted { return }
        telemetryStarted = true
        let s = Double(ProcessInfo.processInfo.environment["PUBLIK_TELEMETRY_INTERVAL_SECONDS"] ?? "") ?? 0 // tests only
        let interval = (1...86_400).contains(s) ? s : 1_800
        Task.detached(priority: .background) {
            await sendEvent("app_opened")
            while true { try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)); await sendEvent("active_session") }
        }
    }

    // ---------- publik API calls ----------
    /// A 402 renders its message plus exactly ONE link: this one.
    static func topUpURLFrom402(_ data: Data) -> (message: String, url: URL?) {
        let e = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any]
        return (e?["message"] as? String ?? "Not enough publik API balance.", (e?["top_up_url"] as? String).flatMap(URL.init(string:)))
    }

    /// `POST /search`: web results for `q` (quote a phrase to find it exactly), one published price per search; on 402 the message and the one link.
    static func search(baseURL: String, apiKey: String, q: String, count: Int = 10) async throws -> (results: [[String: Any]], message: String?, url: URL?) {
        let (status, body) = try await request("POST", "\(baseURL)/search", body: ["q": q, "count": count], key: apiKey, timeout: 30)
        if status == 402 { let t = topUpURLFrom402((try? JSONSerialization.data(withJSONObject: body)) ?? Data()); return ([], t.message, t.url) }
        guard status == 200 else { throw PublikError(message: "publik API answered \(status).") }
        return (body["results"] as? [[String: Any]] ?? [], nil, nil)
    }
}
