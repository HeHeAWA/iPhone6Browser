import UIKit

private let CHANGE_NOTIFICATION = NSNotification.Name("userscriptsDidChange")

// MARK: - Script library / menu commands / console

final class ScriptLibraryViewController: UITableViewController {

    weak var browser: BrowserViewController?

    private let sections = ["当前页面", "菜单命令", "已安装脚本", "控制台"]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "脚本管理"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                             target: self, action: #selector(addTapped))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc private func closeTapped() { dismiss(animated: true, completion: nil) }

    @objc private func addTapped() {
        let editor = ScriptEditorViewController()
        editor.code = ScriptEditorViewController.template
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func toggleScript(_ sender: UISwitch) {
        let index = sender.tag
        let scripts = UserScriptManager.shared.scripts
        guard index >= 0, index < scripts.count else { return }
        UserScriptManager.shared.setEnabled(sender.isOn, id: scripts[index].id)
        NotificationCenter.default.post(name: CHANGE_NOTIFICATION, object: nil)
        tableView.reloadData()
    }

    @objc private func clearLogsTapped() {
        browser?.clearLogs()
        tableView.reloadData()
    }

    // MARK: Table data

    override func numberOfSections(in tableView: UITableView) -> Int { return sections.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return max(2, 1 + (browser?.matchedNames().count ?? 0))
        case 1: return max(1, browser?.menuItems().count ?? 0)
        case 2: return max(1, UserScriptManager.shared.scripts.count)
        case 3: return max(1, min(browser?.logLines().count ?? 0, 80))
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.font = UIFont.systemFont(ofSize: 13)
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 10)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch indexPath.section {
        case 0:
            if indexPath.row == 0 {
                cell.textLabel?.text = browser?.currentURL?.absoluteString ?? "about:blank"
                cell.textLabel?.numberOfLines = 2
                cell.detailTextLabel?.text = "WKWebView 直连真实网站 · 脚本按 @match 注入"
                cell.selectionStyle = .none
            } else {
                let names = browser?.matchedNames() ?? []
                if indexPath.row - 1 < names.count {
                    cell.textLabel?.text = "✓ " + names[indexPath.row - 1]
                    cell.detailTextLabel?.text = "已注入"
                    cell.selectionStyle = .none
                } else {
                    cell.textLabel?.text = "当前页面无匹配脚本"
                    cell.selectionStyle = .none
                }
            }
        case 1:
            let items = browser?.menuItems() ?? []
            if items.isEmpty {
                cell.textLabel?.text = "当前页面没有注册菜单命令"
                cell.selectionStyle = .none
            } else {
                let item = items[indexPath.row]
                cell.textLabel?.text = item.name
                cell.detailTextLabel?.text = item.script
                cell.accessoryType = .disclosureIndicator
            }
        case 2:
            let scripts = UserScriptManager.shared.scripts
            if scripts.isEmpty {
                cell.textLabel?.text = "还没有脚本，点右上角 + 新建"
                cell.selectionStyle = .none
            } else {
                let script = scripts[indexPath.row]
                cell.textLabel?.text = script.name + (script.builtin ? "  [内置]" : "")
                cell.detailTextLabel?.text = (script.match + script.include).joined(separator: " ") +
                    " · " + script.runAt + " · " + script.grants.count.description + " grants"
                cell.detailTextLabel?.numberOfLines = 1
                let toggle = UISwitch()
                toggle.isOn = script.enabled
                toggle.tag = indexPath.row
                toggle.addTarget(self, action: #selector(toggleScript(_:)), for: .valueChanged)
                cell.accessoryView = toggle
                cell.accessoryType = .disclosureIndicator
            }
        case 3:
            let lines = browser?.logLines() ?? []
            if lines.isEmpty {
                cell.textLabel?.text = "控制台为空"
                cell.selectionStyle = .none
            } else {
                let start = max(0, lines.count - 80)
                cell.textLabel?.text = lines[start + indexPath.row]
                cell.textLabel?.font = UIFont(name: "Menlo", size: 9) ?? UIFont.systemFont(ofSize: 9)
                cell.textLabel?.numberOfLines = 2
                cell.selectionStyle = .none
            }
            if indexPath.row == 0 {
                let clear = UIButton(type: .system)
                clear.setTitle("清空", for: .normal)
                clear.frame = CGRect(x: 0, y: 0, width: 44, height: 26)
                clear.addTarget(self, action: #selector(clearLogsTapped), for: .touchUpInside)
                cell.accessoryView = clear
            }
        default:
            break
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            let items = browser?.menuItems() ?? []
            if indexPath.row < items.count {
                browser?.runMenuCommand(items[indexPath.row].id)
                dismiss(animated: true, completion: nil)
            }
        } else if indexPath.section == 2 {
            let scripts = UserScriptManager.shared.scripts
            guard indexPath.row < scripts.count else { return }
            let editor = ScriptEditorViewController()
            editor.code = scripts[indexPath.row].code
            editor.replacingId = scripts[indexPath.row].id
            navigationController?.pushViewController(editor, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView,
                            accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard indexPath.section == 2 else { return }
        let scripts = UserScriptManager.shared.scripts
        guard indexPath.row < scripts.count else { return }
        let editor = ScriptEditorViewController()
        editor.code = scripts[indexPath.row].code
        editor.replacingId = scripts[indexPath.row].id
        navigationController?.pushViewController(editor, animated: true)
    }
}

// MARK: - Script editor

final class ScriptEditorViewController: UIViewController {

    var code: String = ""
    var replacingId: String?

    static let template: String = [
        "// ==UserScript==",
        "// @name         我的脚本",
        "// @namespace    mh.iphone6.native",
        "// @version      1.0.0",
        "// @description  在这里写说明",
        "// @match        *://*/*",
        "// @run-at       document-end",
        "// @grant        GM_addStyle",
        "// @grant        GM_setValue",
        "// @grant        GM_getValue",
        "// @grant        GM_registerMenuCommand",
        "// @grant        GM_notification",
        "// @grant        GM_xmlhttpRequest",
        "// @grant        GM_log",
        "// ==/UserScript==",
        "(function () {",
        "  'use strict';",
        "  console.log('native userscript 已运行：', location.href);",
        "  GM_addStyle('body { -webkit-text-size-adjust: 100%; }');",
        "  GM_registerMenuCommand('点我测试', function () {",
        "    GM_notification({ title: 'iPhone 6 Browser', text: '菜单命令已执行' });",
        "  });",
        "})();"
    ].joined(separator: "\n")

    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = replacingId == nil ? "新建脚本" : "编辑脚本"
        view.backgroundColor = .white
        textView.font = UIFont(name: "Menlo", size: 11) ?? UIFont.systemFont(ofSize: 11)
        textView.text = code
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8)
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "保存并重载", style: .done,
                                                            target: self, action: #selector(saveTapped))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "粘贴导入", style: .plain,
                                                           target: self, action: #selector(pasteTapped))
    }

    @objc private func pasteTapped() {
        if let text = UIPasteboard.general.string, !text.isEmpty { textView.text = text }
    }

    @objc private func saveTapped() {
        let text = textView.text ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UserScriptManager.shared.install(code: text, replacingId: replacingId) { [weak self] in
            NotificationCenter.default.post(name: CHANGE_NOTIFICATION, object: nil)
            self?.navigationController?.popViewController(animated: true)
        }
    }
}

// MARK: - Tabs

final class TabsViewController: UITableViewController {

    weak var browser: BrowserViewController?
    var urls: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "标签页"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "tab")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                             target: self, action: #selector(addTapped))
    }

    @objc private func closeTapped() { dismiss(animated: true, completion: nil) }

    @objc private func addTapped() {
        browser?.openURL("https://example.com/")
        dismiss(animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return urls.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "tab", for: indexPath)
        cell.textLabel?.text = urls[indexPath.row].absoluteString
        cell.textLabel?.font = UIFont.systemFont(ofSize: 12)
        cell.textLabel?.numberOfLines = 2
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        browser?.jumpTo(index: indexPath.row)
        dismiss(animated: true, completion: nil)
    }
}
