import SwiftUI

/// Sheet para recomendar una canción a otro usuario.
/// Búsqueda con debounce + lista de usuarios que sigo + mensaje opcional.
struct RecommendTrackSheet: View {
    let track: Track
    let onClose: () -> Void

    @State private var query: String = ""
    @State private var following: [PublicUserBrief] = []
    @State private var searchResults: [PublicUserBrief] = []
    @State private var selected: PublicUserBrief? = nil
    @State private var note: String = ""
    @State private var sending: Bool = false
    @State private var sent: Bool = false

    @EnvironmentObject var auth: AuthRepository

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 40, height: 4).padding(.top, 10)

            VStack(spacing: 4) {
                Text("Recomendar canción")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(track.title) — \(track.artistName ?? "")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMid)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)

            if sent {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.neonCyan)
                    Text("Recomendación enviada")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
            } else {
                TextField("Buscar amigos…", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSurface))
                    .padding(.horizontal, 14)
                    .onChange(of: query) { _, v in
                        if v.count >= 2 { Task { await searchUsers() } }
                        else { searchResults = [] }
                    }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedUsers) { u in
                            userRow(u)
                        }
                    }
                }
                .frame(maxHeight: 240)

                if selected != nil {
                    TextField("Mensaje opcional…", text: $note, axis: .vertical)
                        .lineLimit(2...3)
                        .padding(10)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSurface))
                        .padding(.horizontal, 14)

                    Button { Task { await send() } } label: {
                        Text(sending ? "Enviando..." : "Enviar")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(
                                LinearGradient(colors: [Color.neonPink, Color.neonPurple],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }
                    .disabled(sending || selected == nil)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }

            Spacer().frame(height: 12)
        }
        .background(Color(red: 0.07, green: 0.04, blue: 0.12))
        .task { await loadFollowing() }
    }

    private var displayedUsers: [PublicUserBrief] {
        query.count >= 2 ? searchResults : following
    }

    private func userRow(_ u: PublicUserBrief) -> some View {
        Button { selected = u } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: u.displayAvatar ?? "")) { phase in
                    if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                    else { Color.bgSurfaceHi }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                Text(u.username ?? "@usuario")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if selected?.id == u.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.neonPink)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(selected?.id == u.id ? Color.neonPink.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func loadFollowing() async {
        guard let me = auth.currentUser else { return }
        if let r = try? await TemazoAPI.shared.userFollowingUsers(userId: Int64(me.id)) {
            following = r.users
        }
    }

    private func searchUsers() async {
        if let r = try? await TemazoAPI.shared.userSearch(query) {
            searchResults = r.users
        }
    }

    private func send() async {
        guard let u = selected else { return }
        sending = true
        defer { sending = false }
        _ = try? await TemazoAPI.shared.trackRecommend(trackId: track.id, toUserId: u.id, note: note)
        sent = true
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        onClose()
    }
}
