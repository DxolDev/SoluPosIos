import SwiftUI
import AVFoundation

struct ScannerView: View {
    let onResult: (String) -> Void
    let onCancel: () -> Void

    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var scanLineOffset: CGFloat = 0
    @State private var hint = "Alinea el código de barras o QR\ndentro del marco para escanear"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch cameraPermission {
            case .authorized:
                cameraLayer
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
                permissionDeniedView
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
    }

    // MARK: - Camera layer

    private var cameraLayer: some View {
        ZStack {
            CameraPreviewLayer(onResult: { code in
                onResult(code)
            })
            .ignoresSafeArea()

            // Overlay oscuro con recorte transparente en el marco
            ScanFrameOverlay()

            VStack(spacing: 0) {
                // Instrucción arriba
                Text(hint)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 60)

                Spacer()

                // Marco de escaneo con línea animada
                scanFrame
                    .padding(.bottom, 40)

                Spacer()

                // Hint pill
                Label("Acerca el código para escanear", systemImage: "lightbulb")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 20)

                // Botón cancelar
                Button(action: onCancel) {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Cancelar")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white, lineWidth: 2)
                    )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Scan frame con esquinas y línea animada

    private var scanFrame: some View {
        let size: CGFloat = 260
        return ZStack {
            // Línea azul animada
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.brandBlue.opacity(0), Color.brandBlue, Color.brandBlue.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size - 20, height: 2)
                .offset(y: scanLineOffset)
                .animation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: scanLineOffset
                )

            // Esquinas del marco
            ScanCorners(size: size)
        }
        .frame(width: size, height: size)
        .onAppear {
            scanLineOffset = (size / 2) - 10
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scanLineOffset = -(size / 2) + 10
            }
        }
    }

    // MARK: - Permission denied

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.4))
            Text("Permiso de cámara requerido")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Ve a Ajustes para permitir el acceso a la cámara.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Cancelar") { onCancel() }
                .foregroundStyle(.white)
                .padding(.top, 8)
        }
    }
}

// MARK: - Esquinas del marco

private struct ScanCorners: View {
    let size: CGFloat
    private let thickness: CGFloat = 3
    private let length: CGFloat = 28
    private let radius: CGFloat = 6

    var body: some View {
        ZStack {
            corner(rotation: 0)
            corner(rotation: 90)
            corner(rotation: 180)
            corner(rotation: 270)
        }
        .frame(width: size, height: size)
    }

    private func corner(rotation: Double) -> some View {
        ZStack(alignment: .topLeading) {
            // Horizontal
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.white)
                .frame(width: length, height: thickness)
            // Vertical
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.white)
                .frame(width: thickness, height: length)
        }
        .rotationEffect(.degrees(rotation))
        .frame(width: size, height: size, alignment: cornerAlignment(rotation))
    }

    private func cornerAlignment(_ rotation: Double) -> Alignment {
        switch rotation {
        case 0:   return .topLeading
        case 90:  return .topTrailing
        case 180: return .bottomTrailing
        case 270: return .bottomLeading
        default:  return .topLeading
        }
    }
}

// MARK: - Overlay oscuro con hueco

private struct ScanFrameOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let frameSize: CGFloat = 260
            let cx = geo.size.width  / 2
            let cy = geo.size.height / 2
            let rect = CGRect(
                x: cx - frameSize / 2,
                y: cy - frameSize / 2,
                width: frameSize,
                height: frameSize
            )
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .mask(
                    Canvas { ctx, size in
                        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                        ctx.blendMode = .destinationOut
                        ctx.fill(
                            Path(roundedRect: rect, cornerRadius: 8),
                            with: .color(.black)
                        )
                    }
                )
        }
        .ignoresSafeArea()
    }
}

// MARK: - AVFoundation camera preview

private struct CameraPreviewLayer: UIViewRepresentable {
    let onResult: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let session = context.coordinator.session
        context.coordinator.setup(session: session)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        context.coordinator.previewLayer = preview
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopSession()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        var previewLayer: AVCaptureVideoPreviewLayer?
        private let onResult: (String) -> Void
        private var didScan = false
        private var didStop = false

        init(onResult: @escaping (String) -> Void) { self.onResult = onResult }

        // Detiene la sesión SIEMPRE fuera del main thread: stopRunning() es bloqueante y
        // llamarlo en main (como hacían metadataOutput y dismantleUIView) cuelga la UI y
        // dispara el watchdog ("se congela y se cierra"). El guard evita el doble stop
        // (uno al escanear, otro en el teardown de la vista).
        func stopSession() {
            guard !didStop else { return }
            didStop = true
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
        }

        func setup(session: AVCaptureSession) {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .code128, .code39, .qr, .upce, .itf14]
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didScan,
                  let obj = objects.first as? AVMetadataMachineReadableCodeObject,
                  let str = obj.stringValue else { return }
            didScan = true
            stopSession()
            onResult(str)
        }
    }
}
