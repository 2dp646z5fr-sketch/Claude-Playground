import SwiftUI
import MapKit

struct HomeSetupView: View {
    @EnvironmentObject private var store: LoopStore
    var onDone: (() -> Void)? = nil

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isLocating = false
    @State private var message: String?
    @State private var locationProvider = LocationProvider()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LogoMark().frame(width: 44, height: 44)
                    Spacer()
                    if let onDone, store.home != nil {
                        Button("Annuleer", action: onDone).foregroundStyle(Theme.muted)
                    }
                }
                Text("Waar begin je?").font(Theme.display(32, .heavy))
                Text("Elk rondje start en eindigt bij je voordeur. Rondjes kiezen zoveel mogelijk paden door bos, polder en langs water.")
                    .foregroundStyle(Theme.muted)

                Button { Task { await useCurrentLocation() } } label: {
                    HStack {
                        Label("Gebruik mijn huidige locatie", systemImage: "location.fill")
                        if isLocating { ProgressView().tint(Theme.pineInk) }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isLocating)

                Text("OF ZOEK JE ADRES")
                    .font(.system(size: 12, weight: .semibold)).tracking(1)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    TextField("Straat 12, Plaats", text: $query)
                        .textContentType(.fullStreetAddress)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                    Button("Zoek") { Task { await search() } }
                        .buttonStyle(SecondaryButtonStyle())
                }

                ForEach(results, id: \.self) { item in
                    Button {
                        store.setHome(item.placemark.coordinate, name: item.name ?? "Thuis")
                        onDone?()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Onbekend").foregroundStyle(Theme.ink)
                            if let title = item.placemark.title {
                                Text(title).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .card(radius: 12)
                    }
                }

                if let message {
                    Text(message).font(.footnote).foregroundStyle(Theme.danger)
                }

                Text("Een nieuw thuisadres wist de bestaande routes. Je afgevinkte rondjes blijven bewaard.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        message = nil
        do {
            let c = try await locationProvider.currentLocation()
            var name = "Huidige locatie"
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
            if let p = placemark {
                let street = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                if !street.isEmpty { name = street }
            }
            store.setHome(c, name: name)
            onDone?()
        } catch {
            message = error.localizedDescription
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        message = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.address, .pointOfInterest]
        do {
            results = try await MKLocalSearch(request: request).start().mapItems
            if results.isEmpty { message = "Geen adres gevonden. Probeer straat, huisnummer en plaats." }
        } catch {
            message = "Zoeken mislukt. Controleer je internetverbinding."
        }
    }
}
