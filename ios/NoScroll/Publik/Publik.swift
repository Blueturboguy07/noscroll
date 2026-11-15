// Publik.swift — Sign in with publik, usage counting, and publik API as one provider option.
// The publik module from https://publikhq.com/sdk/publik.swift.md, for iOS (the iPhone app of NoScroll).
// Gate mode (PUBLIK_GATE_MODE in ios/Config/App.xcconfig, Info.plist key PublikGateMode):
//   required (default): at launch, before any screen of the app's own: `let gate = await Publik.ensureSignedIn(ui)`;
//   optional: the app opens without the gate; Settings has "Sign in with publik", which runs ensureSignedIn(ui),
//             and at launch `await Publik.resume()` starts usage counting only for a device that is signed in.
// ensureSignedIn(ui):
//   1. loads or provisions this device's publik key (POST /api/v1/installs);
//   2. shows Sign in with publik until GET /api/v1/wallet says "claimed" (required mode: no other way past it);
//   3. when usesAI: asks once how the app pays for AI and stores the answer (setChoice changes it);
//   4. starts usage counting: app_opened now, active_session every 30 minutes (POST /api/v1/telemetry).
// Settings: signOut() (POST /api/v1/installs/revoke), deleteLocalData() before deleteAccountURL, usageConsent.
// iOS changes from the macOS page: os is "ios", the device name comes from UIDevice, the version comes
// from the bundle, there is no terminal UI, the key file is excluded from backups, and the test hooks
// (PUBLIK_API_BASE_URL and the others, see hook()) exist only in builds with the PUBLIK_TEST_HOOKS flag.
import Foundation
import UIKit

/// show(): draw the screen and return the button pressed. When the task is cancelled (the gate saw the sign-in), close it and return nil.
protocol PublikGateUI: Sendable {
    func show(_ screen: Publik.Screen) async -> String?
    func open(_ url: URL)
}

