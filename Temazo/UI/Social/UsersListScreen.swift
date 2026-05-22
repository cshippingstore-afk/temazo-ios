import SwiftUI

enum UserListKind {
    case followers, following, search
}

/// Lista de usuarios: followers / following / búsqueda. Resultado tappable.
struct UsersListScreen: View {
    let kind: UserListKind
    let userId: Int64?      // para followers/following
    let initialQuery: String?
    let onBack: () -> Void
    let onOpen: (Int64, String?) -> Void

    @State private var users: [PublicUserBrief] = []
    @State private var loading: Bool = false
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if kind == .search { searchField }
            if loading && users.isEmpty {
                Spacer()
                ProgressView().tint(.neonPink)
                Spacer()
            } else if users.isEmpty {
                Spacer()
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMid)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(users) { u in
                            userRow(u)
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
        .background(Color.bgRoot)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Button { onBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18))
                    .foregroundStyle(.white).padding(8)
            }
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private var searchField: some View {
        TextField("Buscar usuarios…", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(10)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSurface))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .onChange(of: query) { _, new in
                if new.count >= 2 { Task { await search() } }
                else if new.isEmpty { users = [] }
            }
    }

    private func userRow(_ u: PublicUserBrief) -> some View {
        Button { onOpen(u.id, u.username) } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: u.displayAvatar ?? "")) { phase in
                    if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                    else { Color.bgSurfaceHi }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(u.username ?? "@usuario")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    if let bio = u.bio, !bio.isEmpty {
                        Text(bio).font(.system(size: 11)).foregroundStyle(Color.textLow).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        switch kind {
        case .followers: return "Seguidores"
        case .following: return "Siguiendo"
        case .search:    return "Buscar usuarios"
        }
    }

    private var emptyText: String {
        switch kind {
        case .followers: return "Sin seguidores aún"
        case .following: return "No sigue a nadie aún"
        case .search:    return "Empieza a teclear…"
        }
    }

    private func load() async {
        switch kind {
        case .followers:
            guard let id = userId else { return }
            loading = true; defer { loading = false }
            if let r = try? await TemazoAPI.shared.userFollowers(userId: id) {
                users = r.users
            }
        case .following:
            guard let id = userId else { return }
            loading = true; defer { loading = false }
            if let r = try? await TemazoAPI.shared.userFollowingUsers(userId: id) {
                users = r.users
            }
        case .search:
            if let q = initialQuery, !q.isEmpty {
                query = q
                await search()
            }
        }
    }

    private func search() async {
        loading = true; defer { loading = false }
        if let r = try? await TemazoAPI.shared.userSearch(query) {
            users = r.users
        }
    }
}
