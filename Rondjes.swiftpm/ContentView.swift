import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LoopStore
    @State private var showHomeSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if store.home == nil {
                    HomeSetupView()
                } else {
                    LoopListView(showHomeSetup: $showHomeSetup)
                }
            }
            .navigationDestination(for: Int.self) { step in
                LoopDetailView(step: step)
            }
        }
        .sheet(isPresented: $showHomeSetup) {
            NavigationStack { HomeSetupView(onDone: { showHomeSetup = false }) }
        }
        .alert("Er ging iets mis",
               isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct LoopListView: View {
    @EnvironmentObject private var store: LoopStore
    @Binding var showHomeSetup: Bool

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(store.completedCount) van \(Distances.steps.count) gelopen")
                            .font(.headline)
                        Spacer()
                        Text(Distances.format(km: completedKm, digits: 1))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(store.completedCount),
                                 total: Double(Distances.steps.count))
                }
                .padding(.vertical, 4)

                if let next = store.nextStep {
                    NavigationLink(value: next) {
                        Label("Volgende rondje: \(Distances.label(next))", systemImage: "figure.run")
                            .font(.headline)
                    }
                } else {
                    Label("Alle rondjes gelopen! 🎉", systemImage: "trophy.fill")
                }

                if store.isGeneratingAll {
                    Button(role: .destructive) { store.cancelAll() } label: {
                        Label("Stop met genereren (\(store.loops.count)/\(Distances.steps.count))",
                              systemImage: "stop.circle")
                    }
                } else if store.loops.count < Distances.steps.count {
                    Button { store.generateAllMissing() } label: {
                        Label("Genereer alle ontbrekende routes", systemImage: "wand.and.stars")
                    }
                }
            } footer: {
                if store.isGeneratingAll {
                    Text("Apple Kaarten beperkt het aantal routeverzoeken per minuut; alle 81 routes maken kan een tijdje duren. Laat de app open staan.")
                }
            }

            Section("Rondjes (3 – 43 km)") {
                ForEach(Distances.steps, id: \.self) { step in
                    NavigationLink(value: step) { LoopRow(step: step) }
                }
            }
        }
        .navigationTitle("Rondjes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHomeSetup = true } label: {
                    Label("Thuisadres", systemImage: "house")
                }
            }
        }
    }

    private var completedKm: Double {
        store.completed.keys.reduce(0) { total, step in
            total + (store.loops[step]?.actualKm ?? Distances.km(step))
        }
    }
}

struct LoopRow: View {
    @EnvironmentObject private var store: LoopStore
    let step: Int

    var body: some View {
        HStack {
            Image(systemName: store.isCompleted(step) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(store.isCompleted(step) ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(Distances.label(step)).font(.body.monospacedDigit().weight(.semibold))
                Group {
                    if store.generating.contains(step) {
                        Text(store.statusText[step] ?? "Route maken…")
                    } else if let loop = store.loops[step] {
                        Text("Route: \(Distances.format(km: loop.actualKm, digits: 2))")
                    } else {
                        Text("Nog geen route")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.generating.contains(step) {
                ProgressView()
            } else if let date = store.completed[step] {
                Text(date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
