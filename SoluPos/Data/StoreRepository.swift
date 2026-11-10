import Foundation
import SwiftData

@MainActor
final class StoreRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [Store] {
        let descriptor = FetchDescriptor<Store>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func insert(_ store: Store) throws {
        context.insert(store)
        try context.save()
    }

    func update(_ store: Store, name: String, url: String) throws {
        store.name = name
        store.url = url
        try context.save()
    }

    /// Tienda configurada como quiosco en este equipo (equivale a getKioskStore()).
    func kioskStore() throws -> Store? {
        var d = FetchDescriptor<Store>(predicate: #Predicate { $0.kioskMode == true })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    /// Un equipo solo puede ser quiosco de una tienda.
    func clearKioskExcept(id: String) throws {
        let all = try context.fetch(FetchDescriptor<Store>(predicate: #Predicate { $0.kioskMode == true }))
        for s in all where s.id != id { s.kioskMode = false }
        try context.save()
    }

    func delete(_ store: Store) throws {
        context.delete(store)
        try context.save()
    }

    func find(id: String) throws -> Store? {
        var descriptor = FetchDescriptor<Store>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
