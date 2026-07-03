import Foundation
import SwiftData

@Model
final class Store {
    var id: String
    var name: String
    var url: String
    var createdAt: Date

    init(name: String, url: String) {
        self.id = UUID().uuidString
        self.name = name
        self.url = url
        self.createdAt = Date()
    }
}
