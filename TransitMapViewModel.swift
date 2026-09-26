import Foundation
import MapKit
import CoreLocation
import ActiveTransit
import SwiftUI

@MainActor
final class TransitMapViewModel: ObservableObject {
    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Published var allStops: [TransitStop] = []
    @Published var optimalStops: [String: TransitStop] = [:]
    @Published var closestStop: TransitStop?
    @Published var transferStops: [TransitStop] = []
    @Published var finalDestinationStop: TransitStop?
    @Published var itinerary: [ItineraryLeg] = []
    @Published var walkingRoutes: [WalkingRoute] = []
    @Published var transitPolylines: [[CLLocationCoordinate2D]] = []
    @Published var showItinerarySheet = true
    @Published var errorMessage: String?
    @Published var isLoading = false
    
    var hasFetchedRoute = false
    private let router = ActiveTransitRouter(enturClientName: "sivertasskildt-aktivovergang")
    
    /// Resets the fetch state so the route can be re-fetched.
    func retry() {
        hasFetchedRoute = false
        errorMessage = nil
    }
    
    func fetchActiveTransitRoute(currentLocation: CLLocation, trip: TransitTrip, destinationCoordinate: CLLocationCoordinate2D?, userSettings: UserSettings) async {
        guard !hasFetchedRoute else { return }
        hasFetchedRoute = true
        
        isLoading = true
        errorMessage = nil
        
        do {
            var combinedStops: [TransitStop] = []
            var newTransferStops: [TransitStop] = []
            var newFinalDestStop: TransitStop? = nil
            var newOptimalStops: [String: TransitStop] = [:]
            var newItinerary: [ItineraryLeg] = []
            var newWalkingRoutes: [WalkingRoute] = []
            var newTransitPolylines: [[CLLocationCoordinate2D]] = []
            
            var mkRouteCache: [String: MKRoute] = [:]
            
            func getWalkingRoute(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) async throws -> MKRoute {
                let key = "\(start.latitude),\(start.longitude)-\(end.latitude),\(end.longitude)"
                if let cached = mkRouteCache[key] { return cached }
                
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
                request.transportType = .walking
                
                try await Task.sleep(nanoseconds: 200_000_000) // Small delay to avoid rate limiting
                let response = try await MKDirections(request: request).calculate()
                
                if let route = response.routes.first {
                    mkRouteCache[key] = route
                    return route
                }
                throw NSError(domain: "MKDirectionsError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Fant ingen rute"])
            }
            
            let legs = trip.transitLegs.isEmpty ? [TransitLeg(serviceJourneyId: trip.mainServiceJourneyId, startName: nil, destinationName: trip.destinationName, mode: trip.mode, description: trip.description)] : trip.transitLegs
            
            var didTruncate = false
            var currentPhysicalCoordinate = currentLocation.coordinate
            var currentPhysicalTime = Date()
            
            for (index, leg) in legs.enumerated() {
                let fetchedStops = try await router.fetchSubsequentStops(for: leg.serviceJourneyId)
                
                var startIndex = 0
                if let startName = leg.startName, let idx = fetchedStops.firstIndex(where: { $0.name == startName }) {
                    startIndex = idx
                }
                
                var endIndex = fetchedStops.count - 1
                if let destName = leg.destinationName, let idx = fetchedStops.firstIndex(where: { $0.name == destName }) {
                    endIndex = idx
                }
                
                var optimalForThisLeg: TransitStop? = nil
                do {
                    if startIndex <= endIndex {
                        let relevantStops = Array(fetchedStops[startIndex...endIndex])
                        
                        let preciseProvider: PreciseWalkTimeProvider = { (startLoc: CLLocation, targetStop: TransitStop) async throws -> TimeInterval in
                            let route = try await getWalkingRoute(start: startLoc.coordinate, end: targetStop.location.coordinate)
                            return route.expectedTravelTime
                        }
                        
                        optimalForThisLeg = try await router.findOptimalBoardingStop(
                            stops: relevantStops,
                            currentPosition: CLLocation(latitude: currentPhysicalCoordinate.latitude, longitude: currentPhysicalCoordinate.longitude),
                            startTime: currentPhysicalTime,
                            walkingSpeed: userSettings.walkingSpeed,
                            safetyMargin: userSettings.safetyMargin,
                            preciseWalkTimeProvider: preciseProvider
                        )
                    }
                } catch {
                    // Fant ikke noe bedre stopp
                    if currentPhysicalTime == Date() { // If this is the first physical leg
                        optimalForThisLeg = fetchedStops[startIndex]
                    }
                }
                
                var skippedCount = 0
                if let optimal = optimalForThisLeg {
                    if let optIdx = fetchedStops.firstIndex(where: { $0.id == optimal.id }), optIdx >= startIndex, optIdx <= endIndex {
                        if optIdx > startIndex {
                            skippedCount = optIdx - startIndex
                            startIndex = optIdx
                        }
                    }
                    
                    if startIndex < endIndex {
                        newOptimalStops[leg.serviceJourneyId] = optimal
                    }
                }
                
                if startIndex < endIndex {
                    // We are actually boarding this leg!
                    let actualStartStop = fetchedStops[startIndex]
                    
                    // Draw walking route from current physical location to the start stop
                    let destCoord = CLLocationCoordinate2D(latitude: actualStartStop.latitude, longitude: actualStartStop.longitude)
                    do {
                        let route = try await getWalkingRoute(start: currentPhysicalCoordinate, end: destCoord)
                        newWalkingRoutes.append(WalkingRoute(polyline: route.polyline))
                    } catch {
                        print("Kunne ikke beregne gå-rute: \(error.localizedDescription)")
                    }
                    
                    let legStops = Array(fetchedStops[startIndex...endIndex])
                    combinedStops.append(contentsOf: legStops)
                    
                    let polyCoords = legStops.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    newTransitPolylines.append(polyCoords)
                    
                    if let alightingStop = legStops.last {
                        let waitTime = actualStartStop.expectedArrivalTime.timeIntervalSince(currentPhysicalTime)
                        let legWaitTimeMinutes = currentPhysicalTime == Date() ? nil : Int(max(0, waitTime / 60))
                        
                        let itinLeg = ItineraryLeg(
                            legIndex: index,
                            mode: leg.mode,
                            lineDescription: leg.description,
                            waitTimeMinutes: legWaitTimeMinutes,
                            transferStationName: nil, // Simplified for now
                            optimalBoardingStop: optimalForThisLeg,
                            skippedStopsCount: skippedCount,
                            boardingStopName: actualStartStop.name,
                            boardingTime: actualStartStop.expectedArrivalTime,
                            alightingStopName: alightingStop.name,
                            alightingTime: alightingStop.expectedArrivalTime
                        )
                        newItinerary.append(itinLeg)
                        
                        // Update physical location for the next leg
                        currentPhysicalCoordinate = CLLocationCoordinate2D(latitude: alightingStop.latitude, longitude: alightingStop.longitude)
                        currentPhysicalTime = alightingStop.expectedArrivalTime
                        
                        // Check if we should truncate (walk from here to final destination)
                        var shouldTruncate = false
                        if let dest = destinationCoordinate, index < legs.count - 1 {
                            let alightingLoc = CLLocation(latitude: alightingStop.latitude, longitude: alightingStop.longitude)
                            let finalLoc = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
                            let distance = alightingLoc.distance(from: finalLoc)
                            let walkingTime = distance / userSettings.walkingSpeed
                            let arrivalTimeIfWalking = alightingStop.expectedArrivalTime.addingTimeInterval(walkingTime)
                            
                            if arrivalTimeIfWalking <= trip.expectedEndTime {
                                shouldTruncate = true
                                newFinalDestStop = alightingStop
                                
                                let walkLeg = ItineraryLeg(
                                    legIndex: index + 1,
                                    mode: .foot,
                                    lineDescription: "Aktiv Overgang",
                                    waitTimeMinutes: nil,
                                    transferStationName: nil,
                                    optimalBoardingStop: nil,
                                    skippedStopsCount: 0,
                                    boardingStopName: alightingStop.name,
                                    boardingTime: alightingStop.expectedArrivalTime,
                                    alightingStopName: "Destinasjon",
                                    alightingTime: arrivalTimeIfWalking
                                )
                                newItinerary.append(walkLeg)
                                
                                do {
                                    let route = try await getWalkingRoute(start: alightingLoc.coordinate, end: dest)
                                    newWalkingRoutes.append(WalkingRoute(polyline: route.polyline))
                                } catch {
                                    print("Kunne ikke beregne gå-rute til destinasjon: \(error.localizedDescription)")
                                }
                            }
                        }
                        
                        if shouldTruncate {
                            didTruncate = true
                            break
                        } else {
                            if index < legs.count - 1 {
                                newTransferStops.append(alightingStop)
                            } else {
                                newFinalDestStop = alightingStop
                            }
                        }
                    }
                } else {
                    // We walked past this entire leg (startIndex == endIndex).
                    // We don't update physical coordinates here, so the next leg will calculate
                    // a walking route straight from our previous location to its start stop!
                }
            }
            
            if !didTruncate, let dest = destinationCoordinate, let finalStop = newFinalDestStop {
                let finalLoc = CLLocation(latitude: finalStop.latitude, longitude: finalStop.longitude)
                let distance = finalLoc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
                let walkingTime = distance / userSettings.walkingSpeed
                let arrivalTimeIfWalking = finalStop.expectedArrivalTime.addingTimeInterval(walkingTime)
                
                let walkLeg = ItineraryLeg(
                    legIndex: legs.count,
                    mode: .foot,
                    lineDescription: "Gå til destinasjonen",
                    waitTimeMinutes: nil,
                    transferStationName: nil,
                    optimalBoardingStop: nil,
                    skippedStopsCount: 0,
                    boardingStopName: finalStop.name,
                    boardingTime: finalStop.expectedArrivalTime,
                    alightingStopName: "Destinasjon",
                    alightingTime: arrivalTimeIfWalking
                )
                newItinerary.append(walkLeg)
                
                let startCoord = finalLoc.coordinate
                let destCoord = dest
                do {
                    let route = try await getWalkingRoute(start: startCoord, end: destCoord)
                    newWalkingRoutes.append(WalkingRoute(polyline: route.polyline))
                } catch {
                    print("Kunne ikke beregne siste gå-rute: \(error.localizedDescription)")
                }
            }
            
            self.optimalStops = newOptimalStops
            self.transferStops = newTransferStops
            self.finalDestinationStop = newFinalDestStop
            self.itinerary = newItinerary
            self.walkingRoutes = newWalkingRoutes
            self.transitPolylines = newTransitPolylines
            
            var uniqueStops: [TransitStop] = []
            var seenIds = Set<String>()
            for stop in combinedStops {
                if !seenIds.contains(stop.id) {
                    uniqueStops.append(stop)
                    seenIds.insert(stop.id)
                }
            }
            
            self.allStops = uniqueStops
            
            if let firstStop = self.allStops.first {
                self.closestStop = firstStop
            }
            
            if let firstOptimal = self.optimalStops[legs.first?.serviceJourneyId ?? ""] {
                let coord = CLLocationCoordinate2D(latitude: firstOptimal.latitude, longitude: firstOptimal.longitude)
                self.cameraPosition = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1000, longitudinalMeters: 1000))
            } else if let closest = self.closestStop {
                let coord = CLLocationCoordinate2D(latitude: closest.latitude, longitude: closest.longitude)
                self.cameraPosition = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1000, longitudinalMeters: 1000))
            }
            
        } catch let error as ActiveTransitError {
            self.errorMessage = "Feil med Aktiv Overgang: \(error.localizedDescription)"
        } catch {
            self.errorMessage = "En uventet feil oppstod: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}
