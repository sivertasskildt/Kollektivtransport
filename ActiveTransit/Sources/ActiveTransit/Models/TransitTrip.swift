import Foundation
import CoreLocation

/// Represents a public transit trip option from A to B.
public struct TransitTrip: Identifiable, Equatable {
    public let id: String
    /// The expected departure time for this trip.
    public let expectedStartTime: Date
    /// The expected arrival time for this trip.
    public let expectedEndTime: Date
    /// The main public transit service journey ID for this trip.
    public let mainServiceJourneyId: String
    /// Text description of the trip (e.g. "Trikk 11 til Kjelsås").
    public let description: String
    
    public init(id: String = UUID().uuidString, expectedStartTime: Date, expectedEndTime: Date, mainServiceJourneyId: String, description: String) {
        self.id = id
        self.expectedStartTime = expectedStartTime
        self.expectedEndTime = expectedEndTime
        self.mainServiceJourneyId = mainServiceJourneyId
        self.description = description
    }
}
