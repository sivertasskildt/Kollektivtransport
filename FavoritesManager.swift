import SwiftUI

/// Manages favorite locations with JSON persistence via @AppStorage.
@MainActor
final class FavoritesManager: ObservableObject {
    @AppStorage("savedFavorites") private var favoritesData: Data = Data()
    
    @Published var favorites: [FavoriteLocation] = [] {
        didSet {
            saveToDisk()
        }
    }
    
    init() {
        loadFromDisk()
    }
    
    // MARK: - CRUD
    
    func add(_ favorite: FavoriteLocation) {
        // If it's a predefined type, replace existing of same type
        if favorite.type != .custom {
            favorites.removeAll { $0.type == favorite.type }
        }
        favorites.append(favorite)
    }
    
    func remove(_ favorite: FavoriteLocation) {
        favorites.removeAll { $0.id == favorite.id }
    }
    
    func update(_ favorite: FavoriteLocation) {
        if let index = favorites.firstIndex(where: { $0.id == favorite.id }) {
            favorites[index] = favorite
        }
    }
    
    /// Returns the favorite for a given type, if one exists.
    func favorite(ofType type: FavoriteType) -> FavoriteLocation? {
        favorites.first { $0.type == type }
    }
    
    // MARK: - Persistence
    
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(favorites) {
            favoritesData = data
        }
    }
    
    private func loadFromDisk() {
        if let decoded = try? JSONDecoder().decode([FavoriteLocation].self, from: favoritesData) {
            self.favorites = decoded
        }
    }
}
