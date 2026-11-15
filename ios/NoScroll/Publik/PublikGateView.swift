import SafariServices
import SwiftUI
import UIKit

/// The UI of the publik gate (Publik.swift): draws each Publik.Screen and returns the button pressed.
/// From publikhq.com/sdk/publik.swift.md, "SwiftUI", for iOS: the sign-in page opens in an in-app
/// browser (SFSafariViewController), so the app stays in the foreground and keeps checking every 3 seconds.
/// It also holds the publik rows of Settings: sign in (optional mode), sign out, delete account, usage counting.
@MainActor
final class PublikGateModel: ObservableObject, PublikGateUI {
    struct BrowserPage: Identifiable { let id = UUID(); let url: URL }

    @Published var screen: Publik.Screen?
    /// The publik page in the in-app browser, or nil.
    @Published var browser: BrowserPage?
    /// True once the person is signed in to publik on this device.
    @Published private(set) var signedIn = false
    /// The publik handle, for "Signed in as" in Settings.
    @Published private(set) var handle: String?
    /// Optional mode: the Sign in with publik sheet (Settings) is open.
    @Published var signInSheet = false
    /// Delete account, step 3: publik's delete page in the in-app browser.
    @Published var deletePage: BrowserPage?
    /// The Settings switch for usage counting (consent.json).
    @Published var usageCounting = Publik.usageConsent {
        didSet { Publik.usageConsent = usageCounting }
    }
    /// A button was pressed and the gate is checking (for example Retry): the buttons show a spinner and do not take taps.
    @Published private(set) var busy = false
    private var busySince: Date?
    private var pick: CheckedContinuation<String?, Never>?
    private var pickID: UUID?
    private var runID: UUID?
    #if PUBLIK_TEST_HOOKS
    /// The PUBLIK_TEST_PRESS hook: the button it names is pressed once, by itself (CI: the layout check after sign-in).
    private var testPress = Publik.hook("PUBLIK_TEST_PRESS")
    #endif

    let mode = Publik.gateMode
    /// Required mode: Sign in with publik stands in front of the app until sign-in. Optional mode: never.
    var showsWall: Bool { mode == .required && !signedIn }

    /// Runs the gate (the gate view's .task). Ends at sign-in, or when the view goes away (optional mode: the sheet closed).
    func run() async {
        guard !signedIn else { signInSheet = false; return }
        let id = UUID()
        runID = id
        let result = await Publik.ensureSignedIn(self)
        guard runID == id else { return } // a newer run took over
        runID = nil
        // Close the in-app browser and wait until its dismissal is complete. Only then does the app's own
        // screen replace the gate: a swap during the dismissal gave that screen no safe area (the title went
        // under the Dynamic Island).
        browser = nil
        await waitUntilBrowserIsGone()
        busy = false
        busySince = nil
        guard let result else { screen = nil; return }
        handle = result.wallet.handle
        signedIn = true
        signInSheet = false
    }

