import SwiftUI
import AVFoundation

/// Admin sheet: buscar en YouTube + previsualizar audio + seleccionar id.
/// Callback devuelve el video ID elegido (para reemplazar YT de un track o
/// para import manual).
struct AdminYouTubeSearchSheet: View {
    var initialQuery: String = ""
    var onSelected: (_ videoId: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [AdminService.YTSearchResult] = []
    @State private var loading = false
    @State private var errorMsg: String? = nil
    @State private var previewingId: String? = nil
    @State private var previewPlayer: AVPlayer? = nil

    init(initialQuery: String = "", onSelected: @escaping (String) -> Void) {
        self.initialQuery = initialQuery; self.onSelected = onSelected
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("Buscar en YouTube", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await search() } }
                    Button("Buscar") { Task { await search() } }
                        .disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding()

                if loading {
                    ProgressView("Buscando…").padding()
                } else if let err = errorMsg {
                    Text(err).foregroundStyle(.red).padding()
                }

                List(results) { r in
                    HStack(spacing: 10) {
                        AsyncImage(url: URL(string: r.thumbnail ?? "")) { phase in
                            if case .success(let img) = phase { img.resizable().scaledToFill() }
                            else { Color.gray.opacity(0.2) }
                        }
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                            Text(r.uploader).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 8) {
                                if let d = r.duration {
                                    Text(fmtDur(d)).font(.caption2).foregroundStyle(.secondary)
                                }
                                if let v = r.view_count {
                                    Text("\(fmtViews(v)) views").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        VStack(spacing: 4) {
                            Button {
                                togglePreview(id: r.id)
                            } label: {
                                Image(systemName: previewingId == r.id ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 22)).foregroundStyle(.tint)
                            }.buttonStyle(.plain)
                            Button("Elegir") {
                                stopPreview()
                                onSelected(r.id)
                                dismiss()
                            }
                            .font(.caption).buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Buscar YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { stopPreview(); dismiss() }
                }
            }
            .task { if !query.isEmpty { await search() } }
            .onDisappear { stopPreview() }
        }
    }

    private func search() async {
        loading = true; errorMsg = nil
        do {
            results = try await AdminService.shared.youtubeSearch(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch { errorMsg = error.localizedDescription; results = [] }
        loading = false
    }

    private func togglePreview(id: String) {
        if previewingId == id {
            stopPreview()
        } else {
            stopPreview()
            let url = URL(string: "https://temazo.es/api/yt_proxy.php?id=\(id)")!
            let p = AVPlayer(url: url)
            p.play()
            previewPlayer = p
            previewingId = id
            // Auto-stop tras 15s
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if previewingId == id { stopPreview() }
            }
        }
    }
    private func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        previewingId = nil
    }

    private func fmtDur(_ s: Int) -> String {
        let m = s / 60, sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }
    private func fmtViews(_ v: Int) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v)/1_000_000) }
        if v >= 1_000 { return String(format: "%dK", v/1000) }
        return "\(v)"
    }
}
