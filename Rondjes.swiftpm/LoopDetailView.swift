import SwiftUI
import MapKit

struct LoopDetailView: View {
    @EnvironmentObject private var store: LoopStore
    let step: Int
    @State private var position: MapCameraPosition = .automatic

    private var loop: RunLoop? { store.loops[step] }
    private var isGenerating: Bool { store.generating.contains(step) }

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(maxHeight: .infinity)

            VStack(spacing: 12) {
                stats

                if isGenerating {
                    HStack {
                        ProgressView()
                        Text(store.statusText[step] ?? "Route maken…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Button {
                        Task {
                            await store.generate(step: step, randomDirection: loop != nil)
                            position = .automatic
                        }
                    } label: {
                        Label(loop == nil ? "Maak route" : "Andere route", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                HStack {
                    Button {
                        store.toggleCompleted(step)
                    } label: {
                        Label(store.isCompleted(step) ? "Gelopen ✓" : "Markeer als gelopen",
                              systemImage: store.isCompleted(step) ? "checkmark.circle.fill" : "figure.run")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.isCompleted(step) ? Color.green : Color.accentColor)
                    .controlSize(.large)

                    if loop != nil, let url = store.gpxFile(for: step) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .frame(minHeight: 22)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityLabel("Exporteer GPX")
                    }
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Rondje \(Distances.label(step))")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Generate automatically the first time this distance is opened.
            if loop == nil { await store.generate(step: step) ; position = .automatic }
        }
    }

    private var map: some View {
        Map(position: $position) {
            if let home = store.home {
                Annotation("Thuis", coordinate: home.clCoordinate) {
                    Image(systemName: "house.fill")
                        .padding(6)
                        .background(Circle().fill(.orange))
                        .foregroundStyle(.white)
                }
            }
            if let loop {
                MapPolyline(coordinates: loop.coordinates.map(\.clCoordinate))
                    .stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }

    private var stats: some View {
        HStack {
            stat(title: "Doel", value: Distances.label(step))
            Divider().frame(height: 32)
            stat(title: "Route", value: loop.map { Distances.format(km: $0.actualKm, digits: 2) } ?? "–")
            Divider().frame(height: 32)
            stat(title: "Verschil", value: loop.map { diffText($0) } ?? "–")
        }
    }

    private func stat(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private func diffText(_ loop: RunLoop) -> String {
        let meters = Int((loop.actualMeters - loop.targetKm * 1000).rounded())
        return (meters >= 0 ? "+" : "−") + "\(abs(meters)) m"
    }
}
