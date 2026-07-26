import SwiftUI

/// Admin sheet: ajustar popularity 0-100 de un track (trending manual).
struct AdminBoostSheet: View {
    let trackId: Int
    let trackTitle: String
    let currentPopularity: Int
    var onSaved: ((_ newValue: Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var value: Double
    @State private var sending = false
    @State private var errorMsg: String? = nil

    init(trackId: Int, trackTitle: String, currentPopularity: Int, onSaved: ((Int) -> Void)? = nil) {
        self.trackId = trackId; self.trackTitle = trackTitle
        self.currentPopularity = currentPopularity; self.onSaved = onSaved
        _value = State(initialValue: Double(currentPopularity))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Track") {
                    Text(trackTitle).font(.headline)
                    HStack { Text("Actual").foregroundStyle(.secondary); Spacer(); Text("\(currentPopularity)") }
                }
                Section("Nueva popularidad") {
                    VStack {
                        Slider(value: $value, in: 0...100, step: 1)
                        HStack {
                            Text("0").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(value))")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.tint)
                            Spacer()
                            Text("100").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("0") { value = 0 }
                        Spacer()
                        Button("50") { value = 50 }
                        Spacer()
                        Button("100 (max)") { value = 100 }
                    }
                    .buttonStyle(.bordered)
                }
                if let err = errorMsg { Section { Text(err).foregroundStyle(.red) } }
            }
            .navigationTitle("Boost trending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await send() } }
                        .disabled(sending || Int(value) == currentPopularity)
                }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func send() async {
        sending = true; errorMsg = nil
        do {
            let r = try await AdminService.shared.boostTrack(trackId: trackId, popularity: Int(value))
            onSaved?(r.popularity)
            dismiss()
        } catch { errorMsg = error.localizedDescription }
        sending = false
    }
}
