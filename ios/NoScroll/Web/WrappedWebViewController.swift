import AVFoundation
import Foundation
import UIKit
import WebKit

/// The wrapped browser.
///
/// Most of this file exists because of specific, documented failures in the app
/// we are cloning. Each one is annotated with the symptom it prevents — none of
/// this is defensive boilerplate.
final class WrappedWebViewController: UIViewController {

    private let session: WebSession
    private let engineSource: String
    private let bundleRaw: Data
    private let settings: [String: Bool]
    private let telemetry: Bool
    private let onBridge: (BridgeMessage) -> Void

    private var webView: WKWebView!
    private var restorationState: Data?

    init(session: WebSession,
         dataStore: WKWebsiteDataStore,
         engineSource: String,
         bundleRaw: Data,
         settings: [String: Bool],
         telemetry: Bool,
         onBridge: @escaping (BridgeMessage) -> Void) {
        self.session = session
        self.engineSource = engineSource
        self.bundleRaw = bundleRaw
        self.settings = settings
        self.telemetry = telemetry
        self.onBridge = onBridge
        super.init(nibName: nil, bundle: nil)
        configure(dataStore: dataStore)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // MARK: - Configuration

    private func configure(dataStore: WKWebsiteDataStore) {
        let controller = WKUserContentController()

        // The engine runs at documentStart so blocking CSS lands before first
        // paint. Injecting at documentEnd would let a Reel render and then
        // vanish, and that flicker is what makes a blocker feel broken.
        let config = engineConfigJSON()
        let bootstrap = """
        window.__NOSCROLL_CONFIG = \(config);
        \(engineSource)
        """
        controller.addUserScript(WKUserScript(source: bootstrap,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        controller.add(BridgeHandler(onBridge), name: "noscroll")

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = controller
        cfg.websiteDataStore = dataStore

        // Without these, video plays fullscreen-only and is silent unless the
        // ringer is on — a specific, repeated complaint about SocialLite.
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        // Apple 2.5.6: WKWebView only. We use the stock mobile user agent
        // unmodified — a custom UA is a fingerprint that raises the rate of
        // "suspicious login attempt" checkpoints against our users' accounts.
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    private func engineConfigJSON() -> String {
        let bundleJSON = String(data: bundleRaw, encoding: .utf8) ?? "{}"
        let settingsJSON = (try? JSONSerialization.data(withJSONObject: settings))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        { "bundle": \(bundleJSON), "settings": \(settingsJSON), "telemetry": \(telemetry) }
        """
    }

    // MARK: - Lifecycle

    override func loadView() { view = webView }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureAudioSession()
        restoreOrLoad()

        NotificationCenter.default.addObserver(
            self, selector: #selector(saveState),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// Video that plays silently unless the ringer is on is an audio-session
    /// problem, not a WebKit one.
    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// iOS reaps the WebView process under memory pressure. Without restoration,
    /// switching to an authenticator app during 2FA and coming back produces a
    /// white screen and forces a restart — which blocks login entirely. That is
    /// a real, reported SocialLite bug and it is the single worst one, because
    /// the user cannot get past it.
    private func restoreOrLoad() {
        if let state = restorationState ?? UserDefaults.standard.data(forKey: stateKey) {
            webView.interactionState = state
            return
        }
        webView.load(URLRequest(url: homeURL()))
    }

    private var stateKey: String { "noscroll.state.\(session.id.uuidString)" }

    @objc private func saveState() {
        if let state = webView.interactionState as? Data {
            restorationState = state
            UserDefaults.standard.set(state, forKey: stateKey)
        }
    }

    private func homeURL() -> URL {
        switch session.service {
        case "instagram": return URL(string: "https://www.instagram.com/")!
        case "youtube": return URL(string: "https://m.youtube.com/")!
        default: return URL(string: "https://www.instagram.com/")!
        }
    }
}

// MARK: - Navigation

extension WrappedWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }

        // Cancel app-scheme navigations. Instagram's web pages try hard to hand
        // off to the native app; since we have that app shielded, following the
        // link would eject the user into a shield screen mid-flow and look like
        // the wrapper crashed.
        if let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "data", "blob"].contains(scheme) {
            decisionHandler(.cancel); return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        saveState()
    }

    /// A crashed WebView must recover, not sit blank.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        restoreOrLoad()
    }
}

// MARK: - UI delegate

/// WKUIDelegate is MANDATORY, not optional. Without these callbacks, `<input
/// type=file>` pickers and getUserMedia fail *silently* — which is exactly the
/// "can't upload a video to posts/story" complaint against SocialLite. The
/// feature looks broken rather than unsupported.
extension WrappedWebViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Prompt the user via the system permission sheet rather than silently
        // denying. Requires NSCameraUsageDescription / NSMicrophoneUsageDescription.
        decisionHandler(.prompt)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank inside a wrapper should navigate in place, not vanish.
        if let url = navigationAction.request.url, navigationAction.targetFrame == nil {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

// MARK: - Bridge

enum BridgeMessage {
    case probe(ruleId: String, expected: Int, actual: Int, bundleVersion: Int)
    case blocked(ruleId: String, count: Int)
    case route(path: String, blocked: Bool)
    case authSurface(active: Bool)
    case breakage(ruleId: String, detail: String)
    case ready(bundleVersion: Int, service: String)
}

private final class BridgeHandler: NSObject, WKScriptMessageHandler {
    private let onMessage: (BridgeMessage) -> Void
    init(_ onMessage: @escaping (BridgeMessage) -> Void) { self.onMessage = onMessage }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else { return }

        switch type {
        case "probe":
            onMessage(.probe(ruleId: dict["ruleId"] as? String ?? "",
                             expected: dict["expected"] as? Int ?? 0,
                             actual: dict["actual"] as? Int ?? 0,
                             bundleVersion: dict["bundleVersion"] as? Int ?? 0))
        case "blocked":
            onMessage(.blocked(ruleId: dict["ruleId"] as? String ?? "",
                               count: dict["count"] as? Int ?? 0))
        case "route":
            onMessage(.route(path: dict["path"] as? String ?? "",
                             blocked: dict["blocked"] as? Bool ?? false))
        case "auth-surface":
            onMessage(.authSurface(active: dict["active"] as? Bool ?? false))
        case "breakage":
            onMessage(.breakage(ruleId: dict["ruleId"] as? String ?? "",
                                detail: dict["detail"] as? String ?? ""))
        case "ready":
            onMessage(.ready(bundleVersion: dict["bundleVersion"] as? Int ?? 0,
                             service: dict["service"] as? String ?? ""))
        default:
            break
        }
    }
}
