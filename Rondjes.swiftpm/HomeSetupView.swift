import SwiftUI
import MapKit

struct HomeSetupView: View {
    @EnvironmentObject private var store: LoopStore
    var onDone: (() -> Void)? = nil

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isLocating = false
    @State private var errorText: String?
    @State private var locationProvider = LocationProvider()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Waar begin je?")
                        .font(.title2.bold())
                    Text("Elk rondje start en eindigt bij je huis. De app maakt 81 looproutes van 3 tot 43 km, steeds een halve kilometer langer.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    HStack {
                        Label("Gebruik mijn huidige locatie", systemImage: "location.fill")
                        if isLocating { Spacer(); ProgressView() }
                    }
                }
                .disabled(isLocating)
            }

            Section("Of zoek je adres") {
                TextField("Straat en huisnummer, plaats", text: $query)
                    .textContentType(.fullStreetAddress)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                ForEach(results, id: \.self) { item in
                    Button {
                        store.setHome(item.placemark.coordinate, name: item.placemark.title ?? item.name)
                        onDone?()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Onbekend").foregroundStyle(.primary)
                            if let title = item.placemark.title {
                                Text(title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let current = store.homeName ?? store.home.map({ String(format: "%.5f, %.5f", $0.latitude, $0.longitude) }) {
                Section {
                    Text(current)
                } header: {
                    Text("Huidig thuisadres")
                } footer: {
                    Text("Een nieuw thuisadres wist de bestaande routes. Je gelopen rondjes blijven bewaard.")
                }
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Thuisadres")
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { onDone() }
                }
            }
        }
    }

    private func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        errorText = nil
        do {
            let coordinate = try await locationProvider.currentLocation()
            var name: String?
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                name = [placemark.thoroughfare, placemark.subThoroughfare, placemark.locality]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            store.setHome(coordinate, name: name)
            onDone?()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorText = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        do {
            results = try await MKLocalSearch(request: request).start().mapItems
            if results.isEmpty { errorText = "Geen adres gevonden." }
        } catch {
            errorText = "Zoeken mislukt: \(error.localizedDescription)"
        }
    }
}
