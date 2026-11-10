import SwiftUI
import AVFoundation

/// Cámara que sigue leyendo códigos sin cerrarse (el escáner del POS es de un
/// solo disparo). Mientras `active` sea false las lecturas se descartan, pero la
/// cámara sigue encendida para no tardar en reiniciarla entre consultas.
/// El permiso de cámara debe estar concedido antes de mostrarlo.
struct ContinuousScanner: UIViewRepresentable {
    var useFrontCamera: Bool = false
    var active: Bool = true
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(useFront: useFrontCamera) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = context.coordinator.session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.active = active
        context.coordinator.onCode = onCode
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "solupos.continuous-scanner")
        private let stabilizer = ScanStabilizer()
        private let useFront: Bool
        private var didStop = false
        var active = true
        var onCode: (String) -> Void = { _ in }

        init(useFront: Bool) { self.useFront = useFront }

        /// Configura y arranca la sesión fuera del main thread.
        func start() {
            queue.async { [self] in
                let wanted: AVCaptureDevice? = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: useFront ? .front : .back)
                // Respaldo a la trasera si no existe la pedida.
                guard let device = wanted ?? AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else { return }
                session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else { return }
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                // UPC-A llega como EAN-13 con 0 delante; el intérprete ya lo cubre.
                output.metadataObjectTypes = [.ean13, .ean8, .code128, .code39, .upce]
                session.startRunning()
            }
        }

        /// stopRunning() es bloqueante: nunca en el main thread, y sin doble stop.
        func stop() {
            guard !didStop else { return }
            didStop = true
            queue.async { [session] in session.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard active else { return }
            let raw = objects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }.first
            if let confirmed = stabilizer.offer(raw), active { onCode(confirmed) }
        }
    }
}
