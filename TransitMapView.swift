import SwiftUI
import MapKit
import CoreLocation
import ActiveTransit

// MARK: - Location Manager
/// En enkel LocationManager for å be om tillatelse og lytte til posisjonsoppdateringer.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startUpdating() {
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let firstLocation = locations.first {
            self.location = firstLocation
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startUpdating()
        }
    }
}

// MARK: - Transit Map View
struct TransitMapView: View {
    // Tilstand for kartet og data
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var allStops: [TransitStop] = []
    @State private var optimalStop: TransitStop?
    @State private var skippedStopsCount: Int?
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    @StateObject private var locationManager = LocationManager()
    
    private let router = ActiveTransitRouter(enturClientName: "kollektiv-ios-app")
    
    // Reisen sendes inn fra reiseplanleggeren
    let trip: TransitTrip
    
    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                
                // Tegn opp selve ruten som en strek (Polyline)
                if !allStops.isEmpty {
                    MapPolyline(coordinates: allStops.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(.blue, lineWidth: 5)
                }
                
                // Tegn opp alle stopp
                ForEach(allStops, id: \.id) { stop in
                    // Sjekk at det ikke er det optimale stoppet
                    if stop.id != optimalStop?.id {
                        Marker(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude))
                            .tint(.blue)
                    }
                }
                
                // Tegn opp optimalt stopp (Active Waiting)
                if let optimal = optimalStop {
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
                            
                            Text("Aktiv Overgang")
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
            .onAppear {
                locationManager.requestAuthorization()
            }
            
            // Info Panel i bunnen
            if let skipped = skippedStopsCount, skipped > 0 {
                VStack {
                    Spacer()
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 50, height: 50)
                            Image(systemName: "figure.walk")
                                .font(.title)
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aktiv Overgang")
                                .font(.headline)
                            Text("Du rekker å gå forbi \(skipped) stopp før avgangen din kommer!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemBackground).opacity(0.95))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                    .padding()
                }
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
        // Kjør ruteberegning når brukerens posisjon er funnet
        .task(id: locationManager.location) {
            guard let location = locationManager.location, optimalStop == nil else { return }
            await fetchActiveTransitRoute(currentLocation: location)
        }
    }
    
    // MARK: - Hente og beregne rute
    @MainActor
    private func fetchActiveTransitRoute(currentLocation: CLLocation) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let networkClient = EnturNetworkClient(clientName: "kollektiv-ios-app")
            
            // 1. Hent alle stopp
            let fetchedStops = try await networkClient.fetchSubsequentStops(for: trip.mainServiceJourneyId)
            
            // Kutt listen ved destinasjonen hvis vi har den
            if let destName = trip.destinationName,
               let destIndex = fetchedStops.firstIndex(where: { $0.name == destName }) {
                self.allStops = Array(fetchedStops.prefix(through: destIndex))
            } else {
                self.allStops = fetchedStops
            }
            
            // 2. Prøv å beregne optimalt stopp
            do {
                self.optimalStop = try await router.findOptimalBoardingStop(
                    for: trip.mainServiceJourneyId,
                    currentPosition: currentLocation,
                    walkingSpeed: 1.4,
                    safetyMargin: 120, // 2 min margin
                    preciseWalkTimeProvider: nil
                )
                
                // Fokuser kameraet på det optimale stoppet hvis vi fant et
                if let optimal = self.optimalStop {
                    // Regn ut hvor mange stopp vi går forbi
                    let closestStop = self.allStops.min { a, b in
                        let distA = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: currentLocation)
                        let distB = CLLocation(latitude: b.latitude, longitude: b.longitude).distance(from: currentLocation)
                        return distA < distB
                    }
                    
                    if let closest = closestStop,
                       let closestIndex = self.allStops.firstIndex(where: { $0.id == closest.id }),
                       let optimalIndex = self.allStops.firstIndex(where: { $0.id == optimal.id }),
                       optimalIndex > closestIndex {
                        self.skippedStopsCount = optimalIndex - closestIndex
                    } else {
                        self.skippedStopsCount = 0
                    }
                    
                    let coord = CLLocationCoordinate2D(latitude: optimal.latitude, longitude: optimal.longitude)
                    withAnimation {
                        self.cameraPosition = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1000, longitudinalMeters: 1000))
                    }
                }
            } catch ActiveTransitError.noBetterStopFound {
                // Helt normalt scenario: Brukeren er allerede på det beste stoppet,
                // eller det er for kort tid til å gå noen andre steder.
                // Vi lar bare optimalStop være nil, og tegner opp de vanlige stoppene.
                self.optimalStop = nil
            }
            
        } catch let error as ActiveTransitError {
            self.errorMessage = "Feil med Aktiv Overgang: \(error.localizedDescription)"
        } catch {
            self.errorMessage = "En uventet feil oppstod: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

}

#Preview {
    TransitMapView(trip: TransitTrip(expectedStartTime: Date(), expectedEndTime: Date(), mainServiceJourneyId: "dummy-id", description: "Trikk 11", mode: "tram", destinationName: "Majorstuen"))
}
