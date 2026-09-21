import Foundation
import CoreLocation

/// Signature for a closure that can provide a precise walking time between a location and a transit stop.
public typealias PreciseWalkTimeProvider = (CLLocation, TransitStop) async throws -> TimeInterval

/// Protocol defining the interface for the active routing algorithm.
public protocol ActiveRoutingProtocol {
    /// Finds the optimal transit stop to walk to based on the current position, walking speed, and a list of upcoming stops.
    ///
    /// - Parameters:
    ///   - currentPosition: The user's current location.
    ///   - stops: A list of subsequent transit stops for the service journey, ordered by arrival time.
    ///   - walkingSpeed: The user's walking speed in meters per second. Default is 1.4 m/s.
    ///   - safetyMargin: The safety margin in seconds to ensure the user arrives before the bus. Default is 120 seconds.
    ///   - preciseWalkTimeProvider: An optional closure to calculate a more precise walking time (e.g., using Apple Maps Directions API). If provided, it is invoked for the best candidate.
    /// - Returns: The optimal `TransitStop` to walk to.
    /// - Throws: `ActiveTransitError` if no better stop could be found.
    func calculateOptimalStop(
        currentPosition: CLLocation,
        startTime: Date,
        stops: [TransitStop],
        walkingSpeed: Double,
        safetyMargin: TimeInterval,
        preciseWalkTimeProvider: PreciseWalkTimeProvider?
    ) async throws -> TransitStop
}
