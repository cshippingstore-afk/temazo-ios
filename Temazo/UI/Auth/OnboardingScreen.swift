import SwiftUI

/// Onboarding tras registro: el usuario elige géneros favoritos y, a partir de
/// ellos, sigue al menos un puñado de artistas. Solo se muestra UNA vez (gated
/// por user_data.php?a=onboarding_status). El usuario puede saltarlo.
struct OnboardingScreen: View {
    let onFinish: () -> Void

    @State private var step: Int = 0   // 0 = géneros · 1 = artistas
    @State private var selectedGenres: Set<String> = []
    @State private var loadingArtists: Bool = false
    @State private var artists: [OnboardingArtist] = []
    @State private var followedArtists: Set<Int64> = []
    @State private var submitting: Bool = false

    private let genres: [(slug: String, name: String, emoji: String)] = [
        ("reggaeton","Reggaetón","🔥"), ("pop","Pop","🎤"),
        ("rock","Rock","🎸"), ("hip-hop","Hip-hop","🎧"),
        ("latin-pop","Latin Pop","🌶️"), ("regional-mexicano","Regional Mex","🤠"),
        ("electronic","Electrónica","💿"), ("rnb-soul","R&B / Soul","💜"),
        ("indie","Indie","✨"), ("metal","Metal","🤘"),
        ("k-pop","K-Pop","🌸"), ("bachata","Bachata","🎶"),
        ("flamenco","Flamenco","💃"), ("reggae-caribbean","Reggae","🏝"),
        ("jazz","Jazz","🎷"), ("classical","Clásica","🎼"),
        ("country-americana","Country","🤠"), ("blues","Blues","🎺"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1a0a2e), Color(hex: 0x0a0a1a)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                topBar
                if step == 0 { genresStep } else { artistsStep }
                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
    }

    private var topBar: some View {
        HStack {
            Text(step == 0 ? "Elige tus géneros" : "Sigue a tus artistas")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
            Spacer()
            Button { skip() } label: {
                Text("Saltar")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMid)
            }
        }
    }

    private var genresStep: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(genres, id: \.slug) { g in
                    let active = selectedGenres.contains(g.slug)
                    Button {
                        if active { selectedGenres.remove(g.slug) } else { selectedGenres.insert(g.slug) }
                    } label: {
                        HStack(spacing: 8) {
                            Text(g.emoji)
                            Text(g.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(active ? .white : Color.textMid)
                            Spacer()
                            if active {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(active ? Color.neonPink.opacity(0.85) : Color.bgSurface)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var artistsStep: some View {
        if loadingArtists && artists.isEmpty {
            Spacer()
            ProgressView().tint(.neonPink)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(artists) { a in
                        artistRow(a)
                    }
                }
            }
        }
    }

    private func artistRow(_ a: OnboardingArtist) -> some View {
        let followed = followedArtists.contains(a.id)
        return HStack(spacing: 12) {
            AsyncImage(url: URL(string: a.displayImage ?? "")) { phase in
                if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                else { Color.bgSurfaceHi }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(a.name ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if let f = a.followers, f > 0 {
                    Text("\(f.formatted()) seguidores")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textLow)
                }
            }
            Spacer()
            Button {
                Task { await toggleFollow(a) }
            } label: {
                Text(followed ? "Siguiendo" : "Seguir")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(
                        Capsule().fill(followed ? Color.neonPink.opacity(0.85) : Color.white.opacity(0.12))
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgSurface.opacity(0.5)))
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                if step == 0 { advanceToArtists() } else { Task { await finish() } }
            } label: {
                Group {
                    if submitting { ProgressView().tint(.white) }
                    else if step == 0 {
                        Text(selectedGenres.isEmpty ? "Saltar" : "Continuar (\(selectedGenres.count))")
                            .font(.system(size: 15, weight: .bold))
                    } else {
                        Text(followedArtists.isEmpty ? "Saltar" : "¡Listo! (\(followedArtists.count))")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Color.neonPink, Color.neonPurple],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(submitting)
        }
    }

    // MARK: - Actions

    private func advanceToArtists() {
        step = 1
        if selectedGenres.isEmpty { return }
        Task { await loadArtists() }
    }

    private func loadArtists() async {
        loadingArtists = true
        defer { loadingArtists = false }
        var collected: [OnboardingArtist] = []
        var seen = Set<Int64>()
        for g in selectedGenres {
            do {
                let r = try await TemazoAPI.shared.onboardingArtists(genre: g, limit: 5)
                for a in r.artists where !seen.contains(a.id) {
                    seen.insert(a.id)
                    collected.append(a)
                }
            } catch {}
        }
        artists = collected
    }

    private func toggleFollow(_ a: OnboardingArtist) async {
        let wasFollowed = followedArtists.contains(a.id)
        if wasFollowed { followedArtists.remove(a.id) } else { followedArtists.insert(a.id) }
        // Optimistic; backend con follow_toggle.
        _ = try? await TemazoAPI.shared.followToggle(artistId: a.id)
    }

    private func skip() {
        Task { await finish() }
    }

    private func finish() async {
        submitting = true
        defer { submitting = false }
        _ = try? await TemazoAPI.shared.onboardingFinish()
        onFinish()
    }
}
