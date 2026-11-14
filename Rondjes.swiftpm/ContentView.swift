import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject private var store: LoopStore
    @State private var showHome = false
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        MapHero()
                            .frame(height: 460)
                            .id("top")
                        VStack(spacing: 30) {
                            RouteCard()
                                .padding(.top, -64)
                            DistancePicker { withAnimation { proxy.scrollTo("top", anchor: .top) } }
                            ProgressCard { withAnimation { proxy.scrollTo("top", anchor: .top) } }
                            DistanceGrid { m in
                                store.select(m)
                                withAnimation { proxy.scrollTo("top", anchor: .top) }
                            }
                            footer
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: 680)
                    }
                    .frame(maxWidth: .infinity)
                }
                .ignoresSafeArea(edges: .top)
                .scrollDismissesKeyboard(.interactively)
            }
            TopBar(showHome: $showHome, showSettings: $showSettings)
        }
        .sheet(isPresented: $showHome) { HomeSetupView { showHome = false } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: Binding(get: { store.home == nil }, set: { _ in })) {
            HomeSetupView(onDone: nil).interactiveDismissDisabled()
        }
        .alert("Er ging iets mis",
               isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .tint(Theme.pine)
    }

    private var footer: some View {
        Text("Kaartgegevens © OpenStreetMap-bijdragers. Routes via BRouter met een eigen natuurprofiel (paden, bos en water voorrang; drukke en bebouwde wegen vermeden). Alles wordt alleen op dit toestel bewaard.")
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .padding(.bottom, 32)
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject private var store: LoopStore
    @Binding var showHome: Bool
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                LogoMark().frame(width: 30, height: 30)
                Text("Rondjes").font(Theme.display(20, .heavy))
            }
            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Button { showHome = true } label: {
                Label(store.home == nil ? "Thuis instellen" : (store.homeName.isEmpty ? "Thuis" : store.homeName), systemImage: "house")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Instellingen")
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

struct LogoMark: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.pine)
            Circle()
                .trim(from: 0.0, to: 0.72)
                .stroke(Theme.pineInk, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .rotationEffect(.degrees(90))
                .padding(7)
            Circle().fill(Theme.sun).frame(width: 7, height: 7).offset(y: 9)
        }
    }
}

// MARK: - Map

struct MapHero: View {
    @EnvironmentObject private var store: LoopStore
    @State private var position: MapCameraPosition = .automatic
    @AppStorage("terrainMap") private var terrain = false

    var body: some View {
        let coords = store.selectedLoop?.coordinates ?? []
        ZStack(alignment: .bottomTrailing) {
            Map(position: $position) {
                if !coords.isEmpty {
                    MapPolyline(coordinates: coords)
                        .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.sun, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let home = store.home {
                    Annotation("Thuis", coordinate: home.cl, anchor: .center) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.pineInk)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.pine))
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                }
            }
            .mapStyle(terrain ? .hybrid(elevation: .realistic) : .standard(pointsOfInterest: .excludingAll))
            .onAppear(perform: recenter)
            .onChange(of: store.selected) { recenter() }
            .onChange(of: store.selectedLoop?.generatedAt) { recenter() }
            .onChange(of: store.home) { recenter() }

            HStack(spacing: 2) {
                styleButton("Kaart", active: !terrain) { terrain = false }
                styleButton("Satelliet", active: terrain) { terrain = true }
            }
            .padding(3)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.trailing, 16)
            .padding(.bottom, 76)
        }
    }

    private func styleButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(active ? Theme.pineInk : Theme.muted)
                .background(Capsule().fill(active ? Theme.pine : .clear))
        }
    }

    private func recenter() {
        if let loop = store.selectedLoop {
            let coords = loop.coordinates
            let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
            if let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() {
                let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
                // extra room at the bottom for the card that overlaps the map
                let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.7 + 0.004, longitudeDelta: (maxLon - minLon) * 1.3 + 0.004)
                let shifted = CLLocationCoordinate2D(latitude: center.latitude - span.latitudeDelta * 0.12, longitude: center.longitude)
                withAnimation(.easeInOut(duration: 0.6)) { position = .region(MKCoordinateRegion(center: shifted, span: span)) }
                return
            }
        }
        if let home = store.home {
            withAnimation { position = .region(MKCoordinateRegion(center: home.cl, latitudinalMeters: 3000, longitudinalMeters: 3000)) }
        }
    }
}
