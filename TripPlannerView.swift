import SwiftUI
import MapKit
import ActiveTransit

struct TripPlannerView: View {
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var trips: [TransitTrip] = []
    @State private var isLoadingTrips = false
    @State private var errorMessage: String?
    
    // For navigation to TransitMapView
    @State private var selectedTrip: TransitTrip?
    
    // For Search
    @State private var searchQuery = ""
    @State private var searchResults: [MKMapItem] = []
    
    private let router = ActiveTransitRouter(enturClientName: "kollektiv-ios-app")
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map
                MapReader { reader in
                    Map(position: $position) {
                        UserAnnotation()
                        
                        if let dest = destinationCoordinate {
                            Marker("Destinasjon", coordinate: dest)
                                .tint(.blue)
                        }
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                    }
                    .onTapGesture { screenCoordinate in
                        if let location = reader.convert(screenCoordinate, from: .local) {
                            withAnimation {
                                destinationCoordinate = location
                                trips = []
                                errorMessage = nil
                            }
                        }
                    }
                }
                .ignoresSafeArea()
                
                // Search Results Overlay
                if !searchResults.isEmpty {
                    VStack {
                        List(searchResults.indices, id: \.self) { index in
                            let item = searchResults[index]
                            Button {
                                selectSearchResult(item)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name ?? "Ukjent sted")
                                        .font(.body)
                                    Text(item.placemark.title ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .listStyle(.plain)
                        .background(Color(.systemBackground).opacity(0.95))
                        .cornerRadius(12)
                        .padding()
                        .shadow(radius: 5)
                        
                        Spacer()
                    }
                    .zIndex(1)
                }
                
                // Bottom Sheet / Panel
                VStack(spacing: 16) {
                    if destinationCoordinate == nil {
                        Text("Trykk i kartet for å velge hvor du vil reise")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemBackground).opacity(0.9))
                            .cornerRadius(12)
                            .shadow(radius: 5)
                            .padding()
                    } else {
                        VStack(spacing: 16) {
                            if trips.isEmpty && !isLoadingTrips {
                                Button(action: searchTrips) {
                                    Text("Søk etter avganger hit")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                }
                            } else if isLoadingTrips {
                                ProgressView("Søker i Entur...")
                                    .padding()
                            } else {
                                // List of trips
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Velg avgang for Aktiv Overgang:")
                                            .font(.headline)
                                        
                                        ForEach(trips) { trip in
                                            Button {
                                                selectedTrip = trip
                                            } label: {
                                                HStack {
                                                    Text(modeEmoji(for: trip.mode))
                                                        .font(.largeTitle)
                                                    
                                                    VStack(alignment: .leading) {
                                                        Text(trip.description)
                                                            .font(.subheadline)
                                                            .bold()
                                                        if let dest = trip.destinationName {
                                                            Text("mot \(dest)")
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                        }
                                                        Text("\(formatTime(trip.expectedStartTime)) - \(formatTime(trip.expectedEndTime))")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .foregroundColor(.gray)
                                                }
                                                .padding()
                                                .background(Color(.secondarySystemBackground))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .frame(maxHeight: 250)
                            }
                            
                            if let error = errorMessage {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .shadow(radius: 10)
                        .padding()
                    }
                }
            }
            .navigationTitle("Reiseplanlegger")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedTrip) { trip in
                TransitMapView(trip: trip)
            }
            .onAppear {
                locationManager.requestAuthorization()
            }
            .searchable(text: $searchQuery, prompt: "Søk etter sted eller adresse")
            .onChange(of: searchQuery) { newValue in
                if newValue.isEmpty {
                    searchResults = []
                }
            }
            .onSubmit(of: .search) {
                performSearch()
            }
        }
    }
    
    private func searchTrips() {
        guard let dest = destinationCoordinate,
              let currentLoc = locationManager.location else {
            errorMessage = "Mangler din posisjon eller destinasjon."
            return
        }
        
        isLoadingTrips = true
        errorMessage = nil
        
        Task {
            do {
                let fetchedTrips = try await router.fetchTrips(
                    from: currentLoc.coordinate,
                    to: dest
                )
                
                await MainActor.run {
                    self.trips = fetchedTrips
                    self.isLoadingTrips = false
                    if fetchedTrips.isEmpty {
                        self.errorMessage = "Fant ingen ruter."
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Feil ved henting: \(error.localizedDescription)"
                    self.isLoadingTrips = false
                }
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        
        // Prioriter søk i nærheten av brukeren
        if let currentLoc = locationManager.location {
            request.region = MKCoordinateRegion(center: currentLoc.coordinate, latitudinalMeters: 50000, longitudinalMeters: 50000)
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response else {
                self.errorMessage = "Klarte ikke å søke opp stedet."
                return
            }
            self.searchResults = response.mapItems
        }
    }
    
    private func selectSearchResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        withAnimation {
            self.destinationCoordinate = coordinate
            self.position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
            self.searchResults = []
            self.searchQuery = ""
            self.trips = []
            self.errorMessage = nil
        }
    }
    
    private func modeEmoji(for mode: String) -> String {
        switch mode.lowercased() {
        case "bus": return "🚌"
        case "tram": return "🚋"
        case "metro": return "🚇"
        case "rail": return "🚆"
        case "water": return "⛴️"
        default: return "🚍"
        }
    }
}
