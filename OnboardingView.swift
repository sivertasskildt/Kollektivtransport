import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var userSettings: UserSettings
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Tittel og Ikon
            VStack(spacing: 16) {
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.bottom, 8)
                
                Text("Velkommen til\nActive Transit")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Kollektiv-appen som hjelper deg å nå målet raskest mulig, samtidig som du får gått mest mulig.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)
            }
            
            // Innstillinger-kort
            VStack(alignment: .leading, spacing: 16) {
                Text("Hvor raskt går du?")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Picker("Hvor raskt går du?", selection: $userSettings.walkingSpeed) {
                    Text("Rolig (1.0 m/s)").tag(1.0)
                    Text("Normal (1.4 m/s)").tag(1.4)
                    Text("Rask (1.8 m/s)").tag(1.8)
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                
                Text("Dette brukes til å beregne hvor langt du rekker å gå før bussen kommer.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Kom i gang-knapp
            Button(action: {
                withAnimation {
                    userSettings.hasCompletedOnboarding = true
                }
            }) {
                Text("Kom i gang")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

#Preview {
    OnboardingView()
        .environmentObject(UserSettings())
}
