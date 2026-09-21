import SwiftUI
import MapKit
import CoreLocation
import ActiveTransit

// LocationManager er nå flyttet til LocationManager.swift

// MARK: - Itinerary UI Model
struct ItineraryLeg: Identifiable {
    let id = UUID()
    let legIndex: Int
    let mode: String
    let lineDescription: String
    
    // Venting før denne etappen (nil for aller første etappe)
    let waitTimeMinutes: Int?
    let transferStationName: String?
    
    // Gå-informasjon (Aktiv Overgang)
    let optimalBoardingStop: TransitStop?
    let skippedStopsCount: Int
    
    // Påstigning
    let boardingStopName: String
    let boardingTime: Date?
    
    // Avstigning
    let alightingStopName: String
    let alightingTime: Date?
}

// MARK: - Walking Route UI Model
struct WalkingRoute: Identifiable {
    let id = UUID()
    let route: MKRoute
}

// MARK: - Transit Map View
struct TransitMapView: View {
    // Tilstand for kartet og data
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var allStops: [TransitStop] = []
    @State private var optimalStops: [String: TransitStop] = [:]
    @State private var closestStop: TransitStop?
    @State private var transferStops: [TransitStop] = []
    @State private var finalDestinationStop: TransitStop?
    @State private var itinerary: [ItineraryLeg] = []
    @State private var walkingRoutes: [WalkingRoute] = []
    @State private var transitPolylines: [[CLLocationCoordinate2D]] = []
    @State private var showItinerarySheet = true
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var hasFetchedRoute = false
    
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var userSettings: UserSettings
    
    private let router = ActiveTransitRouter(enturClientName: "kollektiv-ios-app")
    
    // Reisen sendes inn fra reiseplanleggeren
    let trip: TransitTrip
    var destinationCoordinate: CLLocationCoordinate2D? = nil
    
    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                
                // Tegn opp selve ruten som separate streker per etappe (Polyline)
                ForEach(transitPolylines.indices, id: \.self) { i in
                    if transitPolylines[i].count >= 2 {
                        MapPolyline(coordinates: transitPolylines[i])
                            .stroke(.blue, lineWidth: 5)
                    }
                }
                
                // Tegn opp gå-ruter (Aktiv Overgang)
                ForEach(walkingRoutes) { walkingRoute in
                    MapPolyline(walkingRoute.route.polyline)
                        .stroke(.green, style: StrokeStyle(lineWidth: 4, dash: [6, 6]))
                }
                
