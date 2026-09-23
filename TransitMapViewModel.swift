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
    private let router = ActiveTransitRouter(enturClientName: "kollektiv-ios-app")
    
    func fetchActiveTransitRoute(currentLocation: CLLocation, trip: TransitTrip, destinationCoordinate: CLLocationCoordinate2D?, userSettings: UserSettings) async {
        guard !hasFetchedRoute else { return }
        hasFetchedRoute = true
        
        isLoading = true
        errorMessage = nil
        
        do {
            let networkClient = EnturNetworkClient(clientName: "kollektiv-ios-app")
            
            var combinedStops: [TransitStop] = []
            var newTransferStops: [TransitStop] = []
            var newFinalDestStop: TransitStop? = nil
            var newOptimalStops: [String: TransitStop] = [:]
            var newItinerary: [ItineraryLeg] = []
            var newWalkingRoutes: [WalkingRoute] = []
            var newTransitPolylines: [[CLLocationCoordinate2D]] = []
            
            let legs = trip.transitLegs.isEmpty ? [TransitLeg(serviceJourneyId: trip.mainServiceJourneyId, startName: nil, destinationName: trip.destinationName, mode: trip.mode, description: trip.description)] : trip.transitLegs
            
            var previousLegEndStop: TransitStop? = nil
            var didTruncate = false
            
            for (index, leg) in legs.enumerated() {
                let fetchedStops = try await networkClient.fetchSubsequentStops(for: leg.serviceJourneyId)
                
                var startIndex = 0
                if let startName = leg.startName, let idx = fetchedStops.firstIndex(where: { $0.name == startName }) {
                    startIndex = idx
                }
                
                var endIndex = fetchedStops.count - 1
                if let destName = leg.destinationName, let idx = fetchedStops.firstIndex(where: { $0.name == destName }) {
                    endIndex = idx
                }
                
                var optimalForThisLeg: TransitStop? = nil
                var startCoordForWalking: CLLocationCoordinate2D? = nil
                do {
                    if startIndex <= endIndex {
                        let relevantStops = Array(fetchedStops[startIndex...endIndex])
                        
                        if index == 0 {
                            startCoordForWalking = currentLocation.coordinate
                            optimalForThisLeg = try await router.findOptimalBoardingStop(
                                stops: relevantStops,
                                currentPosition: currentLocation,
                                startTime: Date(),
                                walkingSpeed: userSettings.walkingSpeed,
                                safetyMargin: userSettings.safetyMargin
                            )
                        } else if let prevEnd = previousLegEndStop {
                            startCoordForWalking = CLLocationCoordinate2D(latitude: prevEnd.latitude, longitude: prevEnd.longitude)
                            optimalForThisLeg = try await router.findOptimalBoardingStop(
                                stops: relevantStops,
                                currentPosition: CLLocation(latitude: prevEnd.latitude, longitude: prevEnd.longitude),
                                startTime: prevEnd.expectedArrivalTime,
                                walkingSpeed: userSettings.walkingSpeed,
                                safetyMargin: userSettings.safetyMargin
                            )
                        }
                    }
                } catch {
                    // Fant ikke noe bedre stopp
                }
                
                var skippedCount = 0
                if let optimal = optimalForThisLeg {
                    newOptimalStops[leg.serviceJourneyId] = optimal
                    
                    if let optIdx = fetchedStops.firstIndex(where: { $0.id == optimal.id }), optIdx >= startIndex, optIdx <= endIndex {
                        if optIdx > startIndex {
                            skippedCount = optIdx - startIndex
                            startIndex = optIdx
                        }
                    }
                }
                
                if index == 0, let startCoord = startCoordForWalking, startIndex < fetchedStops.count {
                    let actualStartStop = fetchedStops[startIndex]
                    let request = MKDirections.Request()
                    request.source = MKMapItem(placemark: MKPlacemark(coordinate: startCoord))
                    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: actualStartStop.latitude, longitude: actualStartStop.longitude)))
                    request.transportType = .walking
                    
                    do {
                        let response = try await MKDirections(request: request).calculate()
                        if let route = response.routes.first {
                            newWalkingRoutes.append(WalkingRoute(route: route))
                        }
                    } catch {
                        print("Kunne ikke beregne gå-rute: \(error.localizedDescription)")
                    }
                }
                
                var legWaitTimeMinutes: Int? = nil
                var transferStation: String? = nil
                
                if index > 0, let prevEnd = previousLegEndStop, startIndex < fetchedStops.count {
                    let boardingStop = fetchedStops[startIndex]
                    let waitTime = boardingStop.expectedArrivalTime.timeIntervalSince(prevEnd.expectedArrivalTime)
                    legWaitTimeMinutes = Int(max(0, waitTime / 60))
                    transferStation = prevEnd.name
                    
                    if prevEnd.id != boardingStop.id {
                        let request = MKDirections.Request()
                        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: prevEnd.latitude, longitude: prevEnd.longitude)))
                        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: boardingStop.latitude, longitude: boardingStop.longitude)))
                        request.transportType = .walking
                        do {
                            let response = try await MKDirections(request: request).calculate()
                            if let route = response.routes.first {
                                newWalkingRoutes.append(WalkingRoute(route: route))
                            }
                        } catch {
                             print("Kunne ikke beregne gå-rute for overgang: \(error.localizedDescription)")
                        }
                    }
                }
                
                if startIndex <= endIndex {
                    let legStops = Array(fetchedStops[startIndex...endIndex])
                    combinedStops.append(contentsOf: legStops)
                    
                    let polyCoords = legStops.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    newTransitPolylines.append(polyCoords)
                    
                    if let boardingStop = legStops.first, let alightingStop = legStops.last {
                        let itinLeg = ItineraryLeg(
                            legIndex: index,
                            mode: leg.mode,
                            lineDescription: leg.description,
                            waitTimeMinutes: legWaitTimeMinutes,
                            transferStationName: transferStation,
                            optimalBoardingStop: optimalForThisLeg,
                            skippedStopsCount: skippedCount,
                            boardingStopName: boardingStop.name,
                            boardingTime: boardingStop.expectedArrivalTime,
                            alightingStopName: alightingStop.name,
                            alightingTime: alightingStop.expectedArrivalTime
                        )
                        newItinerary.append(itinLeg)
                    }
                    
                    previousLegEndStop = legStops.last
                    
                    var shouldTruncate = false
                    
                    if let dest = destinationCoordinate, index < legs.count - 1, let alightingStop = legStops.last {
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
                            
                            let request = MKDirections.Request()
                            request.source = MKMapItem(placemark: MKPlacemark(coordinate: alightingLoc.coordinate))
                            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
                            request.transportType = .walking
                            do {
                                let response = try await MKDirections(request: request).calculate()
                                if let route = response.routes.first {
                                    newWalkingRoutes.append(WalkingRoute(route: route))
                                }
                            } catch {
                                print("Kunne ikke beregne gå-rute: \(error.localizedDescription)")
                            }
                        }
                    }
                    
                    if shouldTruncate {
                        didTruncate = true
                        break
                    } else {
                        if index < legs.count - 1 {
                            if let lastStop = legStops.last {
                                newTransferStops.append(lastStop)
                            }
                        } else {
                            newFinalDestStop = legStops.last
                        }
                    }
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
                
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: finalLoc.coordinate))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
                request.transportType = .walking
                do {
                    let response = try await MKDirections(request: request).calculate()
                    if let route = response.routes.first {
                        newWalkingRoutes.append(WalkingRoute(route: route))
                    }
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
