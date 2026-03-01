import Foundation

public struct FavoritePort: Codable, Hashable {
    public let port: Int
    public let protocolName: String
    public var label: String
    public var category: PortCategory
    public let addedAt: Date

    public init(port: Int, protocolName: String = "tcp", label: String = "", category: PortCategory = .dev) {
        self.port = port
        self.protocolName = protocolName
        self.label = label.isEmpty ? "Port \(port)" : label
        self.category = category
        self.addedAt = Date()
    }
}

public enum FavoritesError: LocalizedError {
    case alreadyExists
    case notFound

    public var errorDescription: String? {
        switch self {
        case .alreadyExists:
            return "This port is already in your favorites"
        case .notFound:
            return "Favorite port not found"
        }
    }
}

public final class FavoritesManager {
    private let userDefaults: UserDefaults
    private let favoritesKey = "portKiller.favorites"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - CRUD Operations

    public func getAllFavorites() -> [FavoritePort] {
        guard let data = userDefaults.data(forKey: favoritesKey),
              let favorites = try? JSONDecoder().decode([FavoritePort].self, from: data) else {
            return []
        }
        return favorites.sorted { $0.port < $1.port }
    }

    public func addFavorite(port: Int, protocolName: String = "tcp", label: String = "", category: PortCategory = .dev) throws {
        var favorites = getAllFavorites()

        guard !favorites.contains(where: { $0.port == port && $0.protocolName == protocolName }) else {
            throw FavoritesError.alreadyExists
        }

        let favorite = FavoritePort(port: port, protocolName: protocolName, label: label, category: category)
        favorites.append(favorite)
        try saveFavorites(favorites)
    }

    public func removeFavorite(port: Int, protocolName: String = "tcp") throws {
        var favorites = getAllFavorites()
        let initialCount = favorites.count
        favorites.removeAll { $0.port == port && $0.protocolName == protocolName }

        guard favorites.count < initialCount else {
            throw FavoritesError.notFound
        }

        try saveFavorites(favorites)
    }

    public func updateFavoriteLabel(port: Int, protocolName: String, newLabel: String) throws {
        var favorites = getAllFavorites()
        guard let index = favorites.firstIndex(where: { $0.port == port && $0.protocolName == protocolName }) else {
            throw FavoritesError.notFound
        }

        let oldFavorite = favorites[index]
        favorites[index] = FavoritePort(
            port: oldFavorite.port,
            protocolName: oldFavorite.protocolName,
            label: newLabel,
            category: oldFavorite.category
        )

        try saveFavorites(favorites)
    }

    public func updateFavoriteCategory(port: Int, protocolName: String, newCategory: PortCategory) throws {
        var favorites = getAllFavorites()
        guard let index = favorites.firstIndex(where: { $0.port == port && $0.protocolName == protocolName }) else {
            throw FavoritesError.notFound
        }

        let oldFavorite = favorites[index]
        favorites[index] = FavoritePort(
            port: oldFavorite.port,
            protocolName: oldFavorite.protocolName,
            label: oldFavorite.label,
            category: newCategory
        )

        try saveFavorites(favorites)
    }

    public func isFavorite(port: Int, protocolName: String = "tcp") -> Bool {
        return getAllFavorites().contains { $0.port == port && $0.protocolName == protocolName }
    }

    public func getFavoritesByCategory(_ category: PortCategory) -> [FavoritePort] {
        return getAllFavorites().filter { $0.category == category }
    }

    public func getFavoritesByPort(_ port: Int) -> [FavoritePort] {
        return getAllFavorites().filter { $0.port == port }
    }

    // MARK: - Quick Actions

    public func getQuickActionPorts() -> [FavoritePort] {
        return getAllFavorites().filter { favorite in
            PortCategory.dev.defaultPorts.contains(favorite.port) ||
            PortCategory.web.defaultPorts.contains(favorite.port)
        }
    }

    public func addCommonPorts() throws {
        let commonPorts: [(Int, String, PortCategory)] = [
            (3000, "React Dev Server", .web),
            (5173, "Vite Dev Server", .web),
            (8000, "Django/Python", .dev),
            (8080, "HTTP Alt", .web),
            (5432, "PostgreSQL", .database),
            (3306, "MySQL", .database),
            (27017, "MongoDB", .database),
            (6379, "Redis", .database)
        ]

        for (port, label, category) in commonPorts {
            try? addFavorite(port: port, protocolName: "tcp", label: label, category: category)
        }
    }

    // MARK: - Private

    private func saveFavorites(_ favorites: [FavoritePort]) throws {
        let data = try JSONEncoder().encode(favorites)
        userDefaults.set(data, forKey: favoritesKey)
    }
}
