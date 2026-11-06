import UIKit
import WebKit

struct MenuCommand {
    let id: Int
    let name: String
    let script: String
}

final class BrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate, GMBridgeDelegate {

    private let addressField = UITextField()
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let containerView = UIView()
    private let toolbar = UIToolbar()
    private var backItem: UIBarButtonItem!
    private var forwardItem: UIBarButtonItem!
    private var scriptsItem: UIBarButtonItem!
    private var tabsItem: UIBarButtonItem!

    private var webView: WKWebView?
    private var progressObservation: NSKeyValueObservation?
    private var history: [URL] = []
    private var historyIndex: Int = -1
    private var currentSignature = ""
    private var injectedCount = 0
    private var menuCommands: [MenuCommand] = []
    private var logs: [String] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        GMBridge.shared.delegate = self
        UserScriptManager.shared.load()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(scriptsDidChange),
                                               name: NSNotification.Name("userscriptsDidChange"),
                                               object: nil)
        if let home = URL(string: "https://example.com/") {
            loadURL(home, push: true)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.97, alpha: 1)

        let topBar = UIView()
        topBar.backgroundColor = UIColor(white: 0.96, alpha: 1)
        topBar.heightAnchor.constraint(equalToConstant: 48).isActive = true

        addressField.borderStyle = .roundedRect
        addressField.backgroundColor = .white
        addressField.placeholder = "输入网址或搜索"
        addressField.font = UIFont.systemFont(ofSize: 13)
        addressField.keyboardType = .URL
        addressField.returnKeyType = .go
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.clearButtonMode = .whileEditing
        addressField.delegate = self

        let reloadButton = UIButton(type: .system)
        reloadButton.setTitle("刷新", for: .normal)
        reloadButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)

        topBar.addSubview(addressField)
        topBar.addSubview(reloadButton)
        addressField.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addressField.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            addressField.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            addressField.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -8),
            reloadButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -10),
            reloadButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 34)
        ])

        progressView.progressTintColor = UIColor(red: 0.18, green: 0.42, blue: 1.0, alpha: 1)
        progressView.trackTintColor = .clear
        progressView.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])

        statusLabel.font = UIFont.systemFont(ofSize: 10)
        statusLabel.textColor = .darkGray
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor(white: 0.93, alpha: 1)
        statusLabel.heightAnchor.constraint(equalToConstant: 20).isActive = true

        backItem = UIBarButtonItem(title: "‹", style: .plain, target: self, action: #selector(backTapped))
        forwardItem = UIBarButtonItem(title: "›", style: .plain, target: self, action: #selector(forwardTapped))
        scriptsItem = UIBarButtonItem(title: "脚本(0)", style: .plain, target: self, action: #selector(scriptsTapped))
        tabsItem = UIBarButtonItem(title: "标签(0)", style: .plain, target: self, action: #selector(tabsTapped))
        let flex = { UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }
        toolbar.items = [backItem, flex(), forwardItem, flex(), scriptsItem, flex(), tabsItem]
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true

        containerView.setContentHuggingPriority(.defaultLow, for: .vertical)
        for arranged in [topBar, statusLabel, containerView, toolbar] {
            arranged.translatesAutoresizingMaskIntoConstraints = false
        }
        let stack = UIStackView(arrangedSubviews: [topBar, statusLabel, containerView, toolbar])
        stack.axis = .vertical
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func updateChrome() {
        backItem.isEnabled = historyIndex > 0
        forwardItem.isEnabled = historyIndex < history.count - 1
        scriptsItem.title = "脚本(\(injectedCount))"
        tabsItem.title = "标签(\(history.count))"
        statusLabel.text = "已注入 \(injectedCount) 个脚本 · 菜单 \(menuCommands.count) · 日志 \(logs.count)"
    }

    // MARK: - Navigation

    func makeURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if !text.contains("://") {
            if text.contains(" ") || !text.contains(".") {
                let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
                text = "https://www.bing.com/search?q=" + query
            } else {
                text = "https://" + text
            }
        }
        return URL(string: text)
    }

    func loadURL(_ url: URL, push: Bool) {
        if push {
            if historyIndex < history.count - 1 {
                history = Array(history.prefix(historyIndex + 1))
            }
            history.append(url)
            historyIndex = history.count - 1
        }
        let matched = UserScriptManager.shared.matching(url)
        currentSignature = matched.map { $0.id }.joined(separator: ",")
        injectedCount = matched.count
        menuCommands.removeAll()
        addressField.text = url.absoluteString
        updateChrome()

        let newWebView = makeWebView(for: url)
        webView?.removeFromSuperview()
        webView = newWebView
        progressObservation = nil
        newWebView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(newWebView)
        NSLayoutConstraint.activate([
            newWebView.topAnchor.constraint(equalTo: containerView.topAnchor),
            newWebView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            newWebView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            newWebView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        progressObservation = newWebView.observe(\WKWebView.estimatedProgress, options: [.new]) { [weak self] _, change in
            let value = Float(change.newValue ?? 0)
            DispatchQueue.main.async { self?.progressView.progress = value }
        }
        newWebView.load(URLRequest(url: url))
    }

    private func makeWebView(for url: URL) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(WeakScriptMessageHandler(GMBridge.shared), name: "gm")

        let runtime = UserScriptManager.shared.runtimeJS
        if !runtime.isEmpty {
            controller.addUserScript(WKUserScript(source: runtime,
                                                 injectionTime: .atDocumentStart,
                                                 forMainFrameOnly: true))
        }
        for script in UserScriptManager.shared.matching(url) {
            let source = UserScriptManager.shared.source(for: script)
            let time: WKUserScriptInjectionTime =
                script.runAt.lowercased() == "document-start" ? .atDocumentStart : .atDocumentEnd
            controller.addUserScript(WKUserScript(source: source,
                                                 injectionTime: time,
                                                 forMainFrameOnly: true))
        }

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        return web
    }

    @objc private func reloadTapped() {
        if let url = webView?.url { loadURL(url, push: false) }
    }

    @objc private func backTapped() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        loadURL(history[historyIndex], push: false)
    }

    @objc private func forwardTapped() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        loadURL(history[historyIndex], push: false)
    }

    @objc private func scriptsTapped() {
        let library = ScriptLibraryViewController()
        library.browser = self
        present(UINavigationController(rootViewController: library), animated: true, completion: nil)
    }

    @objc private func tabsTapped() {
        let tabs = TabsViewController()
        tabs.browser = self
        tabs.urls = history
        present(UINavigationController(rootViewController: tabs), animated: true, completion: nil)
    }

    @objc private func scriptsDidChange() {
        if let url = webView?.url { loadURL(url, push: false) }
    }

    // MARK: - Public surface for the panels

    var currentURL: URL? { return webView?.url }
    func menuItems() -> [MenuCommand] { return menuCommands }
    func logLines() -> [String] { return logs }
    func matchedNames() -> [String] {
        guard let url = webView?.url else { return [] }
        return UserScriptManager.shared.matching(url).map { $0.name }
    }
    func runMenuCommand(_ id: Int) {
        let expression = "window.__tm_menuClick(" + String(id) + ");"
        webView?.evaluateJavaScript(expression, completionHandler: nil)
    }
    func openURL(_ raw: String) {
        if let url = makeURL(raw) { loadURL(url, push: true) }
    }
    func clearLogs() { logs.removeAll(); updateChrome() }
    func historyURLs() -> [URL] { return history }
    func jumpTo(index: Int) {
        guard index >= 0, index < history.count else { return }
        historyIndex = index
        loadURL(history[index], push: false)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            decisionHandler(.allow)
            return
        }
        let isMain = navigationAction.targetFrame?.isMainFrame ?? true
        if isMain {
            let signature = UserScriptManager.shared.signature(for: url)
            if signature != currentSignature {
                // Rebuild the web view so the new page gets the right WKUserScripts.
                decisionHandler(.cancel)
                DispatchQueue.main.async { self.loadURL(url, push: true) }
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url { addressField.text = url.absoluteString }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progressView.progress = 0
        statusLabel.text = "已注入 \(injectedCount) 个脚本 · \(webView.url?.host ?? "") · 菜单 \(menuCommands.count)"
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        progressView.progress = 0
        Toast.show(title: "加载失败", text: error.localizedDescription, in: view)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        progressView.progress = 0
        Toast.show(title: "无法连接网站", text: error.localizedDescription, in: view)
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { loadURL(url, push: true) }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true, completion: nil)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true, completion: nil)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if let url = makeURL(textField.text ?? "") { loadURL(url, push: true) }
        return true
    }

    // MARK: - GMBridgeDelegate

    func gmWebView() -> WKWebView? { return webView }

    func gmShowToast(title: String, text: String) {
        Toast.show(title: title, text: text, in: view)
    }

    func gmOpenInTab(_ urlString: String) {
        if let url = makeURL(urlString) { loadURL(url, push: true) }
    }

    func gmRegisterMenu(id: Int, name: String, script: String) {
        menuCommands.append(MenuCommand(id: id, name: name, script: script))
        updateChrome()
    }

    func gmUnregisterMenu(id: Int) {
        menuCommands.removeAll { $0.id == id }
        updateChrome()
    }

    func gmLog(level: String, text: String) {
        logs.append("[\(level)] " + text)
        if logs.count > 300 { logs.removeFirst() }
    }
}

