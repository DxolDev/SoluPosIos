import SwiftUI
import WebKit

struct POSWebView: UIViewRepresentable {
    let url: URL
    let printHandler: PrintMessageHandler
    var onBarcodeRequested: (() -> Void)?
    var webViewRef: ((WKWebView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(printHandler, name: "print")

        // Inyectar el fix de print_receipt() en cada página
        let printScript = WKUserScript(
            source: BarcodeInjector.printReceiptFixScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(printScript)

        // Permitir media inline y JavaScript
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Quitar el marcador "; wv)" que hace que algunos POS sirvan contenido degradado
        let ua = WKWebView().value(forKey: "userAgent") as? String ?? ""
        webView.customUserAgent = ua.replacingOccurrences(of: "; wv)", with: ")")

        // Publicar la referencia fuera del ciclo de update de SwiftUI: asignar el
        // @State webView de WebViewScreen aquí, síncrono dentro de makeUIView,
        // dispara "Modifying state during view update".
        DispatchQueue.main.async { [webViewRef] in
            webViewRef?(webView)
        }

        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: POSWebView
        weak var webView: WKWebView?
        private var sslAlertPresenter: UIViewController?

        init(_ parent: POSWebView) {
            self.parent = parent
        }

        // MARK: SSL — equivalente a PosWebViewClient.onReceivedSslError
        // No se continúa automáticamente; se pide confirmación explícita.
        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            let host = challenge.protectionSpace.host
            let alert = UIAlertController(
                title: "Certificado no verificado",
                message: "El sitio \(host) usa un certificado SSL que no se pudo verificar. ¿Continuar de todas formas?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in
                completionHandler(.cancelAuthenticationChallenge, nil)
            })
            alert.addAction(UIAlertAction(title: "Continuar", style: .destructive) { _ in
                let credential = URLCredential(trust: trust)
                completionHandler(.useCredential, credential)
            })
            findTopViewController()?.present(alert, animated: true)
        }

        // MARK: window.open() — redirige al mismo webview en vez de abrir ventana nueva
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func findTopViewController() -> UIViewController? {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return nil }
            var top: UIViewController = root
            while let presented = top.presentedViewController { top = presented }
            return top
        }
    }
}
