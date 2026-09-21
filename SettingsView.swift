import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userSettings: UserSettings
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Gå-hastighet")) {
                    Picker("Hvor raskt går du?", selection: $userSettings.walkingSpeed) {
                        Text("🐢 Rolig (1.0 m/s)").tag(1.0)
                        Text("🚶 Normal (1.4 m/s)").tag(1.4)
                        Text("🏃 Rask (1.8 m/s)").tag(1.8)
                    }
                    .pickerStyle(.inline)
                }
                
                Section(header: Text("Sikkerhetsmargin")) {
                    Picker("Tid før avgang", selection: $userSettings.safetyMargin) {
                        Text("0 sek (Ingen margin!)").tag(0.0)
                        Text("30 sekunder").tag(30.0)
                        Text("1 minutt").tag(60.0)
                        Text("2 minutter").tag(120.0)
                        Text("3 minutter").tag(180.0)
                    }
                }
            }
            .navigationTitle("Innstillinger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ferdig") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(UserSettings())
}
