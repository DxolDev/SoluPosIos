import SwiftUI

private let greenOk = Color(red: 0x1B / 255, green: 0x7F / 255, blue: 0x4B / 255)
private let redOut = Color(red: 0xB3 / 255, green: 0x26 / 255, blue: 0x1E / 255)
private let amberPromo = Color(red: 0xA1 / 255, green: 0x5C / 255, blue: 0)

/// Resultado de la consulta mostrado sobre la venta; no toca el carrito.
struct PriceResultSheet: View {
    let result: LookupResult
    let scannedCode: String
    let today: LocalDate
    let onClose: () -> Void
    let onScanAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .found(let info) = result {
                found(info)
            } else {
                let msg = result.message(kiosk: false)
                Text(scannedCode).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Text(msg?.title ?? "").font(.system(size: 22, weight: .bold))
                if let detail = msg?.detail {
                    Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Text("Cerrar").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.brandBlue))
                }
                Button(action: onScanAnother) {
                    Text("Escanear otro").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.brandBlue).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            }
            .font(.system(size: 15, weight: .medium))
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func found(_ info: PriceInfo) -> some View {
        let promo = info.activePromo(today: today)
        Text(info.itemNumber ?? String(info.itemId))
            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
        Text(info.displayName).font(.system(size: 16, weight: .semibold))
        Text(formatQuetzales(info.finalPrice(today: today)))
            .font(.system(size: 44, weight: .bold)).foregroundStyle(Color.brandBlue)
        if promo != nil {
            HStack(spacing: 10) {
                Text(formatQuetzales(info.regularPrice)).strikethrough().foregroundStyle(.secondary)
                Text(info.promoEnd.map { String(format: "Oferta hasta %02d/%02d", $0.day, $0.month) } ?? "Oferta")
                    .fontWeight(.semibold).foregroundStyle(amberPromo)
            }
        }
        switch info.available {
        case .some(true): Text("Disponible").fontWeight(.semibold).foregroundStyle(greenOk)
        case .some(false): Text("Agotado").fontWeight(.semibold).foregroundStyle(redOut)
        case .none: EmptyView()
        }
    }
}
