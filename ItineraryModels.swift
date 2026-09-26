import SwiftUI
import MapKit
import ActiveTransit

// MARK: - Itinerary UI Model

/// Represents a single leg in the user-facing journey itinerary.
struct ItineraryLeg: Identifiable {
    let id = UUID()
    let legIndex: Int
    let mode: TransitMode
    let lineDescription: String
    
    // Venting før denne etappen (nil for aller første etappe)
    let waitTimeMinutes: Int?
    let transferStationName: String?
    
    // Gå-informasjon (Aktiv Overgang)
    let optimalBoardingStop: TransitStop?
    let skippedStopsCount: Int
    
    // Påstigning
    let boardingStopName: String
    let boardingTime: Date?
    
    // Avstigning
    let alightingStopName: String
    let alightingTime: Date?
}

// MARK: - Walking Route UI Model

/// Wraps an MKRoute with an Identifiable ID for use in SwiftUI collections.
struct WalkingRoute: Identifiable {
    let id = UUID()
    let polyline: MKPolyline
}
