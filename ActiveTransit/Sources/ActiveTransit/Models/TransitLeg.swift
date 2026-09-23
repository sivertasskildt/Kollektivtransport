import Foundation

/// Represents a single transit leg in a multi-leg journey.
public struct TransitLeg: Equatable, Hashable {
    /// The service journey ID for this specific leg.
    public let serviceJourneyId: String
    /// The start name for this specific leg.
    public let startName: String?
    /// The destination name for this specific leg.
    public let destinationName: String?
    /// Mode of transportation (e.g. .bus, .tram, .metro)
    public let mode: TransitMode
    /// Text description of the leg (e.g. "Trikk 11")
    public let description: String
    
    public init(serviceJourneyId: String, startName: String?, destinationName: String?, mode: TransitMode, description: String) {
        self.serviceJourneyId = serviceJourneyId
        self.startName = startName
        self.destinationName = destinationName
        self.mode = mode
        self.description = description
    }
}
