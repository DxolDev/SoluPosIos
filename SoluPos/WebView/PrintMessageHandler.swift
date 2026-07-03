import WebKit
import UIKit

final class PrintMessageHandler: NSObject, WKScriptMessageHandler {
    var onPrint: (() -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard message.name == "print" else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onPrint?()
        }
    }
}
