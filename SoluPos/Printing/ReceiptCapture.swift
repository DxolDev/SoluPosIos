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

    // Script que extrae las reglas CSS de @media print y las aplica en pantalla,
    // fuerza el ancho angosto y preserva imágenes. Puerto directo del JS de Android.
    private static func cssInjectionScript(paperWidthMm: Int) -> String {
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
                        if (rule instanceof CSSMediaRule && rule.conditionText === 'print') {
                            for (var k = 0; k < rule.cssRules.length; k++) {
                                rules += rule.cssRules[k].cssText + '\\n';
                            }
                        }
                    }
                } catch(e) {}
            }
            rules += 'body { width: \(cssPx)px !important; margin: 0 !important; } img { height: auto !important; }';
            style.textContent = rules;
            document.head.appendChild(style);
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
        guard contentSize.width > 0, contentSize.height > 0 else { return nil }

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: contentSize)

        return await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: config) { image, error in
                continuation.resume(returning: image)
            }
        }
    }

    private static func processForPrinter(image: UIImage, paperWidthMm: Int) -> UIImage? {
        let targetWidth = CGFloat(UserPreferences.printableDots(paperWidthMm: paperWidthMm))
        let scale = targetWidth / image.size.width
        let scaledHeight = min(CGFloat(maxHeightPx), image.size.height * scale)

        let scaledSize = CGSize(width: targetWidth, height: scaledHeight)
        UIGraphicsBeginImageContextWithOptions(scaledSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: scaledSize))
        guard let scaled = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()

        guard let trimmed = trimWhitespace(image: scaled) else { return nil }
        return binarize(image: trimmed)
    }

    private static func trimWhitespace(image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        func isDark(x: Int, y: Int) -> Bool {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let r = CGFloat(ptr[offset]) / 255
            let g = CGFloat(ptr[offset + 1]) / 255
            let b = CGFloat(ptr[offset + 2]) / 255
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            return luminance < darkThreshold
        }

        var top = 0, bottom = height - 1
        outer: for y in 0..<height {
            for x in 0..<width { if isDark(x: x, y: y) { top = y; break outer } }
        }
        outer: for y in stride(from: height - 1, through: 0, by: -1) {
            for x in 0..<width { if isDark(x: x, y: y) { bottom = y; break outer } }
        }
        guard bottom > top, (bottom - top) >= 1 else { return image }

        let cropRect = CGRect(x: 0, y: top, width: width, height: bottom - top + 1)
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
