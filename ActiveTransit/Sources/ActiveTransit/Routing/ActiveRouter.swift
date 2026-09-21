import Foundation
import CoreLocation

/// Service responsible for calculating the optimal transit stop for "Active Waiting".
public final class ActiveRouter: ActiveRoutingProtocol {
    
    /// A factor applied to straight-line distance to estimate actual walking distance (accounts for streets and corners).
    private let walkDistanceWiggleFactor: Double = 1.3
    
    public init() {}
    
    public func calculateOptimalStop(
        currentPosition: CLLocation,
        startTime: Date = Date(),
        stops: [TransitStop],
        walkingSpeed: Double = 1.4,
        safetyMargin: TimeInterval = 120,
        preciseWalkTimeProvider: PreciseWalkTimeProvider? = nil
    ) async throws -> TransitStop {
        
        var bestStop: TransitStop?
        let now = startTime
        
        for stop in stops {
            // Ignore stops that have already departed relative to our start time
            if stop.expectedArrivalTime <= now {
                continue
            }
            
            let straightLineDistance = currentPosition.distance(from: stop.location)
            let estimatedWalkingDistance = straightLineDistance * walkDistanceWiggleFactor
            let estimatedWalkingTime = estimatedWalkingDistance / walkingSpeed
            
            let requiredArrivalTime = now.addingTimeInterval(estimatedWalkingTime + safetyMargin)
            
            if requiredArrivalTime < stop.expectedArrivalTime {
                bestStop = stop
            } else if bestStop != nil {
                // Since stops are sequential, if we found at least one valid stop but can't make it to THIS stop in time,
                // we likely won't make it to the subsequent stops either. Break the loop.
                break
            }
        }
        
        guard let optimalStop = bestStop else {
            throw ActiveTransitError.noBetterStopFound
        }
        
        // If a precise walk time provider is supplied, verify the optimal stop
        if let preciseProvider = preciseWalkTimeProvider {
            let preciseWalkTime = try await preciseProvider(currentPosition, optimalStop)
            let requiredArrivalTime = now.addingTimeInterval(preciseWalkTime + safetyMargin)
            
            if requiredArrivalTime >= optimalStop.expectedArrivalTime {
                // The precise provider says we won't make it.
                // In a more complex implementation, we might step back to the previous stop,
                // but for simplicity, we throw an error if the best stop is invalid.
                throw ActiveTransitError.noBetterStopFound
            }
        }
        
        return optimalStop
    }
}
