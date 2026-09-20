import Foundation
import CoreLocation

/// Represents a transit stop on a service journey.
public struct TransitStop: Codable, Equatable {
    /// The unique identifier of the stop place (e.g., NSR:StopPlace:1234).
    public let id: String
    
    /// The human-readable name of the stop.
    public let name: String
    
    /// The latitude of the stop.
    public let latitude: Double
    
    /// The longitude of the stop.
    public let longitude: Double
    
    /// The expected arrival time at this stop.
    public let expectedArrivalTime: Date
    
    /// Initializes a new TransitStop.
    public init(id: String, name: String, latitude: Double, longitude: Double, expectedArrivalTime: Date) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.expectedArrivalTime = expectedArrivalTime
    }
    
    /// The location of the stop as a `CLLocation` object.
    public var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
