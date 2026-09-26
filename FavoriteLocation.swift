import Foundation
import CoreLocation

/// Represents a saved favorite location.
struct FavoriteLocation: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var type: FavoriteType
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, type: FavoriteType = .custom) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.type = type
    }
}

/// The category of a favorite location, with predefined types and a custom option.
enum FavoriteType: String, Codable, CaseIterable, Identifiable {
    case home
    case work
    case school
    case gym
    case custom
    
    var id: String { rawValue }
    
    /// The SF Symbol icon name for this type.
    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "building.2.fill"
        case .school: return "graduationcap.fill"
        case .gym: return "dumbbell.fill"
        case .custom: return "mappin.circle.fill"
        }
    }
    
    /// The emoji for display in chips.
    var emoji: String {
        switch self {
        case .home: return "🏠"
        case .work: return "🏢"
        case .school: return "🎓"
        case .gym: return "🏋️"
        case .custom: return "📍"
        }
    }
    
    /// The Norwegian display name for this type.
    var displayName: String {
        switch self {
        case .home: return "Hjem"
        case .work: return "Jobb"
        case .school: return "Skole"
        case .gym: return "Trening"
        case .custom: return "Egendefinert"
        }
    }
}
