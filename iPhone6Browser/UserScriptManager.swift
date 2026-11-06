import Foundation

struct ScriptRecord: Codable {
    var id: String
    var name: String
    var namespace: String
    var version: String
    var desc: String
    var code: String
    var enabled: Bool
    var match: [String]
    var include: [String]
    var exclude: [String]
    var runAt: String
    var grants: [String]
    var requires: [String]
    var resources: [String: String]
    var builtin: Bool
}

final class UserScriptManager {

    static let shared = UserScriptManager()

    static let apiNames: [String] = [
        "GM_addStyle", "GM_setValue", "GM_getValue", "GM_deleteValue", "GM_listValues",
        "GM_addValueChangeListener", "GM_removeValueChangeListener", "GM_xmlhttpRequest",
        "GM_registerMenuCommand", "GM_unregisterMenuCommand", "GM_notification",
        "GM_openInTab", "GM_setClipboard", "GM_download", "GM_getResourceText",
        "GM_getResourceURL", "GM_getTab", "GM_saveTab", "GM_getTabs", "GM_log",
        "GM_info", "GM", "unsafeWindow"
    ]

    private(set) var scripts: [ScriptRecord] = []

    lazy var runtimeJS: String = {
        guard let url = Bundle.main.url(forResource: "runtime", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("userscripts.json")
    }

    // MARK: - Metadata

    private func metaRows(_ code: String) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for rawLine in code.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("//") else { continue }
            let body = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard body.hasPrefix("@") else { continue }
            let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).replacingOccurrences(of: "@", with: "").lowercased()
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            out[key, default: []].append(value)
        }
        return out
    }

    func parse(_ code: String, id: String? = nil, builtin: Bool = false) -> ScriptRecord {
        let m = metaRows(code)
        func first(_ key: String, _ fallback: String = "") -> String {
            return m[key]?.first ?? fallback
        }
        let identifier = id ?? "us_\(Int(Date().timeIntervalSince1970 * 1000))"
        return ScriptRecord(
            id: identifier,
            name: first("name", "脚本 \(identifier)"),
            namespace: first("namespace", "iphone6.local"),
            version: first("version", "1.0"),
            desc: first("description"),
            code: code,
            enabled: true,
            match: m["match"] ?? [],
            include: m["include"] ?? [],
            exclude: m["exclude"] ?? [],
            runAt: first("run-at", "document-end"),
            grants: m["grant"] ?? [],
            requires: [],
            resources: [:],
            builtin: builtin
        )
    }

    private func glob(_ rawPattern: String, _ text: String) -> Bool {
        var pattern = rawPattern
        if !pattern.contains("://") && !pattern.hasPrefix("*") {
            pattern = "*://" + pattern + (pattern.contains("/") ? "" : "/*")
        }
        var regex = "^"
        for ch in pattern {
            if ch == "*" { regex += ".*" }
            else { regex += NSRegularExpression.escapedPattern(for: String(ch)) }
        }
        regex += "$"
        guard let re = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive]) else { return false }
        return re.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    func matching(_ url: URL) -> [ScriptRecord] {
        let absolute = url.absoluteString
        return scripts.filter { rec in
            guard rec.enabled else { return false }
            for pattern in rec.exclude {
                if glob(pattern, absolute) { return false }
            }
            let patterns = rec.match + rec.include
            if patterns.isEmpty { return true }
            return patterns.contains { glob($0, absolute) }
        }
    }

    func signature(for url: URL) -> String {
        return matching(url).map { $0.id }.joined(separator: ",")
    }

    // MARK: - Persistence

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ScriptRecord].self, from: data),
           !decoded.isEmpty {
            scripts = decoded
        } else {
            loadDefaults()
            save()
        }
    }

    private func loadDefaults() {
        guard let url = Bundle.main.url(forResource: "defaults", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let rows = obj as? [[String: Any]] else { return }
        scripts = rows.enumerated().map { index, row in
            let code = row["code"] as? String ?? ""
            return parse(code, id: "default_\(index + 1)", builtin: true)
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(scripts) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func setEnabled(_ enabled: Bool, id: String) {
        if let idx = scripts.firstIndex(where: { $0.id == id }) {
            scripts[idx].enabled = enabled
            save()
        }
    }

    func remove(id: String) {
        scripts.removeAll { $0.id == id }
        save()
    }

    /// Resolves @require / @resource before storing, so injection stays synchronous.
    func install(code: String, replacingId: String? = nil, completion: @escaping () -> Void) {
        let meta = metaRows(code)
        let requireURLs = meta["require"] ?? []
        let resourceRows = meta["resource"] ?? []
        DispatchQueue.global(qos: .userInitiated).async {
            let requires = requireURLs.map { self.fetchTextSync($0) }
            var resources: [String: String] = [:]
            for row in resourceRows {
                let parts = row.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    resources[String(parts[0])] = self.fetchTextSync(String(parts[1]))
                }
            }
            DispatchQueue.main.async {
                var rec = self.parse(code, id: replacingId, builtin: false)
                rec.requires = requires
                rec.resources = resources
                if let replace = replacingId,
                   let idx = self.scripts.firstIndex(where: { $0.id == replace }) {
                    rec.enabled = self.scripts[idx].enabled
                    self.scripts[idx] = rec
                } else {
                    self.scripts.append(rec)
                }
                self.save()
                completion()
            }
        }
    }

    private func fetchTextSync(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return "/* @require failed: invalid URL */" }
        let semaphore = DispatchSemaphore(value: 0)
        var result = "/* @require failed: \(raw) */"
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let text = String(data: data, encoding: .utf8) { result = text }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 12)
        return result
    }

    // MARK: - GM storage (plists cannot hold NSNull, so store JSON blobs)

    private func storeKey(_ ns: String) -> String { return "gm.store." + ns }

    func storedValues(for ns: String) -> [String: Any] {
        var out: [String: Any] = [:]
        let dict = UserDefaults.standard.dictionary(forKey: storeKey(ns)) ?? [:]
        for (key, value) in dict {
            guard let data = value as? Data,
                  let array = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [Any],
                  let first = array.first else { continue }
            out[key] = first
        }
        return out
    }

    func setStoredValue(_ value: Any, key: String, ns: String) {
        var dict = UserDefaults.standard.dictionary(forKey: storeKey(ns)) ?? [:]
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: []) {
            dict[key] = data
            UserDefaults.standard.set(dict, forKey: storeKey(ns))
        }
    }

    func deleteStoredValue(key: String, ns: String) {
        var dict = UserDefaults.standard.dictionary(forKey: storeKey(ns)) ?? [:]
        dict.removeValue(forKey: key)
        UserDefaults.standard.set(dict, forKey: storeKey(ns))
    }

    // MARK: - Injection source

    func jsonString(_ object: Any) -> String {
        var target: Any = object
        var isFragment = false
        if !(object is [Any]) && !(object is [String: Any]) {
            target = [object] as [Any]
            isFragment = true
        }
        guard let data = try? JSONSerialization.data(withJSONObject: target, options: []),
              var text = String(data: data, encoding: .utf8) else { return "null" }
        if isFragment && text.count >= 2 { text = String(text.dropFirst().dropLast()) }
        return text
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            .replacingOccurrences(of: "</", with: "<\\/")
    }

    /// Wraps a userscript in its own scope with GM_* bound as parameters,
    /// exactly like Tampermonkey's per-script sandbox.
    func source(for rec: ScriptRecord) -> String {
        let ns = rec.namespace + "|" + rec.name
        let preload: [String: Any] = [
            "ns": ns,
            "scriptId": rec.id,
            "name": rec.name,
            "values": storedValues(for: ns),
            "resources": rec.resources,
            "info": [
                "script": [
                    "name": rec.name, "namespace": rec.namespace, "version": rec.version,
                    "description": rec.desc, "matches": rec.match, "excludes": rec.exclude,
                    "grant": rec.grants, "runAt": rec.runAt
                ],
                "scriptHandler": "iPhone6 Browser Native",
                "version": "1.0.0",
                "scriptSource": rec.code,
                "isIncognito": false
            ] as [String: Any]
        ]

        var names: [String] = []
        if rec.grants.contains("none") {
            names = []
        } else if rec.grants.isEmpty {
            names = UserScriptManager.apiNames
        } else {
            names = rec.grants.filter { UserScriptManager.apiNames.contains($0) }
        }
        for extra in ["GM_info", "GM", "unsafeWindow"] {
            if !names.contains(extra) { names.append(extra) }
        }

        let params = names.joined(separator: ",")
        let args = names.map { "__api[" + jsonString($0) + "]" }.joined(separator: ",")
        let body = rec.requires.joined(separator: "\n;\n") + "\n;\n" + rec.code +
            "\n//# sourceURL=userscript-" + rec.id + ".js"

        return "(function(){\n" +
            "var __P = " + jsonString(preload) + ";\n" +
            "var __api = window.__tm_makeApi(__P);\n" +
            "(function(" + params + "){\n\"use strict\";\n" + body + "\n})(" + args + ");\n" +
            "})();"
    }
}
