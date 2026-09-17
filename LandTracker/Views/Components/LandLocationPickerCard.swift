import SwiftUI
import MapKit

struct LandLocationPickerCard: View {
    @Binding var latitude: Double
    @Binding var longitude: Double
    let language: AppLanguage

    @State private var position: MapCameraPosition
    @State private var searchText: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchError: String?

    init(latitude: Binding<Double>, longitude: Binding<Double>, language: AppLanguage) {
        _latitude = latitude
        _longitude = longitude
        self.language = language

        let hasLocation = latitude.wrappedValue != 0 || longitude.wrappedValue != 0
        _position = State(initialValue: .region(
            MKCoordinateRegion(
                center: hasLocation
                    ? CLLocationCoordinate2D(latitude: latitude.wrappedValue, longitude: longitude.wrappedValue)
                    : Self.defaultCenter,
                span: hasLocation
                    ? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    : MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
            )
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hasConfirmedLocation {
                Label(
                    language.localized(
                        "Location not set — search an address or tap the map to place a pin.",
                        "Ubicación sin confirmar — busca una dirección o toca el mapa para fijar un punto."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                TextField(
                    language.localized("Search address or place", "Buscar dirección o lugar"),
                    text: $searchText
                )
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onSubmit { Task { await search() } }

                Button {
                    Task { await search() }
                } label: {
                    if isSearching {
                        ProgressView()
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }

            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(searchResults.prefix(5).enumerated()), id: \.offset) { _, item in
                        Button {
                            select(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? language.localized("Unnamed place", "Lugar sin nombre"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                if let addressLine = item.address?.fullAddress {
                                    Text(addressLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            MapReader { proxy in
                Map(position: $position) {
                    if hasConfirmedLocation {
                        Marker(
                            language.localized("Land", "Terreno"),
                            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                        )
                        .tint(.blue)
                    }
                }
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        setCoordinate(coordinate)
                    }
                )
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )

            Text(language.localized("Tap the map to place or move the pin.", "Toca el mapa para colocar o mover el pin."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var hasConfirmedLocation: Bool {
        latitude != 0 || longitude != 0
    }

    private func setCoordinate(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        withAnimation {
            position = .region(
                MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
            )
        }
    }

    private func select(_ item: MKMapItem) {
        searchResults = []
        searchText = item.name ?? searchText
        setCoordinate(item.location.coordinate)
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if hasConfirmedLocation {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
            )
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems

            if searchResults.isEmpty {
                searchError = language.localized("No results found.", "No se encontraron resultados.")
            } else if searchResults.count == 1, let onlyResult = searchResults.first {
                select(onlyResult)
            }
        } catch {
            searchError = language.localized("Search failed. Try again.", "Falló la búsqueda. Inténtalo de nuevo.")
        }
    }

    private static var defaultCenter: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 40.0, longitude: -3.7)
    }
}
