import Foundation
import CoreLocation

/// Service responsible for calculating the optimal transit stop for "Active Waiting".
///
/// Mål: Finn stoppet **lengst ut på ruten** (i kjøreretningen, mot avstigning) som brukeren
/// rekker å gå til før transportmiddelet kommer. Ankomsttiden er den samme uansett hvilket
/// stopp man går på, så lengst ut på ruten = mest mulig gange uten å komme senere frem.
///
/// Flyt:
/// 1. Grovfiltrering med luftlinje (nedre grense for gangavstand → ingen falske negative).
/// 2. Rangering: lengst ut på ruten først.
/// 3. Verifisering med presis gangtid (f.eks. MapKit) i parallelle runder, med et fast budsjett.
/// 4. Fallback: forsiktig heuristikk for stopp som ikke kunne verifiseres. Et stopp som er
///    eksplisitt avvist av presis gangtid returneres aldri.
public final class ActiveRouter: ActiveRoutingProtocol {
    
    /// Luftlinje er en nedre grense for faktisk gangavstand. Faktor 1.0 i grovfiltreringen
    /// betyr at vi aldri forkaster et stopp brukeren faktisk rekker.
    private let pruningDetourFactor: Double = 1.0
    
    /// Forsiktig omveisfaktor for stopp som ikke kan verifiseres presist (ingen provider,
    /// nettverksfeil eller budsjettet er brukt opp). Typisk urban omvei er ~1.2–1.4.
    private let conservativeDetourFactor: Double = 1.4
    
    /// Antall presise oppslag som kjøres parallelt per runde.
    private let preciseBatchSize = 3
    
    /// Maks antall presise oppslag per kall (beskytter mot rate limiting i MapKit).
    private let maxPreciseLookups = 6
    
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
        
        func canReach(_ stop: TransitStop, walkTime: TimeInterval) -> Bool {
            now.addingTimeInterval(walkTime + safetyMargin) <= stop.expectedArrivalTime
        }
        
        func canReachHeuristically(_ stop: TransitStop, detourFactor: Double) -> Bool {
            let distance = currentPosition.distance(from: stop.location) * detourFactor
            return canReach(stop, walkTime: distance / walkingSpeed)
        }
        
        // 1 + 2. Grovfiltrer alle stopp (ingen tidlig avbrudd – ring-linjer kan komme tilbake
        // nær brukeren etter mange utilgjengelige stopp) og ranger lengst ut på ruten først.
        // `stops` er i kjørerekkefølge, så reversering gir riktig rangering.
        let rankedCandidates: [TransitStop] = stops
            .filter { $0.expectedArrivalTime > now && canReachHeuristically($0, detourFactor: pruningDetourFactor) }
            .reversed()
        
        guard !rankedCandidates.isEmpty else {
            throw ActiveTransitError.noBetterStopFound
        }
        
        // Uten presis provider: velg det høyest rangerte stoppet som består den forsiktige sjekken.
        guard let preciseProvider = preciseWalkTimeProvider else {
            if let stop = rankedCandidates.first(where: { canReachHeuristically($0, detourFactor: conservativeDetourFactor) }) {
                return stop
            }
            throw ActiveTransitError.noBetterStopFound
        }
        
        // 3. Verifiser de høyest rangerte kandidatene i parallelle runder.
        var nextIndex = 0
        var lookupsUsed = 0
        
        while nextIndex < rankedCandidates.count && lookupsUsed < maxPreciseLookups {
            let batchSize = min(preciseBatchSize, maxPreciseLookups - lookupsUsed, rankedCandidates.count - nextIndex)
            let batch = Array(rankedCandidates[nextIndex..<(nextIndex + batchSize)])
            
            let walkTimes = await Self.preciseWalkTimes(for: batch, from: currentPosition, using: preciseProvider)
            lookupsUsed += batch.count
            nextIndex += batch.count
            
            // Evaluer i rangert rekkefølge, slik at stoppet lengst ut på ruten vinner.
            for (stop, walkTime) in zip(batch, walkTimes) {
                if let walkTime {
                    if canReach(stop, walkTime: walkTime) {
                        return stop
                    }
                    // Eksplisitt avvist – aldri bruk dette stoppet.
                } else if canReachHeuristically(stop, detourFactor: conservativeDetourFactor) {
                    // Oppslaget feilet (nettverk / rate limit): falle tilbake på forsiktig estimat.
                    return stop
                }
            }
        }
        
        // 4. Budsjettet er brukt opp: velg blant de gjenværende (uverifiserte) kandidatene
        // det høyest rangerte stoppet som består den forsiktige sjekken.
        if let stop = rankedCandidates[nextIndex...].first(where: { canReachHeuristically($0, detourFactor: conservativeDetourFactor) }) {
            return stop
        }
        
        throw ActiveTransitError.noBetterStopFound
    }
    
    /// Henter presis gangtid for alle stopp i `batch` parallelt.
    /// Returnerer `nil` for stopp der oppslaget feilet, i samme rekkefølge som `batch`.
    private static func preciseWalkTimes(
        for batch: [TransitStop],
        from position: CLLocation,
        using provider: @escaping PreciseWalkTimeProvider
    ) async -> [TimeInterval?] {
        await withTaskGroup(of: (Int, TimeInterval?).self) { group in
            for (index, stop) in batch.enumerated() {
                group.addTask {
                    (index, try? await provider(position, stop))
                }
            }
            
            var results = [TimeInterval?](repeating: nil, count: batch.count)
            for await (index, walkTime) in group {
                results[index] = walkTime
            }
            return results
        }
    }
}
