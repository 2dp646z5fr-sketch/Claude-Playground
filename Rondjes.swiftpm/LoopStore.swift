import Foundation
import CoreLocation
import SwiftUI

@MainActor
final class LoopStore: ObservableObject {
    private struct Saved: Codable {
        var home: Coordinate?
        var homeName: String
        var series: Series
        var pace: Double
        var custom: [Int]
        var loops: [RunLoop]
        var done: [Int: Date]
        var selected: Int?
        var factor: Double
    }

    // persisted
    @Published private(set) var home: Coordinate?
    @Published private(set) var homeName = ""
    @Published private(set) var series = Series()
    @Published private(set) var pace = 6.0               // minutes per km
    @Published private(set) var custom: [Int] = []       // extra distances in metres
    @Published private(set) var loops: [Int: RunLoop] = [:]
    @Published private(set) var done: [Int: Date] = [:]
    @Published private(set) var selected: Int?
    private var factor = 1.35

    // runtime
    @Published private(set) var busy: Set<Int> = []
    @Published private(set) var status: [Int: String] = [:]
    @Published private(set) var notice: [Int: String] = [:]
    @Published private(set) var isBatchRunning = false
    @Published var errorMessage: String?

    private var batchTask: Task<Void, Never>?
    private var tasks: [Int: Task<Void, Never>] = [:]

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("rondjes-v2.json")
    }

    init() {
        load()
        if selected == nil || !allDistances.contains(selected!) { selected = nextDistance ?? series.distances.first }
    }

    // MARK: - Distances

    var allDistances: [Int] { Array(Set(series.distances + custom)).sorted() }
    func isCustom(_ m: Int) -> Bool { !series.distances.contains(m) }
    var nextDistance: Int? { series.distances.first { done[$0] == nil } }
    var completedInSeries: Int { series.distances.filter { done[$0] != nil }.count }
    var completedKm: Double { done.keys.reduce(0) { $0 + Double(loops[$1]?.meters ?? $1) } / 1000 }
    var generatedInSeries: Int { series.distances.filter { loops[$0] != nil }.count }
    var selectedLoop: RunLoop? { selected.flatMap { loops[$0] } }

    func select(_ m: Int) {
        selected = m
        save()
        if loops[m] == nil { generate(m) }
    }

    /// Adds a typed distance (km). Returns the key in metres, or nil when out of range.
    @discardableResult
    func pick(km: Double) -> Int? {
        guard km >= 1, km <= 60 else { return nil }
        let m = Int((km * 100).rounded()) * 10            // round to 10 m
        if !allDistances.contains(m) { custom.append(m) }
        select(m)
        return m
    }

    func removeCustom(_ m: Int) {
        custom.removeAll { $0 == m }
        loops[m] = nil
        done[m] = nil
        selected = nextDistance ?? series.distances.first
        save()
    }

    func toggleDone(_ m: Int) {
        done[m] = done[m] == nil ? Date() : nil
        save()
    }

    func update(series newSeries: Series, pace newPace: Double) {
        series = newSeries
        pace = newPace
        if let s = selected, !allDistances.contains(s) { selected = nextDistance ?? series.distances.first }
        save()
    }

    // MARK: - Home

    func setHome(_ c: CLLocationCoordinate2D, name: String) {
        let changed = home.map { abs($0.latitude - c.latitude) > 1e-5 || abs($0.longitude - c.longitude) > 1e-5 } ?? true
        home = Coordinate(c)
        homeName = name
        if changed {
            cancelBatch()
            tasks.values.forEach { $0.cancel() }
            tasks = [:]
            busy = []
            loops = [:]
        }
        selected = nextDistance ?? series.distances.first
        save()
        if let s = selected, loops[s] == nil { generate(s) }
    }

    // MARK: - Generation

    func generate(_ m: Int, another: Bool = false) {
        guard home != nil, !busy.contains(m) else { return }
        tasks[m] = Task { await run(m, another: another) }
    }

    private func run(_ m: Int, another: Bool) async {
        guard let home, !busy.contains(m) else { return }
        busy.insert(m)
        notice[m] = nil
        defer {
            busy.remove(m)
            status[m] = nil
            tasks[m] = nil
        }
        let previous = loops[m]
        let base = another ? Double.random(in: 0..<360) : (Double(m) / 500 * 137.508).truncatingRemainder(dividingBy: 360)
        let homeAtStart = home
        do {
            let (r, newFactor) = try await LoopGenerator.make(
                home: home.cl, target: Double(m), baseBearing: base,
                avoidBearing: another ? previous?.bearing : nil, factor: factor,
                progress: { [weak self] text in self?.status[m] = text })
            guard self.home == homeAtStart else { return }
            factor = newFactor
            loops[m] = RunLoop(target: m, meters: Int(r.meters.rounded()), polyline: Polyline.encode(r.coords),
                               elevations: LoopGenerator.sampleElevations(r), ascend: r.ascend,
                               green: r.green, urban: r.urban, bearing: r.bearing, router: r.router, generatedAt: Date())
            if r.router == "osrm" { notice[m] = "De natuurplanner was even niet bereikbaar; dit is een gewone looproute." }
            save()
        } catch is CancellationError {
        } catch {
            if m == selected { errorMessage = "\(Fmt.km(m)) km: \(error.localizedDescription) Probeer ‘Andere’." }
        }
    }

    func startBatch() {
        guard batchTask == nil, home != nil else { return }
        isBatchRunning = true
        batchTask = Task { [weak self] in
            guard let self else { return }
            for m in self.series.distances {
                if Task.isCancelled { break }
                if self.loops[m] == nil && !self.busy.contains(m) { await self.run(m, another: false) }
            }
            self.isBatchRunning = false
            self.batchTask = nil
        }
    }

    func cancelBatch() {
        batchTask?.cancel()
        batchTask = nil
        isBatchRunning = false
    }

    // MARK: - GPX

    func gpxFile(for m: Int) -> URL? {
        guard let loop = loops[m] else { return nil }
        let name = "Rondje \(Fmt.km(m)) km"
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Rondjes" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(name)</name><trkseg>

        """
        for c in loop.coordinates { gpx += "<trkpt lat=\"\(c.latitude)\" lon=\"\(c.longitude)\"/>\n" }
        gpx += "</trkseg></trk>\n</gpx>\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rondje-\(String(format: "%.1f", Double(m) / 1000))km.gpx")
        do { try gpx.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        home = s.home; homeName = s.homeName; series = s.series; pace = s.pace; custom = s.custom
        loops = Dictionary(uniqueKeysWithValues: s.loops.map { ($0.target, $0) })
        done = s.done; selected = s.selected; factor = s.factor
    }

    private func save() {
        let s = Saved(home: home, homeName: homeName, series: series, pace: pace, custom: custom,
                      loops: loops.values.sorted { $0.target < $1.target }, done: done,
                      selected: selected, factor: factor)
        do { try JSONEncoder().encode(s).write(to: fileURL, options: .atomic) }
        catch { errorMessage = "Opslaan mislukt: \(error.localizedDescription)" }
    }
}
