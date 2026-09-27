import SwiftUI
import MapKit
import CoreLocation
import ActiveTransit

// LocationManager er nå flyttet til LocationManager.swift
// ItineraryLeg og WalkingRoute er nå flyttet til ItineraryModels.swift

struct TransitMapView: View {
    @StateObject private var viewModel = TransitMapViewModel()
    @Namespace private var mapScope
    
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var userSettings: UserSettings
    
    // Reisen sendes inn fra reiseplanleggeren
    let trip: TransitTrip
    var destinationCoordinate: CLLocationCoordinate2D? = nil
    var startCoordinate: CLLocationCoordinate2D? = nil
    
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
                    MapPolyline(walkingRoute.polyline)
                        .stroke(.green, style: StrokeStyle(lineWidth: 4, dash: [6, 6]))
                }
                

                
                // Tegn opp alle andre stopp
                ForEach(viewModel.displayRegularStops) { stop in
                    Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(radius: 2)
                            .accessibilityLabel("Stopp: \(stop.name)")
                    }
                }
                
                // Tegn opp overganger (Bytte)
                ForEach(viewModel.displayTransferStops) { stop in
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
                                    .foregroundColor(.primary)
                                    .padding(2)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(4)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Bytt transport ved \(stop.name)")
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
                                .foregroundColor(.primary)
                                .padding(2)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Destinasjon")
                    }
                }
                
                // Tegn opp optimale stopp (Active Waiting)
                ForEach(viewModel.displayOptimalStops) { optimal in
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
                            
                            Text(optimal.id == viewModel.closestStop?.id ? "Gå hit" : "Gå hit (Aktiv Overgang)")
                                .font(.caption)
                                .bold()
                                .foregroundColor(.primary)
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Gå til \(optimal.name) for aktiv overgang")
                    }
                }
            }
            .ignoresSafeArea()
            .onAppear {
                locationManager.requestAuthorization()
            }
            
            // Loading Overlay
            if viewModel.isLoading {
                ProgressView("Beregner rute...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }
            
            // Feilmelding med "Prøv igjen"-knapp (#19)
            if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        viewModel.retry()
                        let location = startCoordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) } ?? locationManager.location
                        if let loc = location {
                            Task {
                                await viewModel.fetchActiveTransitRoute(
                                    currentLocation: loc,
                                    trip: trip,
                                    destinationCoordinate: destinationCoordinate,
                                    userSettings: userSettings
                                )
                            }
                        }
                    } label: {
                        Label("Prøv igjen", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.25))
                            .cornerRadius(8)
                    }
                    .accessibilityLabel("Prøv å laste ruten på nytt")
                }
                .padding()
                .background(Color.red.opacity(0.9))
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .padding(.top, 50)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .mapScope(mapScope)
        // Kjør ruteberegning når brukerens posisjon er funnet (kun første gang)
        .task(id: locationManager.location) {
            guard !viewModel.hasFetchedRoute else { return }
            let location = startCoordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) } ?? locationManager.location
            guard let loc = location else { return }
            await viewModel.fetchActiveTransitRoute(currentLocation: loc, trip: trip, destinationCoordinate: destinationCoordinate, userSettings: userSettings)
        }
        .sheet(isPresented: $viewModel.showItinerarySheet) {
            ItineraryListView(itinerary: viewModel.itinerary, isLoading: viewModel.isLoading)
                .presentationDetents([.height(120), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
        // Haptic feedback når optimal stopp er funnet (#15)
        .onChange(of: viewModel.optimalStops.count) { _, newCount in
            if newCount > 0 {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
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
                    .accessibilityAddTraits(.isHeader)
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
                        .accessibilityLabel("Laster reiseplan")
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Bytt på \(station). Ventetid \(waitTime) minutter")
            }
            
            // Etappen
            HStack(alignment: .top, spacing: 16) {
                VStack {
                    Image(systemName: leg.mode.iconName)
                        .foregroundColor(leg.mode.accentColor)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel(legAccessibilityLabel)
        }
    }
    
    /// Builds a comprehensive VoiceOver label for this leg.
    private var legAccessibilityLabel: String {
        var parts: [String] = []
        parts.append(leg.lineDescription)
        parts.append("fra \(leg.boardingStopName)")
        if let bTime = leg.boardingTime {
            parts.append("klokken \(bTime.formatted(date: .omitted, time: .shortened))")
        }
        parts.append("til \(leg.alightingStopName)")
        if let aTime = leg.alightingTime {
            parts.append("klokken \(aTime.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    TransitMapView(trip: TransitTrip(expectedStartTime: Date(), expectedEndTime: Date(), mainServiceJourneyId: "dummy-id", description: "Trikk 11", mode: .tram, destinationName: "Majorstuen", transitLegs: []), destinationCoordinate: nil)
}
