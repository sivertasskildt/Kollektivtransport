import SwiftUI
import MapKit
import CoreLocation
import ActiveTransit

// LocationManager er nå flyttet til LocationManager.swift

// MARK: - Itinerary UI Model
struct ItineraryLeg: Identifiable {
    let id = UUID()
    let legIndex: Int
    let mode: TransitMode
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

struct TransitMapView: View {
    @StateObject private var viewModel = TransitMapViewModel()
    @Namespace private var mapScope
    
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var userSettings: UserSettings
    
    // Reisen sendes inn fra reiseplanleggeren
    let trip: TransitTrip
    var destinationCoordinate: CLLocationCoordinate2D? = nil
    
    var body: some View {
        ZStack {
            Map(position: $viewModel.cameraPosition, scope: mapScope) {
                UserAnnotation()
                
                // Tegn opp selve ruten som separate streker per etappe (Polyline)
                ForEach(viewModel.transitPolylines.indices, id: \.self) { i in
                    if viewModel.transitPolylines[i].count >= 2 {
                        MapPolyline(coordinates: viewModel.transitPolylines[i])
                            .stroke(.blue, lineWidth: 5)
                    }
                }
                
                // Tegn opp gå-ruter (Aktiv Overgang)
                ForEach(viewModel.walkingRoutes) { walkingRoute in
                    MapPolyline(walkingRoute.route.polyline)
                        .stroke(.green, style: StrokeStyle(lineWidth: 4, dash: [6, 6]))
                }
                
                // Tegn opp nærmeste stopp (Startpunkt)
                if let closest = viewModel.closestStop, !viewModel.optimalStops.values.contains(where: { $0.id == closest.id }) {
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
                            Text(viewModel.optimalStops.isEmpty ? "Gå hit (Aktiv Overgang)" : "Start")
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
                ForEach(viewModel.allStops, id: \.id) { stop in
                    if !viewModel.optimalStops.values.contains(where: { $0.id == stop.id }) && 
                       stop.id != viewModel.closestStop?.id && 
                       !viewModel.transferStops.contains(where: { $0.id == stop.id }) {
                        
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
                ForEach(viewModel.transferStops, id: \.id) { stop in
                    if !viewModel.optimalStops.values.contains(where: { $0.id == stop.id }) && stop.id != viewModel.closestStop?.id {
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
                ForEach(Array(viewModel.optimalStops.values), id: \.id) { optimal in
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
                                .foregroundColor(.black)
                                .padding(4)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .onAppear {
                locationManager.requestAuthorization()
            }
            
            // Fjernet MapControls for å gi mer plass til kartet når ruten vises
            
            // Loading Overlay
            if viewModel.isLoading {
                ProgressView("Beregner rute...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }
            
            // Feilmelding
            if let error = viewModel.errorMessage {
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
        .mapScope(mapScope)
        // Kjør ruteberegning når brukerens posisjon er funnet (kun første gang)
        .task(id: locationManager.location) {
            guard let location = locationManager.location, !viewModel.hasFetchedRoute else { return }
            await viewModel.fetchActiveTransitRoute(currentLocation: location, trip: trip, destinationCoordinate: destinationCoordinate, userSettings: userSettings)
        }
        .sheet(isPresented: $viewModel.showItinerarySheet) {
            ItineraryListView(itinerary: viewModel.itinerary, isLoading: viewModel.isLoading)
                .presentationDetents([.height(120), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
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
                        .foregroundColor(leg.mode == .foot ? .green : .blue)
                    Rectangle().fill(leg.mode == .foot ? Color.green : Color.blue).frame(width: 2, height: 40)
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
                        .background(leg.mode == .foot ? Color.green : Color.blue.opacity(0.1))
                        .foregroundColor(leg.mode == .foot ? .black : .primary)
                        .bold(leg.mode == .foot)
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
    
    private func modeIcon(for mode: TransitMode) -> String {
        switch mode {
        case .bus: return "bus.fill"
        case .tram: return "tram.fill"
        case .metro: return "t.circle.fill"
        case .rail: return "train.side.front.car"
        case .water: return "ferry.fill"
        case .foot: return "figure.walk"
        default: return "bus.fill"
        }
    }
}

#Preview {
    TransitMapView(trip: TransitTrip(expectedStartTime: Date(), expectedEndTime: Date(), mainServiceJourneyId: "dummy-id", description: "Trikk 11", mode: .tram, destinationName: "Majorstuen", transitLegs: []), destinationCoordinate: nil)
}
