import SwiftUI
import ActiveTransit

extension TransitMode {
    /// Returns the SF Symbol name for this transit mode.
    var iconName: String {
        switch self {
        case .bus: return "bus.fill"
        case .tram: return "tram.fill"
        case .metro: return "t.circle.fill"
        case .rail: return "train.side.front.car"
        case .water: return "ferry.fill"
        case .foot: return "figure.walk"
        default: return "bus.fill"
        }
    }
    
    /// Returns the accent color for this transit mode.
    var accentColor: Color {
        switch self {
        case .foot: return .green
        default: return .blue
        }
    }
}
