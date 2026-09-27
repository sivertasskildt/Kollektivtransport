import SwiftUI
import MapKit

struct EditFavoriteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var favoritesManager: FavoritesManager
    
    let originalFavorite: FavoriteLocation
    
    @State private var name: String
    @State private var selectedType: FavoriteType
    @State private var coordinate: CLLocationCoordinate2D
    
    @State private var searchQuery = ""
    @State private var searchResults: [MKMapItem] = []
    
    init(favorite: FavoriteLocation) {
        self.originalFavorite = favorite
        _name = State(initialValue: favorite.name)
        _selectedType = State(initialValue: favorite.type)
        _coordinate = State(initialValue: favorite.coordinate)
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
                
                Section(header: Text("Endre lokasjon"), footer: Text("Søk for å oppdatere posisjonen til favoritten.")) {
                    TextField("Søk etter ny adresse/sted", text: $searchQuery)
                        .onChange(of: searchQuery) { _, newValue in
                            performSearch(query: newValue)
                        }
                    
                    if !searchResults.isEmpty {
                        ForEach(searchResults, id: \.self) { item in
                            Button {
                                if let newCoord = item.placemark.location?.coordinate {
                                    coordinate = newCoord
                                    if name == originalFavorite.name || name.isEmpty {
                                        name = item.name ?? name
                                    }
                                    searchQuery = ""
                                    searchResults = []
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name ?? "Ukjent sted")
                                        .foregroundColor(.primary)
                                    Text(item.placemark.title ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                if coordinate.latitude != originalFavorite.latitude || coordinate.longitude != originalFavorite.longitude {
                    Section {
                        Text("Lokasjon er oppdatert! Husk å lagre.")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Rediger favoritt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Avbryt") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lagre") {
                        saveChanges()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveChanges() {
        var updated = originalFavorite
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.type = selectedType
        updated.latitude = coordinate.latitude
        updated.longitude = coordinate.longitude
        
        favoritesManager.update(updated)
        dismiss()
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response else { return }
            self.searchResults = Array(response.mapItems.prefix(5))
        }
    }
}