enum Publik {
    static let appSlug = "noscroll"
    /// The full name (Info.plist AppFullName, else CFBundleDisplayName), for the gate's words.
    static let appName = (Bundle.main.object(forInfoDictionaryKey: "AppFullName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "This app"
    /// The release version: MARKETING_VERSION of the app target.
    static let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    /// false: the app calls no model. It still signs in and counts users; it skips the plan screen.
    static let usesAI = false
    /// required: Sign in with publik is the first screen, with no way past it. optional: the app opens without it,
    /// and Sign in with publik is in Settings. Set by PUBLIK_GATE_MODE (build setting) through the Info.plist key PublikGateMode.
    enum GateMode: String { case required, optional }
    static let gateMode: GateMode = (Bundle.main.object(forInfoDictionaryKey: "PublikGateMode") as? String)
        .flatMap { GateMode(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) } ?? .required
    /// Delete account, step 3: publik's bare in-app delete page (no site navigation, prices or plan links),
    /// opened in the in-app browser. PublikLinks (NoScrollCore) builds every publik page the app opens.
    static var deleteAccountURL: URL { PublikLinks.deleteAccountURL(origin: origin) ?? publikDeleteAccountURL }
    private static let publikDeleteAccountURL = URL(string: "https://publikhq.com/in-app/delete-account")!
    /// The privacy policy: publik's bare in-app page, opened in the in-app browser.
    static var privacyURL: URL { PublikLinks.privacyURL(origin: origin) ?? publikPrivacyURL }
    private static let publikPrivacyURL = URL(string: "https://publikhq.com/in-app/privacy")!

    /// The test hooks: PUBLIK_API_BASE_URL, PUBLIK_ORIGIN, PUBLIK_TELEMETRY_URL, PUBLIK_SELF_TEST, PUBLIK_API_KEY,
    /// PUBLIK_APP_TOKEN, PUBLIK_TELEMETRY_INTERVAL_SECONDS, PUBLIK_TELEMETRY_DEBUG, PUBLIK_TEST_PRESS (the gate presses
    /// this button once by itself) and PUBLIK_LAYOUT_PROBE (the first onboarding screen prints its layout and the app
    /// exits), from the environment or a launch argument (`-NAME value`). They are compiled in only with the PUBLIK_TEST_HOOKS flag (ios/Config/App.xcconfig:
    /// the Debug configuration and the CI test builds). The App Store Release build has none: it always talks to publik.
    static func hook(_ name: String) -> String? {
        #if PUBLIK_TEST_HOOKS
        let raw = ProcessInfo.processInfo.environment[name] ?? UserDefaults.standard.string(forKey: name)
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
        #else
        return nil
        #endif
    }
    /// A hook value that is an http(s) URL with a host, without a trailing "/". Any other value is ignored.
    static func hookURL(_ name: String) -> String? {
        guard var value = hook(name) else { return nil }
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return value
    }
    /// The test hook of the blind test: PUBLIK_API_BASE_URL, for example http://127.0.0.1:8787/api/v1. Unset: publik itself.
    static let testBaseURL: String? = hookURL("PUBLIK_API_BASE_URL")
    static let origin: String = {
        if let base = testBaseURL { return base.hasSuffix("/api/v1") ? String(base.dropLast("/api/v1".count)) : base }
        return hookURL("PUBLIK_ORIGIN") ?? "https://publikhq.com" // PUBLIK_ORIGIN: tests only
    }()
    static let defaultBaseURL = "\(origin)/api/v1"
    /// Ask for a tier, never a vendor model name.
    static let models = (fast: "publik-fast", balanced: "publik-balanced", smart: "publik-smart")

    /// The key file. `claimed` is the local "signed in" mark: set when GET /wallet says "claimed", cleared only by
    /// publik's own answer (a JSON 401, or a wallet that is not claimed). With it, the app opens when publik is not
    /// reachable (offline, 5xx, 408, 429, a captive-portal page). A fresh install has no mark and needs publik once.
    struct Credential: Codable { var key: String; var base_url: String; var install_id: String; var claim_url: String?; var choice: String?; var claimed: Bool?; var handle: String? }
    struct Wallet: Sendable { var claimed: Bool; var claimURL: String?; var handle: String?; var planKind: String; var planLabel: String?; var balanceMicros: Int; var topUpURL: String }
    struct Screen: Sendable { let id: String; let title: String; let body: String; let note: String?; let buttons: [(action: String, label: String)] }
    enum Provider { case own(baseURL: String, apiKey: String), publik(baseURL: String, apiKey: String), needsOwnKey }
    struct PublikError: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// publik-app-token.txt in the app bundle (the "publik app token" build phase puts it there; a Release build
    /// without it fails). The PUBLIK_APP_TOKEN hook comes first in test builds.
    static var appToken: String {
        if let hooked = hook("PUBLIK_APP_TOKEN") { return hooked }
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
        excludeFromBackup(publikDir)
        try (c.map { try JSONEncoder().encode($0) } ?? Data("{}".utf8)).write(to: credentialURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialURL.path)
        excludeFromBackup(credentialURL) // an atomic write makes a new file, so set it again each time
    }
    /// The key must not go to iCloud or computer backups: it belongs to this device only.
    private static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }
    /// The person's answer to the plan screen: "publik", "own_key", or nil to ask again. Settings call it.
    static func setChoice(_ choice: String?) { if var c = readCredential() { c.choice = choice; try? write(c) } }

    /// The key this app uses: the stored choice decides. PUBLIK_API_KEY / PUBLIK_API_BASE_URL override (development).
    static func resolveProvider(userKey: (baseURL: String, apiKey: String)?) -> Provider {
        if let key = hook("PUBLIK_API_KEY") { return .publik(baseURL: defaultBaseURL, apiKey: key) } // defaultBaseURL follows PUBLIK_API_BASE_URL
        if let c = readCredential(), c.choice == "publik" { return .publik(baseURL: c.base_url, apiKey: c.key) }
        if let u = userKey, !u.apiKey.isEmpty { return .own(baseURL: u.baseURL, apiKey: u.apiKey) }
        return .needsOwnKey
    }

    private static func request(_ method: String, _ url: String, body: [String: Any]? = nil, key: String? = nil, timeout: TimeInterval = 20) async throws -> (Int, [String: Any]) {
        let (status, json) = try await requestJSON(method, url, body: body, key: key, timeout: timeout)
        return (status, json ?? [:])
    }
    /// The status and the JSON object of the answer; nil when the answer is not a JSON object (for example a captive-portal page).
    private static func requestJSON(_ method: String, _ url: String, body: [String: Any]? = nil, key: String? = nil, timeout: TimeInterval = 20) async throws -> (Int, [String: Any]?) {
        guard let target = URL(string: url) else { throw PublikError(message: "publik address is not valid.") }
        var req = URLRequest(url: target, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let key { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
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
        let a = try await walletAnswer(key)
        return (a.status, a.wallet, a.message)
    }
    /// GET /api/v1/wallet with `json`: true when the answer is a JSON object (publik's own answer, not a captive portal's page).
    static func walletAnswer(_ key: String, timeout: TimeInterval = 15) async throws -> (status: Int, wallet: Wallet?, message: String?, json: Bool) {
        let (status, json) = try await requestJSON("GET", "\(origin)/api/v1/wallet", key: key, timeout: timeout)
        let b = json ?? [:]
        guard status == 200, let state = b["claim_state"] as? String else { return (status, nil, (b["error"] as? [String: Any])?["message"] as? String, json != nil) }
        let plan = b["plan"] as? [String: Any]
        return (status, Wallet(claimed: state == "claimed", claimURL: b["claim_url"] as? String, handle: (b["account"] as? [String: Any])?["handle"] as? String,
                               planKind: plan?["kind"] as? String ?? "none", planLabel: plan?["label"] as? String, balanceMicros: b["balance_micros"] as? Int ?? 0,
                               topUpURL: b["top_up_url"] as? String ?? "\(origin)/wallet"), nil, true)
    }

    /// The local "signed in" mark (see Credential). Kept with the key; Sign out deletes both.
    private static func mark(claimed: Bool, handle: String? = nil) {
        guard var c = readCredential() else { return }
        let newHandle = claimed ? (handle ?? c.handle) : nil
        if (c.claimed == true) == claimed && c.handle == newHandle { return }
        c.claimed = claimed ? true : nil
        c.handle = newHandle
        try? write(c)
    }
    /// A device with the mark, when publik does not answer: the wallet from the mark.
    private static func markedWallet(_ c: Credential) -> Wallet {
        Wallet(claimed: true, claimURL: c.claim_url, handle: c.handle, planKind: "none", planLabel: nil, balanceMicros: 0, topUpURL: "\(origin)/wallet")
    }

    /// The words of the gate. The same in every publik module.
    static func gateScreen(_ id: String, _ w: Wallet? = nil, note: String? = nil, message: String? = nil) -> Screen {
        if id == "unreachable" { return Screen(id: id, title: "Sign in with publik", body: message ?? "publik is not reachable. Check your connection.", note: note, buttons: [("retry", "Retry")]) }
        if id == "sign_in" {
            // The contract words, for a phone: what to do and what happens. iOS: the publik page opens in the
            // app and closes by itself after the sign-in.
            return Screen(id: id, title: "Sign in with publik", body: "\(appName) uses your publik account. Tap Sign in with publik and sign in on the publik page. The page then closes, and \(appName) opens by itself.",
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
    /// Returns nil only when its task is cancelled (optional mode: the person closed the sign-in sheet).
    static func ensureSignedIn(_ ui: PublikGateUI) async -> (key: String, wallet: Wallet, choice: String?)? {
        await selfTestIfAsked()
        var signNote: String?, signPoll = true, planNote: String?, planPoll = false
        let signedIn: @Sendable (Wallet) -> Bool = { $0.claimed }, hasPlan: @Sendable (Wallet) -> Bool = { $0.planKind != "none" || $0.balanceMicros > 0 }
        while true {
            if Task.isCancelled { return nil }
            let envKey = hook("PUBLIK_API_KEY")
            let saved = envKey == nil ? readCredential() : nil
            // Signed in before on this device: open even when publik does not answer (offline, 5xx, 408, 429, a captive portal).
            let marked = saved?.claimed == true && !(usesAI && saved?.choice == nil)
            let c: Credential, answer: (status: Int, wallet: Wallet?, message: String?, json: Bool)
            do {
                if let envKey { c = Credential(key: envKey, base_url: defaultBaseURL, install_id: "") } else if let saved { c = saved } else { c = try await provision() }
                answer = try await walletAnswer(c.key, timeout: marked ? 8 : 15)
            } catch {
                if marked, let saved { return await openWithMark(saved) }
                _ = await ask(ui, gateScreen("unreachable", message: error is URLError ? nil : error.localizedDescription))
                continue
            }
            if answer.status == 401 && answer.json && envKey == nil { try? write(nil); continue } // publik's own 401: a revoked key; provision again
            guard let w = answer.wallet else {
                if marked, let saved { return await openWithMark(saved) }
                _ = await ask(ui, gateScreen("unreachable", message: answer.message))
                continue
            }
            if !w.claimed {
                if saved?.claimed == true { mark(claimed: false) } // publik says this device is not signed in
                let a = await ask(ui, gateScreen("sign_in", w, note: signNote), key: c.key, until: signPoll ? signedIn : nil)
                if a == "sign_in" {
                    // Only publik's bare in-app sign-in page (claim_url + in_app=1); never a page with site links,
                    // prices or plans. The wallet poll (signedIn) closes the in-app browser after the sign-in.
                    if let url = (w.claimURL ?? c.claim_url).flatMap(PublikLinks.inAppClaimURL) {
                        ui.open(url); signNote = "Waiting for you to sign in on the publik page."; signPoll = true
                    } else {
                        signNote = "publik sent no sign-in page. Tap Sign in with publik to try again."
                    }
                }
                if a == "timeout" { signNote = "No sign-in after 10 minutes. Tap Sign in with publik to try again."; signPoll = false }
                continue
            }
            if envKey == nil { mark(claimed: true, handle: w.handle) }
            var choice = usesAI ? readCredential()?.choice : nil
            if usesAI && choice == nil {
                if hasPlan(w) { planNote = nil; planPoll = false } // the plan is there: Connect your plan
                let a = await ask(ui, gateScreen("choose", w, note: planNote), key: c.key, until: planPoll ? hasPlan : nil)
                planNote = nil; planPoll = false
                if a == "get_plan", let url = URL(string: w.topUpURL) { ui.open(url); planNote = "Waiting for your plan. Finish on the publik page."; planPoll = true }
                if a == "timeout" { planNote = "No plan after 10 minutes. Tap Get a plan to try again." }
                guard a == "connect" || a == "own_key" else { continue } // "done": the plan is there; the next screen is Connect your plan
                choice = a == "connect" ? "publik" : "own_key"
                setChoice(choice)
            }
            await startTelemetry()
            return (c.key, w, choice)
        }
    }

    /// The gate passes on the local mark: publik did not answer, and this device signed in before.
    private static func openWithMark(_ c: Credential) async -> (key: String, wallet: Wallet, choice: String?) {
        await startTelemetry() // events that cannot reach publik are dropped; nothing waits for them
        return (c.key, markedWallet(c), usesAI ? c.choice : nil)
    }

    /// Optional mode, at launch: no screen. A saved key that GET /wallet says is signed in starts usage counting.
    /// Returns the wallet when signed in (also from the local mark when publik does not answer); nil when not signed in.
    static func resume() async -> Wallet? {
        await selfTestIfAsked()
        guard let c = readCredential() else { return nil }
        let marked = c.claimed == true
        guard let a = try? await walletAnswer(c.key, timeout: marked ? 8 : 15) else {
            if marked { return await openWithMark(c).wallet }
            return nil
        }
        if a.status == 401 && a.json { try? write(nil); return nil } // publik's own 401: a revoked key
        guard let w = a.wallet else {
            if marked { return await openWithMark(c).wallet }
            return nil
        }
        guard w.claimed else { if marked { mark(claimed: false) }; return nil }
        mark(claimed: true, handle: w.handle)
        await startTelemetry()
        return w
    }

    /// Sign out: stop usage counting, delete the key file FIRST, then revoke the key (POST /api/v1/installs/revoke)
    /// with the key held in memory, in a detached task that no screen can cancel. Best effort; the publik account stays.
    @MainActor static func signOut() {
        stopTelemetry()
        let key = readCredential()?.key
        try? FileManager.default.removeItem(at: credentialURL)
        guard let key else { return }
        let url = "\(origin)/api/v1/installs/revoke"
        Task.detached(priority: .utility) { _ = try? await request("POST", url, key: key, timeout: 10) }
    }

    /// Delete account, step 2: sign out, then delete this app's publik data on the device (the key and the
    /// usage-counting id, also the id in memory). consent.json stays, so a "do not count" choice stays.
    @MainActor static func deleteLocalData() {
        signOut()
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: publikDir, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent != "consent.json" {
            try? fm.removeItem(at: url)
        }
        resetTelemetryInstallID()
    }

    /// The PUBLIK_SELF_TEST hook: print the self-test line and exit (both gate modes). Test builds only.
    static func selfTestIfAsked() async {
        if hook("PUBLIK_SELF_TEST") != nil { print(await selfTest()); exit(0) }
    }

    /// Builder check, run by the BUILT app: PUBLIK_SELF_TEST=1 makes ensureSignedIn() (or resume()) print this line and exit.
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
    /// The one usage-counting timer. Only the main actor starts or stops it, so there are never two.
    @MainActor private static var telemetryTask: Task<Void, Never>?

    /// The Settings switch: false writes {"usage": false} to <publik dir>/consent.json, and then no event is sent.
    static var usageConsent: Bool {
        get {
            guard let data = try? Data(contentsOf: publikDir.appendingPathComponent("consent.json")),
                  let consent = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return true }
            return consent["usage"] as? Bool != false
        }
        set {
            try? FileManager.default.createDirectory(at: publikDir, withIntermediateDirectories: true)
            try? Data("{\"usage\":\(newValue)}\n".utf8).write(to: publikDir.appendingPathComponent("consent.json"), options: .atomic)
        }
    }

    private static func usageOff() -> Bool {
        let env = ProcessInfo.processInfo.environment
        let dnt = (env["DO_NOT_TRACK"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if !["", "0", "false"].contains(dnt) || ["0", "false", "off"].contains((env["PUBLIK_TELEMETRY"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()) { return true }
        guard let data = try? Data(contentsOf: publikDir.appendingPathComponent("consent.json")),
              let consent = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return consent["usage"] as? Bool == false
    }
    private static let telemetryIDLock = NSLock()
    nonisolated(unsafe) private static var cachedTelemetryID: String?
    /// One random UUID for this app on this device, in <publik dir>/telemetry.json (mode 0600), kept in memory after
    /// the first read. iOS keeps it inside the app's own container.
    private static func telemetryInstallID() -> String {
        telemetryIDLock.lock()
        defer { telemetryIDLock.unlock() }
        if let id = cachedTelemetryID { return id }
        let id = loadOrCreateTelemetryID()
        cachedTelemetryID = id
        return id
    }
    /// Delete account: forget the id in memory too, so a later count uses a new id.
    static func resetTelemetryInstallID() {
        telemetryIDLock.lock()
        cachedTelemetryID = nil
        telemetryIDLock.unlock()
    }
    private static func loadOrCreateTelemetryID() -> String {
        let file = publikDir.appendingPathComponent("telemetry.json")
        func saved() -> String? {
            guard let data = try? Data(contentsOf: file), let id = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["install_id"] as? String,
                  let uuid = UUID(uuidString: id), id.count == 36, Array(id)[14] == "4" else { return nil }
            return uuid.uuidString.lowercased()
        }
        if let id = saved() { return id }
        let fresh = UUID().uuidString.lowercased() // if the file cannot be saved, this ID lasts for this run only
        try? FileManager.default.createDirectory(at: publikDir, withIntermediateDirectories: true)
        excludeFromBackup(publikDir)
        let created = ISO8601DateFormatter().string(from: Date())
        let text = Data("{\"install_id\":\"\(fresh)\",\"created_at\":\"\(created)\"}\n".utf8)
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o600) // never over a file that is there
        guard fd >= 0 else { return saved() ?? fresh }
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        h.write(text); try? h.close()
        return fresh
    }
    private static func sendEvent(_ event: String) async {
        let debug = hook("PUBLIK_TELEMETRY_DEBUG") == "1"
        func say(_ result: String) { if debug { FileHandle.standardError.write(Data("publik-telemetry: \(event) -> \(result)\n".utf8)) } }
        if usageOff() { return say("off (opt-out)") }
        let key = hook("PUBLIK_API_KEY") ?? readCredential()?.key
        var body: [String: Any] = ["v": 1, "app": appSlug, "install_id": telemetryInstallID(), "event": event, "app_version": appVersion.hasPrefix("v") ? String(appVersion.dropFirst()) : appVersion, "os": "ios"]
        if let arch { body["arch"] = arch }
        do { say(String(try await request("POST", hookURL("PUBLIK_TELEMETRY_URL") ?? "\(origin)/api/v1/telemetry", body: body, key: key?.hasPrefix("pk_") == true ? key : nil, timeout: 5).0)) }
        catch { say((error as? URLError).map { "\($0.code.rawValue)" } ?? "error") }
    }
    /// Called by ensureSignedIn() and resume(): only after sign-in. app_opened now, active_session every 30 minutes;
    /// never fails the app, never blocks. iOS suspends the app in the background, so active_session counts time in the foreground.
    @MainActor static func startTelemetry() {
        if telemetryTask != nil { return }
        let s = Double(hook("PUBLIK_TELEMETRY_INTERVAL_SECONDS") ?? "") ?? 0 // tests only
        let interval = (1...86_400).contains(s) ? s : 1_800
        telemetryTask = Task.detached(priority: .background) {
            await sendEvent("app_opened")
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await sendEvent("active_session")
            }
        }
    }
    /// Sign out and delete account stop usage counting.
    @MainActor static func stopTelemetry() {
        telemetryTask?.cancel()
        telemetryTask = nil
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
