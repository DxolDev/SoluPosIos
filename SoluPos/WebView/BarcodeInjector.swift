import Foundation

enum BarcodeInjector {
    // Puerto fiel de BarcodeInjector.kt (Android): simula un escáner físico
    // tecleando el código carácter por carácter (keydown/keypress/input/keyup) y
    // termina con Enter. Muchos POS detectan "es un escaneo" por el patrón de
    // eventos de teclado, no solo por el valor final del input.
    //
    // Igual que Android, el destino se resuelve en el momento de inyectar:
    // document.activeElement y, si no es un campo, el PRIMER input de texto/búsqueda
    // del documento. Android desenfoca el WebView (clearFocus) antes de escanear, así
    // que activeElement queda en body y siempre cae al primer input. En iOS logramos
    // el mismo efecto con un blur() al inicio, para que el destino sea determinista.
    static func buildScript(barcode: String) -> String {
        let safe = barcode
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function(value) {
            // Equivalente iOS del clearFocus() nativo de Android: garantiza que el
            // destino sea el primer input y no un campo que WKWebView dejara enfocado.
            if (document.activeElement && document.activeElement.blur) {
                document.activeElement.blur();
            }

            var selector =
                'input[type="text"]:not([disabled]):not([readonly]),' +
                'input[type="search"]:not([disabled]):not([readonly]),' +
                'input:not([type]):not([disabled]):not([readonly])';

            var el = document.activeElement;
            if (!el || (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA')) {
                el = document.querySelector(selector);
            }
            if (!el) { return; }
            el.focus();

            var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;

            function fireKey(type, key, keyCode) {
                var ev = new KeyboardEvent(type, {
                    key: key, code: key.length === 1 ? 'Key' + key.toUpperCase() : key,
                    bubbles: true, cancelable: true
                });
                try {
                    Object.defineProperty(ev, 'keyCode', { get: function() { return keyCode; } });
                    Object.defineProperty(ev, 'which', { get: function() { return keyCode; } });
                } catch (e) {}
                el.dispatchEvent(ev);
            }

            var current = '';
            for (var i = 0; i < value.length; i++) {
                var ch = value[i];
                current += ch;
                fireKey('keydown', ch, ch.charCodeAt(0));
                fireKey('keypress', ch, ch.charCodeAt(0));
                nativeSetter.call(el, current);
                el.dispatchEvent(new Event('input', { bubbles: true }));
                fireKey('keyup', ch, ch.charCodeAt(0));
            }

            fireKey('keydown', 'Enter', 13);
            fireKey('keypress', 'Enter', 13);
            el.dispatchEvent(new Event('change', { bubbles: true }));
            fireKey('keyup', 'Enter', 13);

            if (window.$ || window.jQuery) {
                (window.$ || window.jQuery)(el).trigger('change').trigger('input');
            }
        })('\(safe)');
        """
    }

    // Arregla el bug del POS: el botón llama print_receipt() que no existe.
    // Redirige esa función (y window.print, por si el POS la llama directo) al
    // handler nativo de iOS. Equivalente iOS del bridge de impresión que Android
    // instala en onPageFinished.
    static let printReceiptFixScript = """
    (function() {
        function nativePrint() {
            window.webkit.messageHandlers.print.postMessage({});
        }
        window.print_receipt = nativePrint;
        window.print = nativePrint;
    })();
    """
}
