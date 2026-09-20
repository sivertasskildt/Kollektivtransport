import Foundation
import CoreLocation

/// The main entry point for the ActiveTransit framework.
/// Provides a high-level API for finding the optimal boarding stop.
public final class ActiveTransitRouter {
    private let networkClient: EnturClientProtocol
    private let router: ActiveRoutingProtocol
    
    /// Initializes a new `ActiveTransitRouter` with the provided Entur client name.
    /// - Parameter enturClientName: The `ET-Client-Name` header required by Entur (e.g. "mycompany-myapp").
    public convenience init(enturClientName: String) {
        self.init(
            networkClient: EnturNetworkClient(clientName: enturClientName),
            router: ActiveRouter()
        )
    }
    
    /// Internal initializer for dependency injection (useful for testing).
    init(networkClient: EnturClientProtocol, router: ActiveRoutingProtocol) {
        self.networkClient = networkClient
        self.router = router
    }
    
    /// Finds the nearest transit stop to the provided location and returns the ID of its next departing service journey.
    /// This is useful to dynamically discover a valid `serviceJourneyId`.
    /// - Parameter currentLocation: The user's current location.
    /// - Returns: A service journey ID if found, otherwise nil.
    public func findNearestActiveServiceJourney(near currentLocation: CLLocation) async throws -> String? {
        return try await networkClient.fetchNearestActiveServiceJourney(currentLocation: currentLocation)
    }
    
    /// Finds the optimal transit stop to walk to based on the current position.
    ///
    /// - Parameters:
    ///   - serviceJourneyId: The ID of the service journey (from Entur).
    ///   - currentPosition: The user's current location.
    ///   - walkingSpeed: The user's walking speed in meters per second. Default is 1.4 m/s.
    ///   - safetyMargin: The safety margin in seconds to ensure the user arrives before the bus. Default is 120 seconds.
    ///   - preciseWalkTimeProvider: An optional closure to calculate a more precise walking time.
    /// - Returns: The optimal `TransitStop` to walk to.
    /// - Throws: `ActiveTransitError` if the network request fails, or no better stop could be found.
    public func findOptimalBoardingStop(
        for serviceJourneyId: String,
        currentPosition: CLLocation,
        walkingSpeed: Double = 1.4,
        safetyMargin: TimeInterval = 120,
        preciseWalkTimeProvider: PreciseWalkTimeProvider? = nil
    ) async throws -> TransitStop {
        // 1. Fetch subsequent stops for the service journey
        let stops = try await networkClient.fetchSubsequentStops(for: serviceJourneyId)
        
        // 2. Ensure we received stops
        guard !stops.isEmpty else {
            throw ActiveTransitError.invalidServiceJourney
        }
        
        // 3. Calculate and return the optimal stop
        return try await router.calculateOptimalStop(
            currentPosition: currentPosition,
            stops: stops,
            walkingSpeed: walkingSpeed,
            safetyMargin: safetyMargin,
            preciseWalkTimeProvider: preciseWalkTimeProvider
        )
    }
}
