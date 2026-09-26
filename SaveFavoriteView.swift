import SwiftUI
import CoreLocation

struct SaveFavoriteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var favoritesManager: FavoritesManager
    
    let coordinate: CLLocationCoordinate2D
    let defaultName: String
    
    @State private var name: String
    @State private var selectedType: FavoriteType = .custom
    
    init(coordinate: CLLocationCoordinate2D, defaultName: String) {
        self.coordinate = coordinate
        self.defaultName = defaultName
        _name = State(initialValue: defaultName)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Sted")) {
                    TextField("Navn på favoritt", text: $name)
                }
                
                Section(header: Text("Kategori")) {
                    Picker("Kategori", selection: $selectedType) {
                        ForEach(FavoriteType.allCases) { type in
                            HStack {
                                Image(systemName: type.iconName)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Lagre favoritt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Avbryt") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lagre") {
                        saveFavorite()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveFavorite() {
        let favorite = FavoriteLocation(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            type: selectedType
        )
        favoritesManager.add(favorite)
        dismiss()
    }
}
