import SwiftUI

/// Pantalla admin: queue de content reports.
/// Owner puede filtrar por status, resolver o dismissear.
struct AdminReportsQueueScreen: View {
    let onBack: () -> Void

    @State private var status: StatusFilter = .open
    @State private var entries: [AdminService.ReportEntry] = []
    @State private var loading = false
    @State private var errorMsg: String? = nil
    @State private var acting: Int? = nil

    enum StatusFilter: String, CaseIterable, Identifiable {
        case open, in_review, resolved, dismissed, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .open: return "Abiertos"
            case .in_review: return "En revisión"
            case .resolved: return "Resueltos"
            case .dismissed: return "Descartados"
            case .all: return "Todos"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 100)
                    Picker("Estado", selection: $status) {
                        ForEach(StatusFilter.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .onChange(of: status) { _, _ in Task { await load() } }

                    if loading && entries.isEmpty {
                        ProgressView().padding(30)
                    } else if let err = errorMsg {
                        Text(err).foregroundStyle(.red).padding(30)
                    } else if entries.isEmpty {
                        Text("Sin reportes").foregroundStyle(.secondary).padding(30)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(entries) { e in
                                entryRow(e)
                            }
                        }
                        .padding(.horizontal, 12).padding(.top, 8)
                    }
                    Spacer().frame(height: 80)
                }
            }
            .refreshable { await load() }

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white).padding(10)
                }
                Text("Reportes").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise").padding(10).foregroundStyle(.white)
                }
            }.frame(height: 50).padding(.horizontal, 4)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func entryRow(_ e: AdminService.ReportEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(e.reason, systemImage: "exclamationmark.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colorFor(e.status))
                Spacer()
                Text(e.status).font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            Text(e.target_name ?? "(deleted)")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(e.target_type).font(.caption2).foregroundStyle(.secondary)
                Text("#\(e.target_id)").font(.caption2).foregroundStyle(.secondary)
                Text("· \(e.reporter_email ?? "?")").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if let n = e.note, !n.isEmpty {
                Text("\"\(n)\"").font(.caption).italic().foregroundStyle(.secondary).lineLimit(3)
            }
            if e.status == "open" || e.status == "in_review" {
                HStack {
                    Button {
                        Task { await act(e.id, "resolve") }
                    } label: {
                        if acting == e.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Resolver", systemImage: "checkmark.circle").font(.caption)
                        }
                    }.buttonStyle(.borderedProminent).tint(.green).disabled(acting != nil)
                    Button {
                        Task { await act(e.id, "dismiss") }
                    } label: {
                        Label("Descartar", systemImage: "xmark.circle").font(.caption)
                    }.buttonStyle(.bordered).tint(.gray).disabled(acting != nil)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    private func colorFor(_ status: String) -> Color {
        switch status {
        case "open": return .orange
        case "in_review": return .yellow
        case "resolved": return .green
        case "dismissed": return .gray
        default: return .white
        }
    }

    private func load() async {
        loading = true; errorMsg = nil
        do {
            let r = try await AdminService.shared.reportsQueue(status: status.rawValue, limit: 100)
            entries = r.entries
        } catch { errorMsg = error.localizedDescription }
        loading = false
    }
    private func act(_ id: Int, _ action: String) async {
        acting = id
        do {
            _ = try await AdminService.shared.resolveReport(reportId: id, action: action)
            entries.removeAll { $0.id == id }
        } catch { errorMsg = error.localizedDescription }
        acting = nil
    }
}
