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
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var userSettings: UserSettings
    
    @State private var showSettings = false
    
    @State private var isSearchFocused = false
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
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
                    .safeAreaPadding(.top, 160)
                }
                .ignoresSafeArea()
                .safeAreaPadding(.top, 90)
                
                // Floating Search Card
                VStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Søk etter sted eller adresse", text: $searchQuery)
                            .onSubmit {
                                performSearch()
                            }
                            .onChange(of: searchQuery) { newValue in
                                if newValue.isEmpty {
                                    searchResults = []
                                }
                            }
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    
                    // Search Results
                    if !searchResults.isEmpty {
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
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .frame(maxHeight: 250)
                        .shadow(radius: 10)
                    }
                }
                .zIndex(2)
                
                // Bottom Sheet / Panel
                VStack {
                    Spacer()
                    if destinationCoordinate == nil {
                        Text("Trykk på kartet for å velge hvor du vil reise")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
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
                                                HStack(spacing: 16) {
                                                    Image(systemName: modeIcon(for: trip.mode))
                                                        .font(.title)
                                                        .foregroundColor(.blue)
                                                    
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(trip.description)
                                                            .font(.subheadline)
                                                            .bold()
                                                        
                                                        HStack {
                                                            Text("\(formatTime(trip.expectedStartTime)) - \(formatTime(trip.expectedEndTime))")
                                                                .font(.subheadline)
                                                            
                                                            Text("(\(Int(trip.expectedEndTime.timeIntervalSince(trip.expectedStartTime) / 60)) min)")
                                                                .font(.subheadline)
                                                                .foregroundColor(.secondary)
                                                        }
                                                        
                                                        let bytter = trip.transitLegs.count > 1 ? trip.transitLegs.count - 1 : 0
                                                        Text(bytter == 0 ? "Direkte" : "\(bytter) bytte(r)")
                                                            .font(.caption)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.secondary.opacity(0.2))
                                                            .cornerRadius(4)
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
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .shadow(radius: 10)
                        .padding()
                    }
                }
            }
            .navigationTitle("Reiseplanlegger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.primary)
                    }
                }
            }
            .navigationDestination(item: $selectedTrip) { trip in
                if let dest = destinationCoordinate {
                    TransitMapView(trip: trip, destinationCoordinate: dest)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                locationManager.requestAuthorization()
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
    
    private func modeIcon(for mode: String) -> String {
        switch mode.lowercased() {
        case "bus": return "bus.fill"
        case "tram": return "tram.fill"
        case "metro": return "t.circle.fill"
        case "rail": return "train.side.front.car"
        case "water": return "ferry.fill"
        default: return "bus.fill"
        }
    }
}
