import SwiftUI
import AVFoundation

struct ScannerView: View {
    let onResult: (String) -> Void
    let onCancel: () -> Void

    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            switch cameraPermission {
            case .authorized:
                CameraPreview(onResult: { code in
                    onResult(code)
                })
                .ignoresSafeArea()
            case .notDetermined:
                Color.black.ignoresSafeArea()
                    .onAppear {
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            DispatchQueue.main.async {
                                cameraPermission = granted ? .authorized : .denied
                            }
                        }
                    }
            default:
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Permiso de cámara requerido")
                        .font(.headline)
                    Text("Ve a Ajustes para permitir el acceso.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Cancelar") { onCancel() }
                        .buttonStyle(.bordered)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
                Text("Apunta la cámara al código de barras")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
            }
        }
        .statusBarHidden()
    }
}

private struct CameraPreview: UIViewRepresentable {
    let onResult: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let session = context.coordinator.session

        context.coordinator.setup(session: session, view: view)

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = UIScreen.main.bounds
        view.layer.addSublayer(preview)
        context.coordinator.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.session.stopRunning()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        var previewLayer: AVCaptureVideoPreviewLayer?
        private let onResult: (String) -> Void
        private var didScan = false

        init(onResult: @escaping (String) -> Void) {
            self.onResult = onResult
        }

        func setup(session: AVCaptureSession, view: UIView) {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)

            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [
                .ean13, .ean8, .code128, .code39,
                .qr, .upce, .itf14
            ]
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didScan,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let string = obj.stringValue else { return }
            didScan = true
            session.stopRunning()
            onResult(string)
        }
    }
}
