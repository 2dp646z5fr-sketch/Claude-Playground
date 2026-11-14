import SwiftUI
import Charts

struct RouteCard: View {
    @EnvironmentObject private var store: LoopStore

    var body: some View {
        let m = store.selected
        let loop = store.selectedLoop
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: store.homeName.isEmpty ? "Rondje vanaf huis" : "Rondje vanaf \(store.homeName)")
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(m.map { Fmt.km($0) } ?? "–")
                        .font(Theme.display(64, .heavy))
                        .monospacedDigit()
                        .tracking(-2)
                    Text("km").font(Theme.display(26, .bold)).foregroundStyle(Theme.muted)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                if let m, let date = store.done[m] {
                    Tag(text: "Gelopen \(date.formatted(.dateTime.day().month(.abbreviated).locale(Fmt.nl)))", color: Theme.pine, background: Theme.mossSoft)
                }
                if let m, store.isCustom(m) {
                    Tag(text: "Eigen afstand", color: Theme.sun, background: Theme.sun.opacity(0.15))
                }
            }
            .padding(.top, 2)

            NatureBar(green: loop?.green, urban: loop?.urban)
                .padding(.top, 16)

            HStack(spacing: 10) {
                Stat(title: "Route",
                     value: loop.map { Fmt.number(Double($0.meters) / 1000, digits: 2) } ?? "–", unit: loop == nil ? nil : "km",
                     sub: loop.map { l in let d = l.meters - l.target; return abs(d) < 1 ? "precies" : "\(d > 0 ? "+" : "−")\(abs(d)) m" } ?? " ")
                Stat(title: "Looptijd",
                     value: loop.map { Fmt.duration(minutes: Double($0.meters) / 1000 * store.pace) } ?? "–", unit: nil,
                     sub: "bij \(Fmt.pace(store.pace))/km")
                Stat(title: "Klimmen",
                     value: loop?.ascend.map { "\(Int($0.rounded()))" } ?? "–", unit: loop?.ascend == nil ? nil : "m",
                     sub: loop?.elevations.map { "\(Int($0.min() ?? 0))–\(Int($0.max() ?? 0)) m hoog" } ?? " ")
            }
            .padding(.top, 16)

            if let e = loop?.elevations, e.count > 1 {
                ElevationChart(values: e).frame(height: 54).padding(.top, 12)
            }

            statusLine(m).padding(.top, 12)

            if let m {
                HStack(spacing: 8) {
                    let done = store.done[m] != nil
                    Button { withAnimation { store.toggleDone(m) } } label: {
                        Label(done ? "Gelopen" : "Afvinken", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle(background: done ? Theme.moss : Theme.pine, foreground: done ? .white : Theme.pineInk))

                    Button { store.generate(m, another: loop != nil) } label: {
                        Label(loop == nil ? "Maak" : "Andere", systemImage: "shuffle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(store.busy.contains(m) || store.home == nil)

                    if loop != nil, let url = store.gpxFile(for: m) {
                        ShareLink(item: url) { Label("GPX", systemImage: "square.and.arrow.up") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.top, 12)

                if store.isCustom(m) && store.custom.contains(m) {
                    Button("Verwijder deze afstand uit mijn lijst") { store.removeCustom(m) }
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 10)
                }
            }
        }
        .padding(18)
        .card()
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
    }

    @ViewBuilder
    private func statusLine(_ m: Int?) -> some View {
        if let m, store.busy.contains(m) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(store.status[m] ?? "Route zoeken…")
            }
            .font(.footnote).foregroundStyle(Theme.muted)
        } else if let m, let note = store.notice[m] {
            Text(note).font(.footnote).foregroundStyle(Theme.muted)
        }
    }
}

struct Tag: View {
    let text: String
    let color: Color
    let background: Color
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(background))
            .fixedSize()
    }
}

struct NatureBar: View {
    let green: Double?
    let urban: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let g = green ?? 0, u = urban ?? 0
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.moss).frame(width: geo.size.width * g)
                    Rectangle().fill(Theme.urban.opacity(0.35)).frame(width: geo.size.width * max(0, 1 - g - u))
                    Rectangle().fill(Theme.urban).frame(width: geo.size.width * u)
                }
                .opacity(green == nil ? 0 : 1)
                .animation(.easeOut(duration: 0.6), value: g)
            }
            .frame(height: 10)
            .background(Theme.surface2)
            .clipShape(Capsule())

            HStack(spacing: 14) {
                legend(color: Theme.moss, value: green, label: "natuur & groen")
                legend(color: Theme.urban, value: urban, label: "bebouwd")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
    }

    private func legend(color: Color, value: Double?, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–").fontWeight(.semibold).foregroundStyle(Theme.ink)
            Text(label)
        }
    }
}

struct Stat: View {
    let title: String
    let value: String
    let unit: String?
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: title).font(.system(size: 10))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(Theme.display(20, .bold)).monospacedDigit()
                if let unit { Text(unit).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(sub).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
    }
}

struct ElevationPoint: Identifiable {
    let index: Int
    let meters: Double
    var id: Int { index }
}

struct ElevationChart: View {
    let values: [Double]

    var body: some View {
        // smooth a little, and keep at least 25 m of vertical range so flat land looks flat
        let smooth = values.indices.map { i -> Double in
            let w = values[max(0, i - 2)...min(values.count - 1, i + 2)]
            return w.reduce(0, +) / Double(w.count)
        }
        let lo = smooth.min() ?? 0, hi = max(smooth.max() ?? 0, lo + 25)
        let points = smooth.enumerated().map { ElevationPoint(index: $0.offset, meters: $0.element) }
        Chart(points) { p in
            AreaMark(x: .value("km", p.index), yStart: .value("min", lo), yEnd: .value("m", p.meters))
                .foregroundStyle(LinearGradient(colors: [Theme.sun.opacity(0.35), Theme.sun.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("km", p.index), y: .value("m", p.meters))
                .foregroundStyle(Theme.sun)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
        }
        .chartYScale(domain: lo...hi)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel("Hoogteprofiel")
    }
}
