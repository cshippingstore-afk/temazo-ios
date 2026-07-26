import SwiftUI

/// Pantalla admin: historial de acciones (audit log) + rollback puntual.
struct AdminAuditLogScreen: View {
    let onBack: () -> Void

    @State private var entries: [AdminService.AuditEntry] = []
    @State private var loading = false
    @State private var errorMsg: String? = nil
    @State private var rollingBack: Int? = nil

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 56)
                    if loading && entries.isEmpty {
                        ProgressView().padding(40)
                    } else if let err = errorMsg {
                        Text(err).foregroundStyle(.red).padding(40)
                    } else if entries.isEmpty {
                        Text("Sin acciones registradas").foregroundStyle(.secondary).padding(40)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(entries) { e in
                                entryRow(e)
                            }
                        }
                        .padding(.horizontal, 12)
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
                Text("Historial admin").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise").padding(10).foregroundStyle(.white)
                }
            }.frame(height: 50).padding(.horizontal, 4)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func entryRow(_ e: AdminService.AuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(e.action, systemImage: iconFor(e.action))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(e.reverted == 1 ? Color.orange : Color.cyan)
                Spacer()
                Text(shortDate(e.created_at)).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(e.target_type).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                if let tid = e.target_id { Text("#\(tid)").font(.caption).foregroundStyle(.secondary) }
                Text("· \(e.admin_email ?? "?")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let n = e.note, !n.isEmpty {
                Text(n).font(.caption).italic().foregroundStyle(.secondary).lineLimit(2)
            }
            if e.reverted == 1 {
                Text("Revertido").font(.caption2).foregroundStyle(.orange)
            } else if canRollback(e.action) {
                Button {
                    Task { await rollback(e.id) }
                } label: {
                    if rollingBack == e.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Deshacer", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(rollingBack != nil)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    private func iconFor(_ a: String) -> String {
        switch a {
        case "hide", "unhide", "ban_artist", "unban_artist": return "eye.slash"
        case "edit_meta", "edit_bio", "edit_genres": return "square.and.pencil"
        case "replace_youtube": return "arrow.left.arrow.right.circle"
        case "import_youtube", "import_youtube_playlist_item", "import_playlist_youtube": return "square.and.arrow.down"
        case "boost_popularity": return "chart.line.uptrend.xyaxis"
        case "reassign_album": return "square.stack.3d.up.badge.a"
        case "merge_tracks": return "arrow.triangle.merge"
        case "rollback": return "arrow.uturn.backward"
        case "force_rehydrate": return "arrow.clockwise.circle"
        default: return "circle"
        }
    }
    private func canRollback(_ action: String) -> Bool {
        ["hide","unhide","edit_meta","replace_youtube","boost_popularity",
         "edit_bio","reassign_album"].contains(action)
    }
    private func shortDate(_ s: String) -> String {
        // "2026-07-26 14:32:11" → "07/26 14:32"
        if s.count >= 16 {
            let idx = s.index(s.startIndex, offsetBy: 5)
            return String(s[idx..<s.index(s.startIndex, offsetBy: 16)])
        }
        return s
    }

    private func load() async {
        loading = true; errorMsg = nil
        do {
            let r = try await AdminService.shared.auditLog(limit: 100)
            entries = r.entries
        } catch { errorMsg = error.localizedDescription }
        loading = false
    }
    private func rollback(_ id: Int) async {
        rollingBack = id
        do {
            _ = try await AdminService.shared.rollbackAction(actionId: id)
            await load()
        } catch { errorMsg = error.localizedDescription }
        rollingBack = nil
    }
}
