import Foundation

enum BarcodeInjector {
    // Antes de abrir el escáner cerramos el teclado (blur del input activo),
    // lo que borra document.activeElement. Este script recuerda cuál era el
    // campo activo en window.__posScanTarget para restaurarlo al inyectar.
    static let rememberScanTargetScript = """
    (function() {
        var el = document.activeElement;
        if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {
            window.__posScanTarget = el;
        }
    })();
    """

    // Puerto directo de BarcodeInjector.kt: simula teclado físico
    // (keydown/keypress/input/keyup + Enter) para que los POS que detectan
    // el patrón de eventos reciban el código correctamente.
    // Retorna un JSON con diagnóstico para ver en pantalla qué ocurrió.
    static func buildScript(barcode: String) -> String {
        let safe = barcode
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function(value) {
            var selector =
                'input[type="text"]:not([disabled]):not([readonly]),' +
                'input[type="search"]:not([disabled]):not([readonly]),' +
                'input[type="number"]:not([disabled]):not([readonly]),' +
                'input:not([type]):not([disabled]):not([readonly])';

            function isField(x) {
                return x && (x.tagName === 'INPUT' || x.tagName === 'TEXTAREA');
            }

            // Cuenta de inputs e iframes en el documento principal (diagnóstico).
            var inputCount = document.querySelectorAll(selector).length;
            var iframes = document.querySelectorAll('iframe');
            var iframeCount = iframes.length;

            // Prioridad 1: el campo recordado antes de abrir el escáner.
            var el = window.__posScanTarget;
            var source = 'remembered';
            if (!isField(el) || !el.isConnected) { el = null; }

            // Prioridad 2: el activeElement actual.
            if (!el && isField(document.activeElement)) {
                el = document.activeElement; source = 'active';
            }
            // Prioridad 3: primer input de texto del documento principal.
            if (!el) {
                el = document.querySelector(selector);
                if (el) source = 'query';
            }
            // Prioridad 4: buscar dentro de iframes same-origin.
            if (!el) {
                for (var i = 0; i < iframes.length; i++) {
                    try {
                        var doc = iframes[i].contentDocument;
                        if (doc) {
                            var cand = doc.querySelector(selector);
                            if (cand) { el = cand; source = 'iframe'; break; }
                        }
                    } catch (e) {}
                }
            }

            if (!el) {
                return JSON.stringify({found:false, inputCount:inputCount, iframes:iframeCount});
            }
            window.__posScanTarget = null;
            el.focus();

            var proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype
                                                  : window.HTMLInputElement.prototype;
            var nativeSetter = Object.getOwnPropertyDescriptor(proto, 'value').set;

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

            return JSON.stringify({
                found: true,
                source: source,
                tag: el.tagName,
                id: el.id || '',
                name: el.name || '',
                type: el.type || '',
                valueAfter: el.value,
                inputCount: inputCount,
                iframes: iframeCount
            });
        })('\(safe)');
        """
    }

    // Arregla el bug del POS: el botón llama print_receipt() que no existe.
    // Redirige esa función (y window.print, por si el POS la llama directo)
    // al handler nativo de iOS.
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
