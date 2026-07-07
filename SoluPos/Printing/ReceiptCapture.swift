import WebKit
import UIKit
import CoreGraphics

// Puerto de ReceiptCapture.kt — captura el contenido de impresión del WebView
// emulando @media print y procesando el bitmap a B/N para ESC/POS.
enum ReceiptCapture {
    private static let dpi = 203
    private static let reflowDelayMs: UInt64 = 350_000_000 // 350ms en nanosegundos
    private static let darkThreshold: CGFloat = 160.0 / 255.0
    private static let binaryThreshold: CGFloat = 180.0 / 255.0
    private static let maxHeightPx = 8000
    // Factor de sobre-muestreo al capturar el snapshot: WebKit re-rasteriza el texto
    // (vectorial) a esta densidad, así el contenido llega al escalado con muchos más
    // píxeles que los 384 dots del papel y el pipeline REDUCE (como Android) en vez de
    // ampliar → trazos finos en vez de gruesos/blocky. Bajar a 2 si un recibo muy
    // largo diera problemas de memoria.
    private static let snapshotScale: CGFloat = 3

    // Script que extrae las reglas CSS de @media print y las aplica en pantalla,
    // fuerza el ancho angosto y preserva imágenes. Puerto directo del JS de Android.
    private static func cssInjectionScript(paperWidthMm: Int) -> String {
        // Mismos anchos que Android (paperCssPx: 150 para ≤58mm, 240 para 80mm) para
        // paridad de tamaño. Más angosto = texto más grande al escalar a los dots del
        // papel. El wrap de líneas como "Serie y número: POS 54" es idéntico en Android
        // a este ancho, no es un defecto de iOS.
        let cssPx = paperWidthMm <= 58 ? 150 : 240
        return """
        (function() {
            var style = document.createElement('style');
            style.id = '__pos_print_style__';
            var rules = '';
            for (var i = 0; i < document.styleSheets.length; i++) {
                try {
                    var ss = document.styleSheets[i];
                    for (var j = 0; j < ss.cssRules.length; j++) {
                        var rule = ss.cssRules[j];
                        // Detección tolerante como Android (/print/i sobre mediaText): captura
                        // '@media only print', '@media print, screen', '@media print and (...)',
                        // etc. La comparación exacta === 'print' descartaba esas variantes y con
                        // ellas los anchos de columna / table-layout / font-size de impresión.
                        if (rule instanceof CSSMediaRule && rule.media && /print/i.test(rule.media.mediaText)) {
                            for (var k = 0; k < rule.cssRules.length; k++) {
                                var inner = rule.cssRules[k];
                                if (inner.type === 1 /* STYLE_RULE */) rules += inner.cssText + '\\n';
                            }
                        }
                    }
                } catch(e) {}
            }
            rules += 'html, body { width: \(cssPx)px !important; min-width: 0 !important; max-width: \(cssPx)px !important; margin: 0 auto !important; } * { max-width: 100% !important; box-sizing: border-box !important; } img { height: auto !important; }';
            style.textContent = rules;
            document.head.appendChild(style);
            window.scrollTo(0, 0);
        })();
        """
    }

    private static let removeInjectedCssScript = """
    (function(){var el=document.getElementById('__pos_print_style__');if(el)el.remove();})();
    """

    static func capture(webView: WKWebView, paperWidthMm: Int) async -> UIImage? {
        await MainActor.run {
            webView.evaluateJavaScript(cssInjectionScript(paperWidthMm: paperWidthMm), completionHandler: nil)
        }

        try? await Task.sleep(nanoseconds: reflowDelayMs)

        let snapshot = await takeFullSnapshot(webView: webView)

        await MainActor.run {
            webView.evaluateJavaScript(removeInjectedCssScript, completionHandler: nil)
        }

        guard let raw = snapshot else { return nil }
        return processForPrinter(image: raw, paperWidthMm: paperWidthMm)
    }

