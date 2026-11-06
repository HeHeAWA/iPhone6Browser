import UIKit
import WebKit

/// Avoids the classic WKUserContentController -> handler retain cycle.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

enum Toast {
    static func show(title: String, text: String, in host: UIView) {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0.12, alpha: 0.94)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.text = title + "\n" + text
        let width = max(120, host.bounds.width - 32)
        label.frame = CGRect(x: 16, y: 64, width: width, height: 58)
        label.autoresizingMask = [.flexibleWidth]
        label.alpha = 0
        host.addSubview(label)
        UIView.animate(withDuration: 0.22, animations: {
            label.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.4, options: [], animations: {
                label.alpha = 0
            }, completion: { _ in
                label.removeFromSuperview()
            })
        })
    }
}
