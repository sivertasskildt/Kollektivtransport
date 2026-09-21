import SwiftUI

@main
struct KollektivApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var userSettings = UserSettings()
    
    var body: some Scene {
        WindowGroup {
            if userSettings.hasCompletedOnboarding {
                TripPlannerView()
                    .environmentObject(locationManager)
                    .environmentObject(userSettings)
            } else {
                OnboardingView()
                    .environmentObject(userSettings)
            }
        }
    }
}
