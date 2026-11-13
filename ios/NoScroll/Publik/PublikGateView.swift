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
    private var pick: CheckedContinuation<String?, Never>?
    private var pickID: UUID?
    private var runID: UUID?

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
        browser = nil
        guard let result else { screen = nil; return }
        handle = result.wallet.handle
        signedIn = true
        signInSheet = false
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
    func signOut() async {
        await Publik.signOut()
        handle = nil
        screen = nil
        signedIn = false
    }

    /// Settings > Delete account (after the dialog, step 1). Step 2: sign out and delete the publik data on
    /// this device. Step 3: open publik's delete page in the in-app browser. finishDelete() runs when it closes.
    func deleteAccount() async {
        await Publik.deleteLocalData()
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
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { c in pick?.resume(returning: nil); screen = s; pick = c; pickID = id }
        } onCancel: {
            Task { @MainActor in if self.pickID == id { self.press(nil) } }
        }
    }

    func press(_ action: String?) {
        pick?.resume(returning: action)
        pick = nil
        pickID = nil
        if action == nil { screen = nil }
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
                                PrimaryButton(title: button.label) { model.press(button.action) }
                            } else {
                                SecondaryButton(title: button.label, outlined: true) { model.press(button.action) }
                            }
                        }
                        // Consent for usage counting (App Store guideline 5.1.1(ii)); the switch is in Settings.
                        Text("publik counts when this app opens. You can turn this off in Settings.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                } else {
                    ProgressView().tint(Theme.ink)
                    Spacer()
                }
                if model.mode == .optional {
                    // Optional mode: the app works without publik, so the sheet always has a way out.
                    Button("Not now") { model.signInSheet = false }
                        .font(Theme.body(17, .semibold))
                        .foregroundStyle(Theme.inkSoft)
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
