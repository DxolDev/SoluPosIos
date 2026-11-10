import Foundation

/// Interruptor único del Consultador de precios.
/// `true` solo en DEBUG; en Release queda oculto en TODOS los puntos de entrada
/// (botón de la tarjeta, sección del formulario, avisos del tutorial, botón
/// flotante y hoja del POS, arranque directo al quiosco).
/// Ponerlo en `true` (para todas las configuraciones) cuando exista el proxy.
enum Features {
    #if DEBUG
    static let priceCheckEnabled = true
    #else
    static let priceCheckEnabled = false
    #endif
}
