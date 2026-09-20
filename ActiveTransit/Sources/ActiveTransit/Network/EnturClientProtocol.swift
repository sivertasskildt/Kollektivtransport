import Foundation
import CoreLocation

/// Protocol defining the interface for the Entur network client.
public protocol EnturClientProtocol {
    /// Fetches the subsequent transit stops and their expected arrival times for a given service journey.
    /// - Parameter serviceJourneyId: The ID of the service journey (e.g. from Entur).
    /// - Returns: An array of `TransitStop` representing the upcoming stops.
    func fetchSubsequentStops(for serviceJourneyId: String) async throws -> [TransitStop]
    
    /// Finds the nearest transit stop to a location and returns the ID of the next departing service journey.
    /// - Parameter currentLocation: The user's current location.
    /// - Returns: A service journey ID if found, otherwise nil.
    func fetchNearestActiveServiceJourney(currentLocation: CLLocation) async throws -> String?
    
    /// Fetches transit trips between two coordinates.
    /// - Parameters:
    ///   - from: Starting coordinate.
    ///   - to: Destination coordinate.
    /// - Returns: An array of `TransitTrip` representing the available trips.
    func fetchTrips(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> [TransitTrip]
}
