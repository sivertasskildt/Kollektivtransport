import SwiftUI

final class UserSettings: ObservableObject {
    // 1.0 = Rolig, 1.4 = Normal, 1.8 = Rask
    @AppStorage("walkingSpeed") var walkingSpeed: Double = 1.4
    
    // Sikkerhetsmargin (sekunder) for å rekke bussen
    @AppStorage("safetyMargin") var safetyMargin: Double = 60
    
    // Viser Onboarding-skjerm på første oppstart
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
}
