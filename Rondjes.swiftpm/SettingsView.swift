import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LoopStore
    @Environment(\.dismiss) private var dismiss

    @State private var from = ""
    @State private var to = ""
    @State private var step = ""
    @State private var pace = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Instellingen").font(Theme.display(32, .heavy))
                Text("Stel je reeks rondjes in. Gelopen rondjes en eigen afstanden blijven bewaard.")
                    .foregroundStyle(Theme.muted)

                HStack(spacing: 8) {
                    field("Van (km)", $from)
                    field("Tot (km)", $to)
                    field("Stap (km)", $step)
                }
                Divider().padding(.vertical, 4)
                field("Jouw tempo (min per km), voor de geschatte tijd", $pace, placeholder: "6:00")

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }

                HStack(spacing: 8) {
                    Button("Annuleer") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                    Button("Bewaar", action: saveSettings).buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear {
            from = Fmt.number(store.series.from)
            to = Fmt.number(store.series.to)
            step = Fmt.number(store.series.step)
            pace = Fmt.pace(store.pace)
        }
    }

    private func field(_ label: String, _ text: Binding<String>, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: text)
                .keyboardType(.numbersAndPunctuation)
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }
    }

    private func saveSettings() {
        guard let f = Fmt.parse(from), let t = Fmt.parse(to), let s = Fmt.parse(step), f >= 1, t <= 60, f < t else {
            error = "Kies ‘van’ en ‘tot’ tussen 1 en 60 km, met ‘van’ kleiner dan ‘tot’."
            return
        }
        guard s >= 0.1, (t - f) / s <= 200 else {
            error = "Kies een stap van minstens 0,1 km en hooguit 200 rondjes."
            return
        }
        guard let p = Fmt.parsePace(pace), p >= 2.5, p <= 15 else {
            error = "Vul je tempo in als minuten per km, bijvoorbeeld 5:30."
            return
        }
        store.update(series: Series(from: f, to: t, step: s), pace: p)
        dismiss()
    }
}
