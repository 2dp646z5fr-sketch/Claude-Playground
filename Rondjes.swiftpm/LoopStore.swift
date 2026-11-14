import Foundation
import CoreLocation

@MainActor
final class LoopStore: ObservableObject {
    private struct SavedState: Codable {
        var home: Coordinate?
        var homeName: String?
        var loops: [RunLoop]
        var completed: [Int: Date]
    }

    @Published private(set) var home: Coordinate?
    @Published private(set) var homeName: String?
    @Published private(set) var loops: [Int: RunLoop] = [:]
    /// Date each distance was run (key = step).
    @Published private(set) var completed: [Int: Date] = [:]

    @Published private(set) var generating: Set<Int> = []
    @Published private(set) var statusText: [Int: String] = [:]
    @Published private(set) var isGeneratingAll = false
    @Published var errorMessage: String?

    private var batchTask: Task<Void, Never>?
    private let generator = LoopGenerator()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rondjes.json")
    }

    init() { load() }

    // MARK: - Home

    func setHome(_ coordinate: CLLocationCoordinate2D, name: String?) {
        cancelAll()
        home = Coordinate(coordinate)
        homeName = name
        loops = [:]          // routes depend on home; completed runs are kept
        save()
    }

    // MARK: - Progress

    var completedCount: Int { completed.count }

    /// Shortest distance that has not been run yet.
    var nextStep: Int? { Distances.steps.first { completed[$0] == nil } }

    func isCompleted(_ step: Int) -> Bool { completed[step] != nil }

    func toggleCompleted(_ step: Int) {
        if completed[step] == nil { completed[step] = Date() } else { completed[step] = nil }
        save()
    }

    // MARK: - Generation

    func generate(step: Int, randomDirection: Bool = false) async {
        guard let home, !generating.contains(step) else { return }
        generating.insert(step)
        defer {
            generating.remove(step)
            statusText[step] = nil
        }

        // Golden-angle spread gives every distance its own direction by default.
        let bearing = randomDirection ? Double.random(in: 0..<360)
                                      : (Double(step) * 137.508).truncatingRemainder(dividingBy: 360)
        do {
            let result = try await generator.generate(
                home: home.clCoordinate,
                targetMeters: Distances.km(step) * 1000,
                bearing: bearing,
                progress: { [weak self] text in self?.statusText[step] = text }
            )
            loops[step] = RunLoop(step: step,
                                  actualMeters: result.meters,
                                  coordinates: result.coordinates.map(Coordinate.init),
                                  generatedAt: Date())
            save()
        } catch is CancellationError {
            // stopped by user
        } catch {
            errorMessage = "\(Distances.label(step)): \(error.localizedDescription)"
        }
    }

    func generateAllMissing() {
        guard batchTask == nil else { return }
        isGeneratingAll = true
        batchTask = Task { [weak self] in
            for step in Distances.steps {
                guard let self, !Task.isCancelled else { break }
                if self.loops[step] == nil {
                    await self.generate(step: step)
                }
            }
            self?.isGeneratingAll = false
            self?.batchTask = nil
        }
    }

    func cancelAll() {
        batchTask?.cancel()
        batchTask = nil
        isGeneratingAll = false
    }

    // MARK: - GPX

    func gpxFile(for step: Int) -> URL? {
        guard let loop = loops[step] else { return nil }
        let name = "Rondje \(Distances.label(step))"
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Rondjes" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>\(name)</name><trkseg>

        """
        for c in loop.coordinates {
            gpx += "      <trkpt lat=\"\(c.latitude)\" lon=\"\(c.longitude)\"/>\n"
        }
        gpx += "    </trkseg></trk>\n</gpx>\n"

        let fileName = "rondje-\(String(format: "%.1f", Distances.km(step)))km.gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try gpx.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        home = state.home
        homeName = state.homeName
        loops = Dictionary(uniqueKeysWithValues: state.loops.map { ($0.step, $0) })
        completed = state.completed
    }

    private func save() {
        let state = SavedState(home: home,
                               homeName: homeName,
                               loops: loops.values.sorted { $0.step < $1.step },
                               completed: completed)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "Opslaan mislukt: \(error.localizedDescription)"
        }
    }
}
