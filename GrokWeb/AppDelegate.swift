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

    // Native controls remain accessible even if the site's preview covers the page.
    private lazy var toolsButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("预览 ⋯", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        b.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.94)
        b.layer.cornerRadius = 16
        b.layer.borderWidth = 0.5
        b.layer.borderColor = UIColor.separator.cgColor
        b.addTarget(self, action: #selector(showPreviewMenu), for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.accessibilityLabel = "预览操作"
        return b
    }()

    @objc private func showPreviewMenu() {
        let menu = UIAlertController(title: "Grok 预览操作", message: "不会删除对话或清除登录状态。", preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "尝试关闭网页预览", style: .default) { [weak self] _ in
            self?.tryCloseWebPreview()
        })
        menu.addAction(UIAlertAction(title: "网页后退", style: .default) { [weak self] _ in
            guard let self = self else { return }
            if self.webView.canGoBack { self.webView.goBack() }
            else { self.showMessage("当前没有可后退的网页历史。") }
        })
        menu.addAction(UIAlertAction(title: "重新加载网页", style: .default) { [weak self] _ in
            self?.webView.reload()
        })
        menu.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = menu.popoverPresentationController {
            pop.sourceView = toolsButton
            pop.sourceRect = toolsButton.bounds
        }
        present(menu, animated: true)
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: "GrokWeb", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func tryCloseWebPreview() {
        // Only attempt a close button inside a visible dialog/preview overlay.
        // Never remove nodes or spoof a click on an unlabeled site control.
        let script = #"""
        (function () {
          const roots = Array.from(document.querySelectorAll(
            '[role="dialog"], [aria-modal="true"], [data-state="open"], [class*="preview" i], [class*="modal" i]'
          ));
          function visible(el) {
            if (!el || !el.isConnected) return false;
            const r = el.getBoundingClientRect();
            const s = getComputedStyle(el);
            return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
          }
          const candidates = [];
          for (const root of roots) {
            if (!visible(root)) continue;
            const rs = root.getBoundingClientRect();
            if (rs.width < 160 || rs.height < 160) continue;
            for (const b of root.querySelectorAll('button,[role="button"]')) {
              if (!visible(b)) continue;
              const label = [b.getAttribute('aria-label'), b.getAttribute('title'), b.textContent]
                .filter(Boolean).join(' ').trim().toLowerCase();
              if (/^(close|dismiss|关闭|关闭预览|退出预览|×|✕|✖)$/.test(label))
                candidates.push(b);
            }
          }
          if (candidates.length) { candidates[candidates.length - 1].click(); return 'closed'; }
          return 'not-found';
        })();
        """#
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self else { return }
            if error != nil || (result as? String) != "closed" {
                self.showMessage("未找到可识别的网页预览关闭按钮。请尝试“网页后退”；如果也无效，可重新加载网页。")
            }
        }
    }

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
          if (window.__grokComposerFixV4) return;
          window.__grokComposerFixV4 = true;
          var STYLE_ID = 'grok-ios16-composer-fix-v4';
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
              /* V4: repair the empty-editor hint without moving actual input text. */
              .grok-ios16-hint-fix::placeholder {
                line-height: 24px !important;
                opacity: 1 !important;
                overflow: visible !important;
              }
              .grok-ios16-hint-fix:placeholder-shown {
                min-height: 48px !important;
                padding-top: 10px !important;
                padding-bottom: 10px !important;
              }
              .grok-ios16-hint-fix [data-placeholder]::before,
              .grok-ios16-hint-fix [data-placeholder]::after,
              .grok-ios16-hint-fix [data-placeholder]:empty,
              .grok-ios16-hint-fix p.is-editor-empty::before,
              .grok-ios16-hint-fix p.is-empty::before,
              .grok-ios16-hint-fix.is-editor-empty::before {
                line-height: 24px !important;
                padding-top: 0 !important;
                margin-top: 0 !important;
                transform: none !important;
                -webkit-transform: none !important;
                vertical-align: baseline !important;
                overflow: visible !important;
                clip: auto !important;
                text-indent: 0 !important;
              }
              .grok-ios16-hint-fix [data-placeholder] {
                overflow: visible !important;
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
          // Mark only editable controls so placeholder rules do not change other
          // text, buttons or the site's navigation. Covers editors before focus.
          function markEditors(root) {
            if (!root || !root.querySelectorAll) return;
            var items = root.querySelectorAll('textarea,[contenteditable="true"],[role="textbox"][contenteditable]');
            for (var i = 0; i < items.length; i++) {
              if (!items[i].classList.contains('grok-ios16-hint-fix'))
                items[i].classList.add('grok-ios16-hint-fix');
            }
          }
          function setupHints() {
            injectStyle();
            markEditors(document);
            if (document.body && window.MutationObserver) {
              var observer = new MutationObserver(function(mutations) {
                // Grok is a SPA: newly mounted editors need the same hint fix.
                mutations.forEach(function(m) {
                  for (var i = 0; i < m.addedNodes.length; i++) {
                    var node = m.addedNodes[i];
                    if (node.nodeType !== 1) continue;
                    if (isEditor(node)) node.classList.add('grok-ios16-hint-fix');
                    markEditors(node);
                  }
                });
              });
              observer.observe(document.body, {childList: true, subtree: true});
            }
          }
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', setupHints, {once:true});
          } else {
            setupHints();
          }
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
        view.addSubview(toolsButton)
        NSLayoutConstraint.activate([
            toolsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            toolsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            toolsButton.widthAnchor.constraint(equalToConstant: 76),
            toolsButton.heightAnchor.constraint(equalToConstant: 32)
        ])

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
