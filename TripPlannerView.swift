import SwiftUI
import MapKit
import ActiveTransit

enum SearchFocus: Hashable {
    case from
    case to
}

struct TripPlannerView: View {
    @Namespace var mapScope
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    
    @State private var startCoordinate: CLLocationCoordinate2D?
    @State private var startName: String = "Min posisjon"
    @State private var searchQueryFrom = ""
    
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var destinationName: String = "Valgt sted"
    @State private var searchQueryTo = ""
    
    @State private var trips: [TransitTrip] = []
    @State private var isLoadingTrips = false
    @State private var errorMessage: String?
    
    // For navigation to TransitMapView
    @State private var selectedTrip: TransitTrip?
    
    // For Search
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocus: SearchFocus?
    
    private let router = ActiveTransitRouter(enturClientName: "kollektiv-ios-app")
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var userSettings: UserSettings
    @EnvironmentObject private var favoritesManager: FavoritesManager
    
    @State private var showSettings = false
    @State private var showSaveFavoriteSheet = false
    @State private var isEditingStartLocation = false
    @State private var showTripListSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Map
                MapReader { reader in
                    Map(position: $position, scope: mapScope) {
                        UserAnnotation()
                        
                        if let start = startCoordinate ?? locationManager.location?.coordinate {
                            Marker(startName, coordinate: start)
                                .tint(.green)
                        }
                        
                        if let dest = destinationCoordinate {
                            Marker(destinationName, coordinate: dest)
                                .tint(.blue)
                        }
                    }
                    .onTapGesture { screenCoordinate in
                        // Hvis brukeren holder på med et søk, skal trykk på kartet kun lukke tastaturet/søket
                        if searchFocus != nil || isEditingStartLocation {
                            withAnimation {
                                searchFocus = nil
                                isEditingStartLocation = false
                            }
                            return
                        }
                        
                        if let location = reader.convert(screenCoordinate, from: .local) {
                            withAnimation {
                                destinationCoordinate = location
                                destinationName = "Henter adresse..."
                                searchQueryTo = destinationName
                                searchFocus = nil
                                searchResults = []
                                trips = []
                                errorMessage = nil
                                showTripListSheet = true
                            }
                            
                            Task {
                                let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
                                if let placemarks = try? await CLGeocoder().reverseGeocodeLocation(clLocation),
                                   let placemark = placemarks.first {
                                    // Velg gatenavn (thoroughfare) eller stedsnavn (name)
                                    let name = placemark.thoroughfare ?? placemark.name ?? "Kartposisjon"
                                    await MainActor.run {
                                        // Sjekk at brukeren ikke har trykket på et nytt sted i mellomtiden
                                        if destinationCoordinate?.latitude == location.latitude && destinationCoordinate?.longitude == location.longitude {
                                            destinationName = name
                                            searchQueryTo = name
                                        }
                                    }
                                } else {
                                    await MainActor.run {
                                        if destinationCoordinate?.latitude == location.latitude && destinationCoordinate?.longitude == location.longitude {
                                            destinationName = "Kartposisjon"
                                            searchQueryTo = "Kartposisjon"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .ignoresSafeArea()
                
                // Floating Search Area
                VStack(spacing: 8) {
                    // Collapsed "Fra"-knapp (uten bakgrunn, over søkefeltet)
                    if !isEditingStartLocation && startCoordinate == nil {
                        HStack {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isEditingStartLocation = true
                                    searchFocus = .from
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "location.fill")
                                    Text("Fra: Min posisjon")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.15), radius: 5)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Floating Search Card (Fra / Til)
                    VStack(spacing: 0) {
                        // "Fra" Field (skjult som standard)
                    if isEditingStartLocation || startCoordinate != nil {
                        HStack {
                            Text("Fra:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 35, alignment: .leading)
                            
                            TextField("Min posisjon", text: $searchQueryFrom)
                                .focused($searchFocus, equals: .from)
                                .onChange(of: searchQueryFrom) { _, newValue in
                                    if searchFocus == .from {
                                        handleSearchChange(newValue)
                                    }
                                }
                                .onSubmit {
                                    executeImmediateSearch(query: searchQueryFrom, for: .from)
                                }
                            
                            if !searchQueryFrom.isEmpty && searchFocus == .from {
                                Button {
                                    searchQueryFrom = ""
                                    startCoordinate = nil
                                    startName = "Min posisjon"
                                    searchResults = []
                                    withAnimation {
                                        isEditingStartLocation = false
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        
                        Divider()
                            .padding(.leading, 51)
                    }
                    
                    // "Til" Field (Hovedfokus)
                    HStack {
                        Image(systemName: searchFocus == .to ? "magnifyingglass.circle.fill" : "magnifyingglass")
                            .font(.title3)
                            .foregroundColor(searchFocus == .to ? .blue : .secondary)
                            .frame(width: 35, alignment: .leading)
                        
                        TextField("Hvor vil du reise?", text: $searchQueryTo)
                            .focused($searchFocus, equals: .to)
                            .font(.body)
                            .onChange(of: searchQueryTo) { _, newValue in
                                if searchFocus == .to {
                                    handleSearchChange(newValue)
                                }
                            }
                            .onSubmit {
                                executeImmediateSearch(query: searchQueryTo, for: .to)
                            }
                        
                        if !searchQueryTo.isEmpty && searchFocus == .to {
                            Button {
                                searchQueryTo = ""
                                destinationCoordinate = nil
                                destinationName = "Valgt sted"
                                searchResults = []
                                showTripListSheet = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    
                    }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    .padding(.horizontal)
                    
                    // Favorites Chips (Visible when a field is focused)
                    if searchFocus != nil && !favoritesManager.favorites.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(favoritesManager.favorites) { favorite in
                                    Button {
                                        selectFavorite(favorite, for: searchFocus!)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: favorite.type.iconName)
                                            Text(favorite.name)
                                                .font(.subheadline)
                                                .bold()
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color.blue.opacity(0.15))
                                        .foregroundColor(.blue)
                                        .cornerRadius(16)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                    }
                    
                    // Search Results
                    if !searchResults.isEmpty && searchFocus != nil {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(searchResults.prefix(5).indices, id: \.self) { index in
                                let item = searchResults[index]
                                Button {
                                    selectSearchResult(item, for: searchFocus!)
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
                        .padding(.top, 8)
                        .shadow(radius: 10)
                    }
                }
                .padding(.top, 16)
                .zIndex(2)
                
                // Map Controls
                    VStack(spacing: 16) {
                        Spacer()
                        
                        HStack {
                            Spacer()
                            VStack(spacing: 10) {
                                MapCompass(scope: mapScope)
                                MapUserLocationButton(scope: mapScope)
                            }
                            .buttonBorderShape(.circle)
                            .padding(.trailing, 16)
                        }
                    }
                    .zIndex(3)
                    .padding(.bottom, 24)
            }
            .navigationTitle("AktivOvergang")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("Innstillinger")
                }
            }
            .sheet(isPresented: Binding(
                get: { showTripListSheet },
                set: { isPresented in
                    showTripListSheet = isPresented
                }
            )) {
                VStack(spacing: 16) {
                    if trips.isEmpty && !isLoadingTrips {
                        VStack(spacing: 12) {
                            Button(action: searchTrips) {
                                Text("Søk ruter")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                            
                            Button {
                                showSaveFavoriteSheet = true
                            } label: {
                                Label("Lagre destinasjon som favoritt", systemImage: "star.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 24)
                    } else if isLoadingTrips {
                        ProgressView("Søker i Entur...")
                            .padding(.top, 32)
                        Spacer()
                    } else {
                        // List of trips
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Velg avgang for Aktiv Overgang:")
                                .font(.headline)
                                .padding(.top, 24)
                                .padding(.horizontal)
                                .padding(.bottom, 12)
                            
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(trips) { trip in
                                        Button {
                                            let generator = UISelectionFeedbackGenerator()
                                            generator.selectionChanged()
                                            selectedTrip = trip
                                            showTripListSheet = false
                                        } label: {
                                            HStack(spacing: 16) {
                                                Image(systemName: trip.mode.iconName)
                                                    .font(.title)
                                                    .foregroundColor(.blue)
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(trip.description)
                                                        .font(.subheadline)
                                                        .bold()
                                                    
                                                    let bytter = trip.transitLegs.count > 1 ? trip.transitLegs.count - 1 : 0
                                                    Text(bytter == 0 ? "Direkte" : "\(bytter) bytte(r)")
                                                        .font(.caption)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.secondary.opacity(0.2))
                                                        .cornerRadius(4)
                                                }
                                                
                                                Spacer()
                                                
                                                VStack(alignment: .trailing, spacing: 4) {
                                                    Text(trip.expectedStartTime.formatted(date: .omitted, time: .shortened))
                                                        .font(.subheadline)
                                                        .bold()
                                                    Text(trip.expectedEndTime.formatted(date: .omitted, time: .shortened))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                Image(systemName: "chevron.right")
                                                    .foregroundColor(.gray)
                                                    .padding(.leading, 4)
                                            }
                                            .padding()
                                            .background(Color(.secondarySystemBackground))
                                            .cornerRadius(12)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 24)
                            }
                        }
                    }
                    
                    if let error = errorMessage {
                        VStack(spacing: 8) {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                            
                            Button {
                                searchTrips()
                            } label: {
                                Label("Prøv igjen", systemImage: "arrow.clockwise")
                                    .font(.caption)
                                    .bold()
                            }
                        }
                    }
                }
                .presentationDetents(trips.isEmpty ? [.height(150)] : [.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled(false)
                .sheet(isPresented: $showSaveFavoriteSheet) {
                    if let dest = destinationCoordinate {
                        SaveFavoriteView(coordinate: dest, defaultName: destinationName)
                    }
                }
            }
            .navigationDestination(item: $selectedTrip) { trip in
                if let dest = destinationCoordinate {
                    let startLoc = startCoordinate ?? locationManager.location?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                    TransitMapView(trip: trip, destinationCoordinate: dest, startCoordinate: startLoc)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: selectedTrip) { _, newValue in
                if newValue == nil && !trips.isEmpty {
                    showTripListSheet = true
                }
            }
            .onAppear {
                locationManager.requestAuthorization()
            }
        }
        .mapScope(mapScope)
    }
    
    private func searchTrips() {
        guard let dest = destinationCoordinate else {
            errorMessage = "Mangler destinasjon."
            return
        }
        guard let start = startCoordinate ?? locationManager.location?.coordinate else {
            errorMessage = "Mangler startposisjon."
            return
        }
        
        isLoadingTrips = true
        errorMessage = nil
        searchFocus = nil
        
        Task {
            do {
                let fetchedTrips = try await router.fetchTrips(
                    from: start,
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
    
    private func handleSearchChange(_ newValue: String) {
        searchTask?.cancel()
        if newValue.isEmpty {
            searchResults = []
        } else {
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { performSearch(query: newValue) }
            }
        }
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else { return }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        if let currentLoc = locationManager.location {
            request.region = MKCoordinateRegion(center: currentLoc.coordinate, latitudinalMeters: 50000, longitudinalMeters: 50000)
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response else {
                self.errorMessage = "Klarte ikke å søke opp stedet."
                return
            }
            var filtered = response.mapItems.filter { item in
                let countryCode = item.placemark.countryCode
                let country = item.placemark.country
                return countryCode == "NO" || country == "Norway" || country == "Norge" || countryCode == nil
            }
            
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
    
    private func executeImmediateSearch(query: String, for focus: SearchFocus) {
        guard !query.isEmpty else { return }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        if let currentLoc = locationManager.location {
            request.region = MKCoordinateRegion(center: currentLoc.coordinate, latitudinalMeters: 50000, longitudinalMeters: 50000)
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let response = response else { return }
            
            var filtered = response.mapItems.filter { item in
                let countryCode = item.placemark.countryCode
                let country = item.placemark.country
                return countryCode == "NO" || country == "Norway" || country == "Norge" || countryCode == nil
            }
            
            if let userLoc = self.locationManager.location {
                filtered.sort { a, b in
                    let loc1 = a.placemark.location
                    let loc2 = b.placemark.location
                    let dist1 = loc1?.distance(from: userLoc) ?? Double.greatestFiniteMagnitude
                    let dist2 = loc2?.distance(from: userLoc) ?? Double.greatestFiniteMagnitude
                    return dist1 < dist2
                }
            }
            
            if let first = filtered.first {
                DispatchQueue.main.async {
                    self.selectSearchResult(first, for: focus)
                }
            }
        }
    }
    
    private func selectSearchResult(_ item: MKMapItem, for focus: SearchFocus) {
        let coordinate = item.placemark.coordinate
        let name = item.name ?? "Valgt sted"
        withAnimation {
            if focus == .from {
                self.startCoordinate = coordinate
                self.startName = name
                self.searchQueryFrom = name
            } else {
                self.destinationCoordinate = coordinate
                self.destinationName = name
                self.searchQueryTo = name
                self.showTripListSheet = true
            }
            self.position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
            self.searchResults = []
            self.trips = []
            self.errorMessage = nil
            self.searchFocus = nil
        }
    }
    
    private func selectFavorite(_ favorite: FavoriteLocation, for focus: SearchFocus) {
        let coordinate = favorite.coordinate
        withAnimation {
            if focus == .from {
                self.startCoordinate = coordinate
                self.startName = favorite.name
                self.searchQueryFrom = favorite.name
            } else {
                self.destinationCoordinate = coordinate
                self.destinationName = favorite.name
                self.searchQueryTo = favorite.name
                self.showTripListSheet = true
            }
            self.position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
            self.searchResults = []
            self.trips = []
            self.errorMessage = nil
            self.searchFocus = nil
        }
    }
}
