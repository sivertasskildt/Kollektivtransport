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
    @State private var selectedServiceJourneyId: String?
    
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
                                        Text("Velg avgang for Aktiv Venting:")
                                            .font(.headline)
                                        
                                        ForEach(trips) { trip in
                                            Button {
                                                selectedServiceJourneyId = trip.mainServiceJourneyId
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading) {
                                                        Text(trip.description)
                                                            .font(.subheadline)
                                                            .bold()
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
            .navigationDestination(item: $selectedServiceJourneyId) { journeyId in
                TransitMapView(serviceJourneyId: journeyId)
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
}