                // Tegn opp nærmeste stopp (Startpunkt)
                if let closest = closestStop, !optimalStops.values.contains(where: { $0.id == closest.id }) {
                    Annotation(closest.name, coordinate: CLLocationCoordinate2D(latitude: closest.latitude, longitude: closest.longitude)) {
                        VStack {
                            ZStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 32, height: 32)
                                    .shadow(radius: 4)
                                
                                Image(systemName: "figure.wave")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            Text(optimalStops.isEmpty ? "Gå hit (Aktiv Overgang)" : "Start")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.black)
                                .padding(2)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(4)
                        }
                    }
                }
                
                // Tegn opp alle andre stopp
                ForEach(allStops, id: \.id) { stop in
                    if !optimalStops.values.contains(where: { $0.id == stop.id }) && 
                       stop.id != closestStop?.id && 
                       !transferStops.contains(where: { $0.id == stop.id }) {
                        
                        Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 2)
                        }
                    }
                }
                
                // Tegn opp overganger (Bytte)
                ForEach(transferStops, id: \.id) { stop in
                    if !optimalStops.values.contains(where: { $0.id == stop.id }) && stop.id != closestStop?.id {
                        Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                            VStack {
                                ZStack {
                                    Circle()
                                        .fill(Color.purple)
                                        .frame(width: 32, height: 32)
                                        .shadow(radius: 4)
                                    
                                    Image(systemName: "arrow.triangle.swap")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                Text("Bytt her")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.black)
                                    .padding(2)
                                    .background(Color.white.opacity(0.9))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                
                // Tegn opp destinasjonen
                if let dest = destinationCoordinate {
                    Annotation("Destinasjon", coordinate: dest) {
                        VStack {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 32, height: 32)
                                    .shadow(radius: 4)
                                
                                Image(systemName: "flag.checkered")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            Text("Destinasjon")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.black)
                                .padding(2)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(4)
                        }
                    }
                }
                
                // Tegn opp optimale stopp (Active Waiting)
                ForEach(Array(optimalStops.values), id: \.id) { optimal in
                    Annotation(optimal.name, coordinate: CLLocationCoordinate2D(latitude: optimal.latitude, longitude: optimal.longitude)) {
                        VStack {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 44, height: 44)
                                    .shadow(radius: 4)
                                
                                Image(systemName: "figure.walk")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                            
                            Text("Gå hit (Aktiv Overgang)")
                                .font(.caption)
                                .bold()
                                .padding(4)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea()
            .safeAreaPadding(.top, 60)
            .onAppear {
                locationManager.requestAuthorization()
            }
            
            // Loading Overlay
            if isLoading {
                ProgressView("Beregner rute...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }
            
            // Feilmelding
            if let error = errorMessage {
                VStack {
                    Text(error)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .cornerRadius(8)
                    Spacer()
                }
                .padding(.top, 50)
            }
        }
        // Kjør ruteberegning når brukerens posisjon er funnet (kun første gang)
        .task(id: locationManager.location) {
            guard let location = locationManager.location, !hasFetchedRoute else { return }
            hasFetchedRoute = true
            await fetchActiveTransitRoute(currentLocation: location)
        }
        .sheet(isPresented: $showItinerarySheet) {
            ItineraryListView(itinerary: itinerary, isLoading: isLoading)
                .presentationDetents([.height(120), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
    }
    
    // MARK: - Hente og beregne rute
    @MainActor
    private func fetchActiveTransitRoute(currentLocation: CLLocation) async {
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
            
            // For bakoverkompatibilitet hvis transitLegs er tom (f.eks. i previews)
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
                
                // 2. Prøv å beregne optimalt stopp for DENNE etappen
                var optimalForThisLeg: TransitStop? = nil
                var startCoordForWalking: CLLocationCoordinate2D? = nil
                do {
                    if startIndex <= endIndex {
                        let relevantStops = Array(fetchedStops[startIndex...endIndex])
                        
                        if index == 0 {
                            // Første etappe: beregn fra brukerens nåværende posisjon
                            startCoordForWalking = currentLocation.coordinate
                            optimalForThisLeg = try await router.findOptimalBoardingStop(
                                stops: relevantStops,
                                currentPosition: currentLocation,
                                startTime: Date(),
                                walkingSpeed: userSettings.walkingSpeed,
                                safetyMargin: userSettings.safetyMargin
                            )
                        } else if let prevEnd = previousLegEndStop {
                            // Senere etapper: beregn fra der forrige etappe endte, på det tidspunktet den ankom!
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
                    
                    // Kutt den blå ruten, så den starter fra det optimale stoppet i stedet for default start
                    if let optIdx = fetchedStops.firstIndex(where: { $0.id == optimal.id }), optIdx >= startIndex, optIdx <= endIndex {
                        if optIdx > startIndex {
                            skippedCount = optIdx - startIndex
                            startIndex = optIdx
                        }
                    }
                }
                
                // Hent faktisk gå-rute via Apple Maps for den første etappen (fra din posisjon til første stopp)
                if index == 0, let startCoord = startCoordForWalking, startIndex < fetchedStops.count {
                    let actualStartStop = fetchedStops[startIndex]
                    let request = MKDirections.Request()
                    request.source = MKMapItem(placemark: MKPlacemark(coordinate: startCoord))
                    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: actualStartStop.latitude, longitude: actualStartStop.longitude)))
                    request.transportType = .walking
                    
                    do {
                        let directions = MKDirections(request: request)
                        let response = try await directions.calculate()
                        if let route = response.routes.first {
                            newWalkingRoutes.append(WalkingRoute(route: route))
                        }
                    } catch {
                        print("Kunne ikke beregne gå-rute: \(error)")
                    }
                }
                
                var legWaitTimeMinutes: Int? = nil
                var transferStation: String? = nil
                
                if index > 0, let prevEnd = previousLegEndStop, startIndex < fetchedStops.count {
                    let boardingStop = fetchedStops[startIndex]
                    // Beregn ventetid
                    let waitTime = boardingStop.expectedArrivalTime.timeIntervalSince(prevEnd.expectedArrivalTime)
                    legWaitTimeMinutes = Int(max(0, waitTime / 60))
                    transferStation = prevEnd.name
                    
                    // Tegn opp gå-rute hvis byttet krever at man går mellom to ulike stopp
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
                        } catch {}
                    }
                }
                
                if startIndex <= endIndex {
                    let legStops = Array(fetchedStops[startIndex...endIndex])
                    combinedStops.append(contentsOf: legStops)
                    
                    // Legg til koordinatene for denne etappen for tegning av blå strek
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
                                mode: "foot",
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
                                print("Kunne ikke beregne gå-rute: \(error)")
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
            
            // Hvis vi ikke avbrøt tidligere, regn ut siste gå-etappe fra endestasjonen til destinasjonen
            if !didTruncate, let dest = destinationCoordinate, let finalStop = newFinalDestStop {
                let finalLoc = CLLocation(latitude: finalStop.latitude, longitude: finalStop.longitude)
                let distance = finalLoc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
                let walkingTime = distance / userSettings.walkingSpeed
                let arrivalTimeIfWalking = finalStop.expectedArrivalTime.addingTimeInterval(walkingTime)
                
                let walkLeg = ItineraryLeg(
                    legIndex: legs.count,
                    mode: "foot",
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
                } catch {}
            }
            
            // Sett state
            self.optimalStops = newOptimalStops
            self.transferStops = newTransferStops
            self.finalDestinationStop = newFinalDestStop
            self.itinerary = newItinerary
            self.walkingRoutes = newWalkingRoutes
            self.transitPolylines = newTransitPolylines
            
            // Fjern eventuelle duplikater hvis en etappe slutter der neste starter (basert på ID)
            var uniqueStops: [TransitStop] = []
            var seenIds = Set<String>()
            for stop in combinedStops {
                if !seenIds.contains(stop.id) {
                    uniqueStops.append(stop)
                    seenIds.insert(stop.id)
                }
            }
            
            self.allStops = uniqueStops
            
            // Regn ut nærmeste stopp for første etappe (alltid den første i listen)
            if let firstStop = self.allStops.first {
                self.closestStop = firstStop
            }
            
            // Fokuser kameraet på første startpunkt / optimal stop
            if let firstOptimal = self.optimalStops[legs.first?.serviceJourneyId ?? ""] {
                let coord = CLLocationCoordinate2D(latitude: firstOptimal.latitude, longitude: firstOptimal.longitude)
                withAnimation {
                    self.cameraPosition = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1000, longitudinalMeters: 1000))
                }
            } else if let closest = self.closestStop {
                let coord = CLLocationCoordinate2D(latitude: closest.latitude, longitude: closest.longitude)
                withAnimation {
                    self.cameraPosition = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1000, longitudinalMeters: 1000))
                }
            }
            
        } catch let error as ActiveTransitError {
            self.errorMessage = "Feil med Aktiv Overgang: \(error.localizedDescription)"
        } catch {
            self.errorMessage = "En uventet feil oppstod: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - Itinerary List View
struct ItineraryListView: View {
    let itinerary: [ItineraryLeg]
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Reiseplan")
                    .font(.headline)
                    .padding()
                if let first = itinerary.first?.boardingTime, let last = itinerary.last?.alightingTime {
                    let diff = Int(last.timeIntervalSince(first) / 60)
                    Text("\(diff) min totalt")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.trailing)
                } else {
                    Spacer()
                }
                
                if isLoading {
                    ProgressView()
                        .padding(.trailing)
                }
            }
            
            Divider()
            
            if itinerary.isEmpty && !isLoading {
                ContentUnavailableView("Ingen reiseplan", systemImage: "map", description: Text("Kunne ikke laste inn ruten."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(itinerary) { leg in
                            ItineraryLegView(leg: leg)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct ItineraryLegView: View {
    let leg: ItineraryLeg
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Venting og bytte info (hvis ikke første etappe)
            if let waitTime = leg.waitTimeMinutes, let station = leg.transferStationName {
                HStack(alignment: .top, spacing: 16) {
                    VStack {
                        Circle().fill(Color.purple).frame(width: 12, height: 12)
                        Rectangle().fill(Color.purple).frame(width: 2, height: 30)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bytt på \(station)")
                            .font(.subheadline)
                            .bold()
                        
                        if leg.skippedStopsCount > 0, let optimal = leg.optimalBoardingStop {
                            Text("Aktiv Overgang: Du har \(waitTime) min ventetid. Gå \(leg.skippedStopsCount) stopp til \(optimal.name) for å holde deg i gang!")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .bold()
                        } else {
                            Text("Ventetid ca \(waitTime) min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Etappen
            HStack(alignment: .top, spacing: 16) {
                VStack {
                    Image(systemName: modeIcon(for: leg.mode))
                        .foregroundColor(leg.mode == "foot" ? .green : .blue)
                    Rectangle().fill(leg.mode == "foot" ? Color.green : Color.blue).frame(width: 2, height: 40)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let bTime = leg.boardingTime {
                            Text(bTime.formatted(date: .omitted, time: .shortened))
                                .bold()
                        }
                        Text(leg.boardingStopName)
                    }
                    
                    Text(leg.lineDescription)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(leg.mode == "foot" ? Color.green : Color.blue.opacity(0.1))
                        .foregroundColor(leg.mode == "foot" ? .black : .primary)
                        .bold(leg.mode == "foot")
                        .cornerRadius(4)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    
                    HStack {
                        if let aTime = leg.alightingTime {
                            Text(aTime.formatted(date: .omitted, time: .shortened))
                                .bold()
                                .foregroundColor(.secondary)
                        }
                        Text(leg.alightingStopName)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private func modeIcon(for mode: String) -> String {
        switch mode.lowercased() {
        case "bus": return "bus.fill"
        case "tram": return "tram.fill"
        case "metro": return "t.circle.fill"
        case "rail": return "train.side.front.car"
        case "water": return "ferry.fill"
        case "foot": return "figure.walk"
        default: return "bus.fill"
        }
    }
}

#Preview {
    TransitMapView(trip: TransitTrip(expectedStartTime: Date(), expectedEndTime: Date(), mainServiceJourneyId: "dummy-id", description: "Trikk 11", mode: "tram", destinationName: "Majorstuen", transitLegs: []), destinationCoordinate: nil)
}
