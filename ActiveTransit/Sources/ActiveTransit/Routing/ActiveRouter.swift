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
        
        let now = startTime
        
        var heuristicCandidates: [TransitStop] = []
        var consecutiveMisses = 0
        let maxConsecutiveMisses = 3
        
        for stop in stops {
            if stop.expectedArrivalTime <= now {
                continue
            }
            
            let straightLineDistance = currentPosition.distance(from: stop.location)
            let estimatedWalkingDistance = straightLineDistance * walkDistanceWiggleFactor
            let estimatedWalkingTime = estimatedWalkingDistance / walkingSpeed
            let requiredArrivalTime = now.addingTimeInterval(estimatedWalkingTime + safetyMargin)
            
            if requiredArrivalTime < stop.expectedArrivalTime {
                heuristicCandidates.append(stop)
                consecutiveMisses = 0
            } else if !heuristicCandidates.isEmpty {
                consecutiveMisses += 1
                if consecutiveMisses >= maxConsecutiveMisses {
                    break
                }
            }
        }
        
        guard !heuristicCandidates.isEmpty else {
            throw ActiveTransitError.noBetterStopFound
        }
        
        if let preciseProvider = preciseWalkTimeProvider {
            var checkCount = 0
            for candidate in heuristicCandidates.reversed() {
                if checkCount >= 2 { break }
                checkCount += 1
                
                if let preciseWalkTime = try? await preciseProvider(currentPosition, candidate) {
                    let requiredArrivalTime = now.addingTimeInterval(preciseWalkTime + safetyMargin)
                    if requiredArrivalTime < candidate.expectedArrivalTime {
                        return candidate
                    }
                }
            }
            throw ActiveTransitError.noBetterStopFound
        }
        
        return heuristicCandidates.last!
    }
}
