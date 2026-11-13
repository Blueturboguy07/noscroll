import SafariServices
import SwiftUI
import UIKit

/// The UI of the publik gate (Publik.swift): draws each Publik.Screen and returns the button pressed.
/// From publikhq.com/sdk/publik.swift.md, "SwiftUI", for iOS: the sign-in page opens in an in-app
/// browser (SFSafariViewController), so the app stays in the foreground and keeps checking every 3 seconds.
@MainActor
final class PublikGateModel: ObservableObject, PublikGateUI {
    struct BrowserPage: Identifiable { let id = UUID(); let url: URL }

    @Published var screen: Publik.Screen?
    /// The publik page in the in-app browser, or nil.
    @Published var browser: BrowserPage?
    /// True once the gate lets the person through. NoScroll's own screens show only then.
    @Published private(set) var signedIn = false
    private var pick: CheckedContinuation<String?, Never>?
    private var pickID: UUID?
    private var started = false

    /// Runs the gate once per launch (the gate view's .task).
    func run() async {
        guard !started else { return }
        started = true
        _ = await Publik.ensureSignedIn(self)
        browser = nil
        signedIn = true
    }

    func show(_ s: Publik.Screen) async -> String? {
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

/// The first screen of the app: Sign in with publik. It shows the title, the body, the note and one
/// button for each of the screen's buttons, and runs the gate in its .task.
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
                    }
                } else {
                    ProgressView().tint(Theme.ink)
                    Spacer()
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
