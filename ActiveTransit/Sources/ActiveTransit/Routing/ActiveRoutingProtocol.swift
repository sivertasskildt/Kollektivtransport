import Foundation
import CoreLocation

/// Signature for a closure that can provide a precise walking time between a location and a transit stop.
///
/// - Important: The returned time should be based on the user's own walking speed
///   (e.g. `route.distance / walkingSpeed`), not a provider's default speed such as
///   `MKRoute.expectedTravelTime`.
/// - Note: The closure is `@Sendable` because the router verifies several candidates in parallel.
public typealias PreciseWalkTimeProvider = @Sendable (CLLocation, TransitStop) async throws -> TimeInterval

/// Protocol defining the interface for the active routing algorithm.
public protocol ActiveRoutingProtocol {
    /// Finds the optimal transit stop to walk to based on the current position, walking speed, and a list of upcoming stops.
    ///
    /// - Parameters:
    ///   - currentPosition: The user's current location.
    ///   - stops: A list of subsequent transit stops for the service journey, ordered by arrival time.
    ///   - walkingSpeed: The user's walking speed in meters per second. Default is 1.4 m/s.
    ///   - safetyMargin: The safety margin in seconds to ensure the user arrives before the bus. Default is 20 seconds.
    ///   - preciseWalkTimeProvider: An optional closure to calculate a more precise walking time (e.g., MapKit route distance divided by walking speed). If provided, the highest-ranked candidates are verified in parallel batches within a fixed lookup budget.
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
