import SwiftUI
import SwiftData
import AVFoundation
import UIKit

private let resultSeconds = 8.0
private let errorSeconds = 5.0
private let exitHoldSeconds = 3.0

private enum KioskState: Equatable {
    case idle
    case looking
    case showing(LookupResult)
}

/// Consultador a pantalla completa. Si la tienda está en modo quiosco el equipo
/// queda bloqueado aquí y solo se sale con el PIN; si no, es una vista normal
/// con botón "Salir" y gesto atrás.
///
/// IMPORTANTE (Acceso Guiado): iOS no permite fijar la app por código sin MDM.
/// Se intenta `UIAccessibility.requestGuidedAccessSession`, que solo funciona en
/// equipos supervisados; si falla se ignora. Para un quiosco real, el encargado
/// debe activar Acceso Guiado a mano (Ajustes > Accesibilidad > Acceso guiado y
/// triple clic en el botón lateral/Inicio con la app abierta).
struct PriceCheckView: View {
    let store: Store
    var lookup: PriceLookupService = PriceLookupProvider.create()
    var pinStore: KioskPinStore = .shared

    @Environment(\.dismiss) private var dismiss
    @State private var state: KioskState = .idle
    @State private var showPin = false
    @State private var progress: CGFloat = 1
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)

    private var locked: Bool { store.kioskMode }

    var body: some View {
        ZStack(alignment: .topLeading) {
            gradient.ignoresSafeArea()
            scannerColumn

            switch state {
            case .looking:
                Color(red: 4 / 255, green: 27 / 255, blue: 77 / 255).opacity(0.8)
                    .ignoresSafeArea()
                    .overlay(Text("Consultando…").font(.system(size: 24)).foregroundStyle(.white))
            case .showing(let result):
                resultOverlay(result)
            case .idle:
                EmptyView()
            }

            // Salida: mantener pulsada la esquina (con PIN) o botón normal si no es quiosco.
            if locked {
                Color.clear
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: exitHoldSeconds) { showPin = true }
            } else {
                Button("Salir") { dismiss() }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }

            if showPin {
                PinDialog(pinStore: pinStore,
                          onDismiss: { showPin = false },
                          onOk: { showPin = false; dismiss() })
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background { if locked { NoSwipeBack() } }
        .task(id: state) { await runAutoReturn() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if permission == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async { permission = granted ? .authorized : .denied }
                }
            }
            if locked { UIAccessibility.requestGuidedAccessSession(enabled: true) { _ in } }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if locked { UIAccessibility.requestGuidedAccessSession(enabled: false) { _ in } }
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [.heroTop, .heroBottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Pantalla de escaneo

    private var scannerColumn: some View {
        VStack(spacing: 0) {
            Text(store.name.uppercased())
                .font(.system(size: 13)).tracking(2)
                .foregroundStyle(.white.opacity(0.7))
            Text("Escanee su producto")
                .font(.system(size: 34, weight: .bold))
                .lineSpacing(8)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.vertical, 16)
            if permission == .authorized {
                ContinuousScanner(useFrontCamera: store.kioskFrontCamera,
                                  active: state == .idle,
                                  onCode: onCode)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.8), lineWidth: 2))
                Text("Acerque el código de barras a la cámara")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 16)
            } else {
                Text("Se necesita permiso de cámara para escanear.")
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                Button("Permitir cámara") {
                    if permission == .denied || permission == .restricted {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } else {
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            DispatchQueue.main.async { permission = granted ? .authorized : .denied }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Resultado

    @ViewBuilder
    private func resultOverlay(_ result: LookupResult) -> some View {
        let today = LocalDate.today()
        ZStack(alignment: .bottom) {
            gradient.ignoresSafeArea()
            VStack(spacing: 0) {
                if case .found(let info) = result {
                    let promo = info.activePromo(today: today)
                    Text(info.displayName)
                        .font(.system(size: 26, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text(formatQuetzales(info.finalPrice(today: today)))
                        .font(.system(size: 88, weight: .bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.vertical, 16)
                    if promo != nil {
                        Text("Antes \(formatQuetzales(info.regularPrice))"
                             + (info.promoEnd.map { " · Oferta hasta \($0.day)/\($0.month)" } ?? ""))
                            .font(.system(size: 20)).foregroundStyle(Color.blue100)
                    }
                    switch info.available {
                    case .some(true):
                        Text("Disponible").font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(red: 0x7D / 255, green: 0xE0 / 255, blue: 0xA8 / 255))
                            .padding(.top, 16)
                    case .some(false):
                        Text("Agotado").font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(red: 1, green: 0xB4 / 255, blue: 0xAB / 255))
                            .padding(.top, 16)
                    case .none:
                        EmptyView()
                    }
                } else {
                    let msg = result.message(kiosk: true)
                    Text(msg?.title ?? "")
                        .font(.system(size: 34, weight: .bold)).lineSpacing(8)
                        .multilineTextAlignment(.center).foregroundStyle(.white)
                    if let detail = msg?.detail {
                        Text(detail).font(.system(size: 20))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.8)).padding(.top, 12)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GeometryReader { geo in
                Color.blue100.frame(width: geo.size.width * progress, height: 6)
            }
            .frame(height: 6)
        }
        .contentShape(Rectangle())
        .onTapGesture { state = .idle }
    }

    // MARK: - Lógica

    private func onCode(_ raw: String) {
        guard state == .idle else { return }
        state = .looking
        let storeId = store.id
        Task {
            let query = CodeInterpreter.interpret(raw)
            let result: LookupResult = query == .unrecognized
                ? .unrecognized
                : await lookup.lookup(storeId: storeId, query: query)
            state = .showing(result)
        }
    }

    /// Vuelve solo a "Escanee su producto" tras unos segundos (la barra se vacía).
    private func runAutoReturn() async {
        guard case .showing(let result) = state else { return }
        var isFound = false
        if case .found = result { isFound = true }
        let seconds = isFound ? resultSeconds : errorSeconds
        progress = 1
        withAnimation(.linear(duration: seconds)) { progress = 0 }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        if !Task.isCancelled { state = .idle }
    }
}

// MARK: - Diálogo de PIN (inline, sin modal para no interferir con la cámara)

private struct PinDialog: View {
    let pinStore: KioskPinStore
    let onDismiss: () -> Void
    let onOk: () -> Void

    @State private var pin = ""
    @State private var message: String?

    init(pinStore: KioskPinStore, onDismiss: @escaping () -> Void, onOk: @escaping () -> Void) {
        self.pinStore = pinStore
        self.onDismiss = onDismiss
        self.onOk = onOk
        let locked = pinStore.lockedSeconds()
        _message = State(initialValue: locked > 0 ? "Demasiados intentos. Espere \(locked) s." : nil)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 12) {
                Text("PIN del encargado").font(.system(size: 20, weight: .semibold))
                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray3)))
                    .onChange(of: pin) { _, v in
                        let f = String(v.filter { $0.isASCII && $0.isNumber }.prefix(PinCrypto.maxLength))
                        if f != v { pin = f }
                        message = nil
                    }
                if let message {
                    Text(message).foregroundStyle(Color(red: 0xB3 / 255, green: 0x26 / 255, blue: 0x1E / 255))
                }
                HStack {
                    Button("Cancelar", action: onDismiss)
                    Spacer()
                    Button("Salir del quiosco") {
                        switch pinStore.verify(pin) {
                        case .ok: onOk()
                        case .wrong(let n):
                            pin = ""; message = "PIN incorrecto. Intentos restantes: \(n)"
                        case .locked(let s):
                            pin = ""; message = "Demasiados intentos. Espere \(s) s."
                        }
                    }
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(32)
        }
    }
}

/// Desactiva el gesto de deslizar para volver mientras el equipo es quiosco.
private struct NoSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ vc: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
