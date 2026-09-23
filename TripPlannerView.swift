import SwiftUI
import MapKit
import ActiveTransit

struct TripPlannerView: View {
    @Namespace var mapScope
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
    @State private var searchTask: Task<Void, Never>?
    
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
                    Map(position: $position, scope: mapScope) {
                        UserAnnotation()
                        
                        if let dest = destinationCoordinate {
                            Marker("Destinasjon", coordinate: dest)
                                .tint(.blue)
                        }
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
                                searchTask?.cancel()
                                if newValue.isEmpty {
                                    searchResults = []
                                } else {
                                    searchTask = Task {
                                        try? await Task.sleep(nanoseconds: 300_000_000)
                                        guard !Task.isCancelled else { return }
                                        await MainActor.run { performSearch() }
                                    }
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
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(searchResults.prefix(5).indices, id: \.self) { index in
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
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                
                                if index < min(searchResults.count, 5) - 1 {
                                    Divider().padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .shadow(radius: 10)
                    }
                }
                .zIndex(2)
                
                // Map Controls & Bottom Sheet (Combined)
                VStack(spacing: 16) {
                    Spacer()
                    
                    // Map Controls
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            MapCompass(scope: mapScope)
                            MapUserLocationButton(scope: mapScope)
                        }
                        .buttonBorderShape(.circle)
                        .padding(.trailing, 16)
                    }
                    
                    // Bottom Sheet / Panel
                    if destinationCoordinate == nil {
                        Text("Trykk på kartet for å velge hvor du vil reise")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                            .padding(.horizontal)
                            .padding(.bottom)
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
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
                .zIndex(3)
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
        .mapScope(mapScope)
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
            // Filtrer slik at vi kun viser resultater fra Norge
            var filtered = response.mapItems.filter { item in
                let countryCode = item.placemark.countryCode
                let country = item.placemark.country
                return countryCode == "NO" || country == "Norway" || country == "Norge" || countryCode == nil
            }
            
            // Sorter etter avstand fra brukeren
            if let userLoc = self.locationManager.location {
                filtered.sort { item1, item2 in
                    let loc1 = item1.placemark.location
                    let loc2 = item2.placemark.location
                    let dist1 = loc1?.distance(from: userLoc) ?? Double.greatestFiniteMagnitude
                    let dist2 = loc2?.distance(from: userLoc) ?? Double.greatestFiniteMagnitude
                    return dist1 < dist2
                }
            }
            
            self.searchResults = filtered
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
