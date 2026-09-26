import SwiftUI

@main
struct KollektivApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var userSettings = UserSettings()
    @StateObject private var favoritesManager = FavoritesManager()
    
    var body: some Scene {
        WindowGroup {
            if userSettings.hasCompletedOnboarding {
                TripPlannerView()
                    .environmentObject(locationManager)
                    .environmentObject(userSettings)
                    .environmentObject(favoritesManager)
                    .environment(\.locale, .init(identifier: "nb_NO"))
            } else {
                OnboardingView()
                    .environmentObject(userSettings)
                    .environment(\.locale, .init(identifier: "nb_NO"))
            }
        }
    }
}