    @MainActor
    private static func takeFullSnapshot(webView: WKWebView) async -> UIImage? {
        let contentSize = webView.scrollView.contentSize
        // Ancho de captura = ancho del VIEWPORT (como Android usa webView.width), NO
        // contentSize.width. Si algún elemento se desborda horizontalmente, contentSize
        // es más ancho que la pantalla y el recibo saldría corrido a la izquierda con
        // margen a la derecha; capturando al ancho de la vista, ese desborde se recorta.
        // El alto sí es contentSize.height para abarcar todo el recibo (más alto que la
        // pantalla).
        let captureWidth = webView.bounds.width
        guard captureWidth > 0, contentSize.height > 0 else { return nil }

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: captureWidth, height: contentSize.height)
        // Capturar en alta resolución (ver snapshotScale): sin esto WebKit devuelve el
        // snapshot a baja densidad y el contenido se AMPLÍA a 384 dots → letra gruesa.
        config.snapshotWidth = NSNumber(value: Double(captureWidth * snapshotScale))

        return await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: config) { image, error in
                continuation.resume(returning: image)
            }
        }
    }

    private static func processForPrinter(image: UIImage, paperWidthMm: Int) -> UIImage? {
        guard let trimmed = trimWhitespace(image: image) else { return nil }
        guard let scaled = scaleToPaperWidth(image: trimmed, paperWidthMm: paperWidthMm) else { return nil }
        guard let bw = binarize(image: scaled) else { return nil }
        // Centrar el contenido dentro del ancho COMPLETO del papel rellenando con blanco
        // a los lados. La impresora imprime el ráster pegado a su origen izquierdo e
        // ignora el comando ESC/POS de centrado para imágenes; horneando el relleno en
        // la propia imagen (como hace DantSu en Android) el contenido queda centrado.
        return centerOnPaper(image: bw, paperWidthMm: paperWidthMm)
    }

    private static func centerOnPaper(image: UIImage, paperWidthMm: Int) -> UIImage? {
        guard let cg = image.cgImage else { return image }
        let contentW = cg.width
        let contentH = cg.height
        // Ancho total del papel en dots (58mm ≈ 464, 80mm ≈ 639 a 203dpi). El contenido
        // ocupa el ancho imprimible (printableDots); el resto es margen que repartimos
        // a ambos lados para centrar.
        let paperDots = Int((Double(paperWidthMm) * Double(dpi) / 25.4).rounded())
        guard paperDots > contentW else { return image }
        let x = (paperDots - contentW) / 2

        UIGraphicsBeginImageContextWithOptions(CGSize(width: paperDots, height: contentH), true, 1.0)
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: paperDots, height: contentH))
        // Dibujo 1:1 sin escalar (x entero) para no reintroducir gris en los trazos.
        image.draw(in: CGRect(x: x, y: 0, width: contentW, height: contentH))
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out
    }

    private static func scaleToPaperWidth(image: UIImage, paperWidthMm: Int) -> UIImage? {
        let targetWidth = CGFloat(UserPreferences.printableDots(paperWidthMm: paperWidthMm))
        guard image.size.width > 0, targetWidth > 0, targetWidth != image.size.width else { return image }
        let scale = targetWidth / image.size.width
        let scaledHeight = min(CGFloat(maxHeightPx), image.size.height * scale)

        let scaledSize = CGSize(width: targetWidth, height: scaledHeight)
        UIGraphicsBeginImageContextWithOptions(scaledSize, true, 1.0)
        // Interpolación de alta calidad al reducir (equivalente al filtro bilineal de
        // Android): bordes suaves que al binarizar dan trazos definidos, no gruesos.
        UIGraphicsGetCurrentContext()?.interpolationQuality = .high
        image.draw(in: CGRect(origin: .zero, size: scaledSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return scaled
    }

    // Recorta el blanco sobrante a la caja real del contenido oscuro (arriba/abajo
    // y también izquierda/derecha). Sin el recorte horizontal, el bitmap conserva
    // todo el ancho de la página capturada y, al escalar al ancho del papel, el
    // contenido sale pequeño y desplazado a la izquierda. Puerto directo de
    // ReceiptCapture.kt (trimWhitespace).
    private static func trimWhitespace(image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let minRun = 2

        func isDark(x: Int, y: Int) -> Bool {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let r = CGFloat(ptr[offset]) / 255
            let g = CGFloat(ptr[offset + 1]) / 255
            let b = CGFloat(ptr[offset + 2]) / 255
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            return luminance < darkThreshold
        }

        func rowHasContent(_ y: Int) -> Bool {
            var c = 0
            for x in 0..<width { if isDark(x: x, y: y) { c += 1; if c >= minRun { return true } } }
            return false
        }

        func colHasContent(_ x: Int, top: Int, bottom: Int) -> Bool {
            var c = 0
            for y in top...bottom { if isDark(x: x, y: y) { c += 1; if c >= minRun { return true } } }
            return false
        }

        var top = -1
        for y in 0..<height { if rowHasContent(y) { top = y; break } }
        guard top >= 0 else { return image }

        var bottom = height - 1
        for y in stride(from: height - 1, through: 0, by: -1) { if rowHasContent(y) { bottom = y; break } }

        var left = 0
        for x in 0..<width { if colHasContent(x, top: top, bottom: bottom) { left = x; break } }
        var right = width - 1
        for x in stride(from: width - 1, through: 0, by: -1) { if colHasContent(x, top: top, bottom: bottom) { right = x; break } }

        let marginV = 16
        let marginH = 8
        let x0 = max(left - marginH, 0)
        let x1 = min(right + marginH, width - 1)
        let y0 = max(top - marginV, 0)
        let y1 = min(bottom + marginV, height - 1)

        let cropRect = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped)
    }

    private static func binarize(image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        var pixelData = [UInt8](repeating: 255, count: width * height)

        guard let ctx = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for i in 0..<pixelData.count {
            pixelData[i] = CGFloat(pixelData[i]) / 255.0 < binaryThreshold ? 0 : 255
        }

        guard let bwCtx = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let bwCGImage = bwCtx.makeImage() else { return nil }

        return UIImage(cgImage: bwCGImage)
    }

    // Trocea la imagen en franjas de máximo stripHeightPx y genera un comando
    // GS v 0 independiente por franja (evita que la PT-210 encoja imágenes altas
    // enviadas en un solo bloque ráster; mismo workaround que Android).
    static func toEscPosRasterStrips(image: UIImage, stripHeightPx: Int) -> [Data]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        var strips: [Data] = []
        var y = 0
        while y < height {
            let h = min(stripHeightPx, height - y)
            guard let stripCG = cgImage.cropping(to: CGRect(x: 0, y: y, width: width, height: h)),
                  let stripData = toEscPosRaster(image: UIImage(cgImage: stripCG)) else {
                return nil
            }
            strips.append(stripData)
            y += h
        }
        return strips
    }

    // Convierte UIImage B/N a bytes ESC/POS GS v 0 (raster)
    static func toEscPosRaster(image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        // GS v 0: ancho en bytes (ceil(width/8)), alto en líneas
        let widthBytes = (width + 7) / 8
        var data = Data()

        // GS v 0 header
        data.append(contentsOf: [0x1D, 0x76, 0x30, 0x00])
        data.append(UInt8(widthBytes & 0xFF))
        data.append(UInt8((widthBytes >> 8) & 0xFF))
        data.append(UInt8(height & 0xFF))
        data.append(UInt8((height >> 8) & 0xFF))

        var pixels = [UInt8](repeating: 255, count: width * height)
        guard let ctx = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for y in 0..<height {
            for xByte in 0..<widthBytes {
                var byte: UInt8 = 0
                for bit in 0..<8 {
                    let x = xByte * 8 + bit
                    if x < width {
                        let pixel = pixels[y * width + x]
                        if pixel < 128 { byte |= (0x80 >> bit) }
                    }
                }
                data.append(byte)
            }
        }
        return data
    }
}
