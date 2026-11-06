import Foundation
import UIKit
import WebKit

protocol GMBridgeDelegate: AnyObject {
    func gmWebView() -> WKWebView?
    func gmShowToast(title: String, text: String)
    func gmOpenInTab(_ urlString: String)
    func gmRegisterMenu(id: Int, name: String, script: String)
    func gmUnregisterMenu(id: Int)
    func gmLog(level: String, text: String)
}

/// Native side of the Tampermonkey-compatible API. All JS -> Swift traffic
/// arrives through a single WKScriptMessageHandler named "gm".
final class GMBridge: NSObject, WKScriptMessageHandler {

    static let shared = GMBridge()
    weak var delegate: GMBridgeDelegate?

    private let lock = NSLock()
    private var tasks: [Int: URLSessionDataTask] = [:]

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let op = body["op"] as? String else { return }
        let ns = body["ns"] as? String ?? "default"

        switch op {
        case "setValue":
            if let key = body["key"] as? String {
                UserScriptManager.shared.setStoredValue(body["value"] ?? NSNull(), key: key, ns: ns)
            }
        case "deleteValue":
            if let key = body["key"] as? String {
                UserScriptManager.shared.deleteStoredValue(key: key, ns: ns)
            }
        case "log":
            delegate?.gmLog(level: body["level"] as? String ?? "log", text: body["text"] as? String ?? "")
        case "notify":
            delegate?.gmShowToast(title: body["title"] as? String ?? "油猴脚本",
                                  text: body["text"] as? String ?? "")
        case "clipboard":
            UIPasteboard.general.string = body["text"] as? String ?? ""
            delegate?.gmShowToast(title: "已复制", text: body["text"] as? String ?? "")
        case "menu":
            delegate?.gmRegisterMenu(id: intValue(body["id"]),
                                     name: body["text"] as? String ?? "菜单命令",
                                     script: body["name"] as? String ?? "")
        case "menuRemove":
            delegate?.gmUnregisterMenu(id: intValue(body["id"]))
        case "openTab":
            if let url = body["url"] as? String { delegate?.gmOpenInTab(url) }
        case "download":
            if let raw = body["url"] as? String { download(raw, name: body["name"] as? String ?? "download") }
        case "xhr":
            performXHR(body)
        case "xhrAbort":
            let id = intValue(body["id"])
            lock.lock()
            let task = tasks.removeValue(forKey: id)
            lock.unlock()
            task?.cancel()
        default:
            break
        }
    }

    private func intValue(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    // MARK: - GM_xmlhttpRequest (no CORS restrictions)

    private func performXHR(_ body: [String: Any]) {
        let id = intValue(body["id"])
        guard let raw = body["url"] as? String, let url = URL(string: raw) else {
            reply(id: id, ok: false, payload: ["error": "invalid url", "status": 0])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = (body["method"] as? String ?? "GET").uppercased()
        request.timeoutInterval = (body["timeout"] as? NSNumber)?.doubleValue ?? 20
        if let headers = body["headers"] as? [String: Any] {
            for (key, value) in headers {
                if let str = value as? String { request.setValue(str, forHTTPHeaderField: key) }
                else if let num = value as? NSNumber { request.setValue(num.stringValue, forHTTPHeaderField: key) }
            }
        }
        if let user = body["user"] as? String, !user.isEmpty {
            let token = Data((user + ":" + (body["password"] as? String ?? "")).utf8).base64EncodedString()
            request.setValue("Basic " + token, forHTTPHeaderField: "Authorization")
        }
        if let data = body["data"] {
            if let str = data as? String {
                request.httpBody = str.data(using: .utf8)
            } else if let json = try? JSONSerialization.data(withJSONObject: data, options: []) {
                request.httpBody = json
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            self.lock.lock()
            self.tasks.removeValue(forKey: id)
            self.lock.unlock()
            let http = response as? HTTPURLResponse
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            var headers: [String] = []
            if let all = http?.allHeaderFields as? [AnyHashable: Any] {
                for (key, value) in all { headers.append("\(key): \(value)") }
            }
            var payload: [String: Any] = [
                "status": http?.statusCode ?? 0,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: http?.statusCode ?? 0),
                "text": text,
                "headers": headers.joined(separator: "\r\n"),
                "finalUrl": http?.url?.absoluteString ?? url.absoluteString
            ]
            var ok = true
            if let error = error {
                ok = false
                payload["error"] = error.localizedDescription
                payload["status"] = 0
            }
            self.reply(id: id, ok: ok, payload: payload)
        }
        lock.lock()
        tasks[id] = task
        lock.unlock()
        task.resume()
    }

    private func reply(id: Int, ok: Bool, payload: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let text = String(data: json, encoding: .utf8) else { return }
        let safe = text
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        let expression = "window.__tm_xhrCallback(" + String(id) + "," + (ok ? "true" : "false") + "," + safe + ");"
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.gmWebView()?.evaluateJavaScript(expression, completionHandler: nil)
        }
    }

    // MARK: - GM_download

    private func download(_ raw: String, name: String) {
        guard let url = URL(string: raw) else { return }
        let task = URLSession.shared.downloadTask(with: url) { [weak self] temp, _, error in
            guard let self = self, let temp = temp, error == nil else {
                DispatchQueue.main.async { self?.delegate?.gmShowToast(title: "下载失败", text: error?.localizedDescription ?? "") }
                return
            }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dest = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: temp, to: dest)
                DispatchQueue.main.async { self.delegate?.gmShowToast(title: "下载完成", text: dest.lastPathComponent) }
            } catch {
                DispatchQueue.main.async { self.delegate?.gmShowToast(title: "保存失败", text: error.localizedDescription) }
            }
        }
        task.resume()
    }
}
