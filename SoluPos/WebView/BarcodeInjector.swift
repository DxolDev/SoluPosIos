import Foundation

enum BarcodeInjector {
    // Puerto directo de BarcodeInjector.kt: simula teclado físico
    // (keydown/keypress/input/keyup + Enter) para que los POS que detectan
    // el patrón de eventos reciban el código correctamente.
    static func buildScript(barcode: String) -> String {
        let safe = barcode
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function(value) {
            var el = document.activeElement;
            if (!el || (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA')) {
                el = document.querySelector(
                    'input[type="text"]:not([disabled]):not([readonly]),' +
                    'input[type="search"]:not([disabled]):not([readonly]),' +
                    'input:not([type]):not([disabled]):not([readonly])'
                );
            }
            if (!el) return;
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
                } catch(e) {}
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
    // Redirige esa función al handler nativo de iOS.
    static let printReceiptFixScript = """
    window.print_receipt = function() {
        window.webkit.messageHandlers.print.postMessage({});
    };
    """
}
