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
    /// Mode of transportation (e.g. "bus", "tram", "metro")
    public let mode: String
    /// The name of the final destination stop for this transit leg.
    public let destinationName: String?
    
    public init(id: String = UUID().uuidString, expectedStartTime: Date, expectedEndTime: Date, mainServiceJourneyId: String, description: String, mode: String, destinationName: String?) {
        self.id = id
        self.expectedStartTime = expectedStartTime
        self.expectedEndTime = expectedEndTime
        self.mainServiceJourneyId = mainServiceJourneyId
        self.description = description
        self.mode = mode
        self.destinationName = destinationName
    }
}
