import UIKit
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = GrokViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class GrokViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let homeURL = URL(string: "https://grok.com")!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // iOS 16 WebKit workaround for clipped editable text on grok.com.
        // Only the focused composer is patched; no event handlers, values or
        // message-submission logic are replaced.
        let compatibilityJS = #"""
        (function () {
          if (window.__grokComposerFixV3) return;
          window.__grokComposerFixV3 = true;
          var STYLE_ID = 'grok-ios16-composer-fix-v3';
          var activeEditor = null;
          function injectStyle() {
            if (!document.head || document.getElementById(STYLE_ID)) return;
            var s = document.createElement('style');
            s.id = STYLE_ID;
            s.textContent = `
              html { -webkit-text-size-adjust: 100%; }
              .grok-ios16-editor-fix {
                box-sizing: border-box !important;
                min-height: 48px !important;
                height: auto !important;
                line-height: 24px !important;
                padding-top: 10px !important;
                padding-bottom: 10px !important;
                overflow-y: auto !important;
                -webkit-text-fill-color: currentColor;
                transform: none !important;
                -webkit-transform: none !important;
              }
              .grok-ios16-editor-fix p,
              .grok-ios16-editor-fix [data-placeholder] {
                line-height: 24px !important;
                min-height: 24px !important;
                margin-top: 0 !important;
                margin-bottom: 0 !important;
                padding-top: 0 !important;
                padding-bottom: 0 !important;
                transform: none !important;
              }
            `;
            document.head.appendChild(s);
          }
          function isEditor(el) {
            return el && el.nodeType === 1 &&
              (el.matches('textarea,[contenteditable="true"],[role="textbox"][contenteditable]'));
          }
          function setEditor(el) {
            if (!isEditor(el)) return;
            if (activeEditor && activeEditor !== el)
              activeEditor.classList.remove('grok-ios16-editor-fix');
            activeEditor = el;
            injectStyle();
            el.classList.add('grok-ios16-editor-fix');
            // A stale internal scroll offset can render the caret above the
            // text box after keyboard activation on older WebKit builds.
            if (el.matches('textarea') && !el.value) el.scrollTop = 0;
          }
          document.addEventListener('focusin', function(e) {
            setEditor(e.target);
          }, true);
          document.addEventListener('focusout', function(e) {
            if (e.target === activeEditor) {
              activeEditor.classList.remove('grok-ios16-editor-fix');
              activeEditor = null;
            }
          }, true);
          document.addEventListener('DOMContentLoaded', injectStyle);
          injectStyle();
          // SPA re-render can replace the focused editor; reapply on focus only.
          document.addEventListener('click', function(e) {
            var el = e.target && e.target.closest &&
              e.target.closest('textarea,[contenteditable="true"]');
            if (el && document.activeElement === el) setEditor(el);
          }, true);
        })();
        """#
        configuration.userContentController.addUserScript(WKUserScript(source: compatibilityJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .white
        view.addSubview(webView)

        // Do NOT bind the WKWebView bottom edge to keyboardLayoutGuide.
        // WKWebView already adjusts its own scroll/visual viewport for the keyboard;
        // combining both can shrink the site twice and clip a sticky composer.
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        webView.load(URLRequest(url: homeURL))
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if let scheme = url.scheme?.lowercased(), !["http", "https", "about"].contains(scheme) {
            if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}


