import SwiftUI

// MARK: - Distance picker

struct DistancePicker: View {
    @EnvironmentObject private var store: LoopStore
    var onPick: () -> Void
    @State private var text = "10,0"
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Kies je afstand", detail: "1 – 60 km")
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    stepButton("minus") { bump(-0.5) }
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        TextField("10,0", text: $text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(Theme.display(34, .heavy))
                            .monospacedDigit()
                            .focused($focused)
                            .frame(maxWidth: 140)
                        Text("km").font(Theme.display(18, .bold)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    stepButton("plus") { bump(0.5) }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))

                Button(action: submit) { Label("Maak rondje", systemImage: "mappin.and.ellipse") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(14)
            .card(radius: 20)

            Text(error ?? "Typ een afstand of gebruik − en +. Afstanden buiten je reeks komen gestippeld in je lijst.")
                .font(.caption)
                .foregroundStyle(error == nil ? Theme.muted : Theme.danger)
        }
        .onAppear { if let s = store.selected { text = Fmt.km(s) } }
        .onChange(of: store.selected) { if let s = store.selected, !focused { text = Fmt.km(s) } }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .foregroundStyle(Theme.ink)
    }

    private func bump(_ delta: Double) {
        let v = Fmt.parse(text) ?? 10
        let next = min(60, max(1, ((v + delta) * 2).rounded() / 2))
        text = Fmt.number(next)
        error = nil
    }

    private func submit() {
        guard let v = Fmt.parse(text), v >= 1, v <= 60 else {
            error = "Vul een afstand in tussen 1 en 60 km, bijvoorbeeld 12,5."
            return
        }
        error = nil
        focused = false
        store.pick(km: v)
        onPick()
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.display(24, .bold))
            Spacer()
            if let detail { Text(detail).font(.footnote).foregroundStyle(Theme.muted) }
        }
    }
}

// MARK: - Progress

struct ProgressCard: View {
    @EnvironmentObject private var store: LoopStore
    var onNext: () -> Void

    var body: some View {
        let total = store.series.distances.count
        let n = store.completedInSeries
        let pct = total > 0 ? Double(n) / Double(total) : 0
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Theme.pineInk.opacity(0.2), lineWidth: 10)
                    Circle().trim(from: 0, to: pct)
                        .stroke(Theme.sun, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.8), value: pct)
                    Text("\(Int((pct * 100).rounded()))%").font(Theme.display(22, .heavy))
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(n) van \(total) rondjes").font(Theme.display(26, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(Fmt.number(store.completedKm)) km gelopen in totaal").font(.footnote).opacity(0.8)
                    if let next = store.nextDistance {
                        Button { store.select(next); onNext() } label: {
                            Text("Volgende: \(Fmt.km(next)) km →")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(Theme.pineInk))
                                .foregroundStyle(Theme.pine)
                        }
                        .padding(.top, 6)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.pineInk)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22).fill(Theme.pine))

            let made = store.generatedInSeries
            Button {
                store.isBatchRunning ? store.cancelBatch() : store.startBatch()
            } label: {
                Text(store.isBatchRunning ? "Stop met routes maken (\(made)/\(total))"
                     : made == total ? "Alle routes zijn klaar" : "Maak alle routes alvast (\(made)/\(total) klaar)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(store.home == nil || (!store.isBatchRunning && made == total))
        }
    }
}

// MARK: - Grid

struct DistanceGrid: View {
    @EnvironmentObject private var store: LoopStore
    var onSelect: (Int) -> Void

    struct Band: Identifiable {
        let id: Int            // 0 = up to 5 km, 1 = 5–10 km, …
        let distances: [Int]
    }

    private var bands: [Band] {
        Dictionary(grouping: store.allDistances) { $0 / 5000 }
            .sorted { $0.key < $1.key }
            .map { Band(id: $0.key, distances: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Alle rondjes",
                          detail: "\(Fmt.number(store.series.from)) – \(Fmt.number(store.series.to)) km per \(Fmt.number(store.series.step)) km")
            HStack(spacing: 14) {
                legend(Theme.surface, "te doen")
                legend(Theme.moss, "groen-aandeel")
                legend(Theme.pine, "gelopen")
            }
            .font(.caption).foregroundStyle(Theme.muted)

            ForEach(bands) { b in
                let band = b.id, distances = b.distances
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(band == 0 ? "TOT 5 KM" : "\(band * 5) – \(band * 5 + 5) KM")
                            .font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(Theme.muted)
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                        ForEach(distances, id: \.self) { m in
                            Chip(m: m) { onSelect(m) }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line))
            Text(text)
        }
    }
}

struct Chip: View {
    @EnvironmentObject private var store: LoopStore
    let m: Int
    var action: () -> Void

    var body: some View {
        let done = store.done[m] != nil
        let loop = store.loops[m]
        let busy = store.busy.contains(m)
        let selected = store.selected == m
        let custom = store.isCustom(m)
        Button(action: action) {
            VStack(spacing: 2) {
                Text(Fmt.km(m)).font(Theme.display(21, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(busy ? "bezig…" : "km").font(.system(size: 10))
                    .foregroundStyle(busy ? Theme.sun : (done ? Theme.pineInk.opacity(0.75) : Theme.muted))
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .foregroundStyle(done ? Theme.pineInk : Theme.ink)
            .background(RoundedRectangle(cornerRadius: 14).fill(done ? Theme.pine : Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(done ? Theme.pine : Theme.line, style: StrokeStyle(lineWidth: 1, dash: custom ? [4, 3] : []))
            )
            .overlay(alignment: .bottom) {
                if let g = loop?.green {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(done ? Theme.pineInk.opacity(0.2) : Theme.surface2)
                            Capsule().fill(Theme.moss).frame(width: geo.size.width * g)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Theme.sun))
                        .padding(6)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.sun, lineWidth: selected ? 3 : 0).padding(-2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Fmt.km(m)) kilometer\(done ? ", gelopen" : "")")
    }
}