    /// Waits (at most 3 s) until no window shows the in-app browser and no presentation or dismissal is in progress.
    private func waitUntilBrowserIsGone() async {
        for _ in 0..<60 {
            if !Self.browserOrTransitionOnScreen() { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func browserOrTransitionOnScreen() -> Bool {
        func hasBrowser(_ vc: UIViewController) -> Bool { vc is SFSafariViewController || vc.children.contains(where: hasBrowser) }
        let roots = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).compactMap(\.rootViewController)
        for root in roots {
            var vc: UIViewController? = root
            while let v = vc {
                if hasBrowser(v) || v.isBeingPresented || v.isBeingDismissed || v.transitionCoordinator != nil { return true }
                vc = v.presentedViewController
            }
        }
        return false
    }

    /// Optional mode, at launch (RootView's .task): no wall. A device that is signed in starts usage counting.
    func resume() async {
        guard mode == .optional, !signedIn else { return }
        if let w = await Publik.resume() {
            handle = w.handle
            signedIn = true
        }
    }

    /// Settings > Sign out. Required mode then shows Sign in with publik again.
    func signOut() {
        Publik.signOut()
        handle = nil
        screen = nil
        signedIn = false
    }

    /// Settings > Delete account (after the dialog, step 1). Step 2: sign out and delete the publik data on
    /// this device. Step 3: open publik's delete page in the in-app browser. finishDelete() runs when it closes.
    func deleteAccount() {
        Publik.deleteLocalData()
        handle = nil
        deletePage = BrowserPage(url: Publik.deleteAccountURL)
    }

    /// The delete page closed: the device is signed out (required mode: Sign in with publik shows again).
    func finishDelete() {
        screen = nil
        signedIn = false
    }

    func show(_ s: Publik.Screen) async -> String? {
        if Task.isCancelled { return nil }
        // After a press, keep the spinner for at least 0.6 s, so a quick answer (offline: at once) is still seen as a check.
        if let since = busySince {
            let left = 0.6 - Date().timeIntervalSince(since)
            if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
            if Task.isCancelled { return nil }
        }
        busy = false
        busySince = nil
        let id = UUID()
        #if PUBLIK_TEST_HOOKS
        if let action = testPress, s.buttons.contains(where: { $0.action == action }) {
            testPress = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if self.pickID == id { self.press(action) }
            }
        }
        #endif
        return await withTaskCancellationHandler {
            await withCheckedContinuation { c in pick?.resume(returning: nil); screen = s; pick = c; pickID = id }
        } onCancel: {
            Task { @MainActor in if self.pickID == id { self.press(nil) } }
        }
    }

    func press(_ action: String?) {
        guard !busy || action == nil else { return } // one check at a time
        pick?.resume(returning: action)
        pick = nil
        pickID = nil
        if action == nil { screen = nil; busy = false; busySince = nil } else { busy = true; busySince = Date() }
    }

    nonisolated func open(_ url: URL) {
        Task { @MainActor in
            if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                self.browser = BrowserPage(url: url)
            } else {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
}

/// Sign in with publik: the first screen of the app in required mode, a sheet from Settings in optional mode.
/// It shows the title, the body, the note and one button for each of the screen's buttons, and runs the gate in its .task.
struct PublikGateView: View {
    @ObservedObject var model: PublikGateModel

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                if let s = model.screen {
                    VStack(spacing: 14) {
                        Text(s.title)
                            .font(Theme.display(34))
                            .foregroundStyle(Theme.ink)
                        Text(s.body)
                            .font(Theme.body(17))
                            .foregroundStyle(Theme.inkSoft)
                        if let note = s.note {
                            Text(note)
                                .font(Theme.body(15, .semibold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .multilineTextAlignment(.center)
                    Spacer()
                    VStack(spacing: 10) {
                        ForEach(Array(s.buttons.enumerated()), id: \.offset) { index, button in
                            if index == 0 {
                                // While the gate checks (for example after Retry), the first button shows a spinner.
                                PrimaryButton(title: button.label, busy: model.busy) { model.press(button.action) }
                            } else {
                                SecondaryButton(title: button.label, outlined: true) { model.press(button.action) }
                                    .disabled(model.busy)
                            }
                        }
                        // Consent for usage counting (App Store guideline 5.1.1(ii)). The switch is in Settings,
                        // which opens only after sign-in, so the words say "later".
                        Text("After you sign in, \(Publik.appName) tells publik when it opens. You can turn this off later in Settings.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                } else {
                    ProgressView().tint(Theme.ink)
                    Text("Checking your sign-in…")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 12)
                    Spacer()
                }
                if model.mode == .optional {
                    // Optional mode: the app works without publik, so the sheet always has a way out.
                    Button { model.signInSheet = false } label: {
                        Text("Not now")
                            .font(Theme.body(17, .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .sheet(item: $model.browser) { page in
            PublikBrowser(url: page.url).ignoresSafeArea()
        }
        .task { await model.run() }
    }
}

/// SFSafariViewController in SwiftUI.
struct PublikBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
