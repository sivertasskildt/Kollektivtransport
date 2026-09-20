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
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    @StateObject private var locationManager = LocationManager()
    
    private let router = ActiveTransitRouter(enturClientName: "kollektiv-ios-app")
    
    // Rute-ID-en sendes inn fra reiseplanleggeren
    let serviceJourneyId: String
    
    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
                
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
                            
                            Text("Aktiv Venting")
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
            // For å vise alle stopp på kartet (som en bonus for context) bruker vi en underliggende
            let networkClient = EnturNetworkClient(clientName: "kollektiv-ios-app")
            
            // Vi henter alle stopp for den valgte reisen
            async let fetchedStops = networkClient.fetchSubsequentStops(for: serviceJourneyId)
            
            // Vi regner ut det optimale stoppet for denne reisen
            async let calculatedOptimalStop = router.findOptimalBoardingStop(
                for: serviceJourneyId,
                currentPosition: currentLocation,
                walkingSpeed: 1.4,
                safetyMargin: 120, // 2 min margin
                preciseWalkTimeProvider: nil
            )
            
            self.allStops = try await fetchedStops
            self.optimalStop = try await calculatedOptimalStop
            
            // Fokuser kameraet på det optimale stoppet
            if let optimal = self.optimalStop {
                let coord = CLLocationCoordinate2D(latitude: optimal.latitude, longitude: optimal.longitude)
                withAnimation {
                    self.cameraPosition = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1000, longitudinalMeters: 1000))
                }
            }
            
        } catch let error as ActiveTransitError {
            self.errorMessage = "Feil med Aktiv Venting: \(error.localizedDescription)"
        } catch {
            self.errorMessage = "En uventet feil oppstod: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

#Preview {
    TransitMapView(serviceJourneyId: "dummy-id")
}
