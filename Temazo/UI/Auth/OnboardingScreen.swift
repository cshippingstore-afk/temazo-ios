import SwiftUI

/// Onboarding tras registro — réplica del Android:
///   Step 0: Elegir géneros (grid 2-col)
///   Step 1: Seguir artistas top 5 por género (grid 3-col, opcional)
///   Step 2: Done screen con cuenta de seed
/// Solo "Saltar todo" en step 0. Al terminar marca onboarded=1; no se repite.
struct OnboardingScreen: View {
    let onFinish: () -> Void

    @State private var step: Int = 0
    @State private var selectedGenres: Set<String> = []
    @State private var artists: [OnboardingArtist] = []
    @State private var selectedArtistIds: Set<Int64> = []
    @State private var loading: Bool = false

    private let genres: [(slug: String, name: String, emoji: String)] = [
        ("reggaeton","Reggaetón","🔥"), ("latin-pop","Latin Pop","🌶️"),
        ("pop","Pop","🎤"), ("hip-hop","Hip-hop","🎧"),
        ("rock","Rock","🎸"), ("rock-latino","Rock Latino","🎸"),
        ("electronic","Electrónica","💿"), ("indie","Indie","✨"),
        ("rnb-soul","R&B / Soul","💜"), ("bachata","Bachata","🎶"),
        ("regional-mexicano","Regional Mex","🤠"), ("flamenco","Flamenco","💃"),
        ("reggae-caribbean","Reggae","🏝"), ("metal","Metal","🤘"),
        ("k-pop","K-Pop","🌸"), ("j-pop","J-Pop","🌸"),
        ("country-americana","Country","🤠"), ("folk-acoustic","Folk","🎻"),
        ("jazz","Jazz","🎷"), ("blues","Blues","🎺"),
        ("classical","Clásica","🎼"), ("soundtracks","Bandas Sonoras","🎬"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1a0a2e), Color(hex: 0x0d0517), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            Group {
                switch step {
                case 0: stepGenres
                case 1: stepArtists
                default: stepDone
                }
            }
        }
    }

    // MARK: - Step 0: Genres

    private var stepGenres: some View {
        VStack(spacing: 14) {
            stepHeader(title: "Empecemos con tus géneros",
                       subtitle: "Elige los que te muevan. Lo demás vendrá solo.")

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(genres, id: \.slug) { g in
                        let active = selectedGenres.contains(g.slug)
                        Button {
                            if active { selectedGenres.remove(g.slug) }
                            else { selectedGenres.insert(g.slug) }
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
                            .padding(.horizontal, 14).padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(active ? Color.neonPink.opacity(0.85) : Color.bgSurface.opacity(0.7))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(active ? Color.neonPink : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }

            HStack(spacing: 10) {
                Button { Task { await finish() } } label: {
                    Text("Saltar todo")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .disabled(loading)

                Button { Task { await goToArtists() } } label: {
                    Text(loading ? "Cargando..." : "Siguiente")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(
                            LinearGradient(colors: [Color.neonPink, Color.neonPurple],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(loading)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    // MARK: - Step 1: Artists

    private var stepArtists: some View {
        VStack(spacing: 14) {
            stepHeader(title: "Sigue a tus favoritos",
                       subtitle: "Te ayudamos a empezar. Puedes saltar y añadirlos después.")

            if loading && artists.isEmpty {
                Spacer()
                ProgressView().tint(.neonPink)
                Spacer()
            } else if artists.isEmpty {
                Spacer()
                Text("No hay artistas para esos géneros. Pasa al siguiente paso.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMid)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(artists) { a in
                            artistCircle(a)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }

            HStack(spacing: 10) {
                Button { step = 0 } label: {
                    Text("Atrás")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                Button { step = 2 } label: {
                    Text("Siguiente")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(
                            LinearGradient(colors: [Color.neonPink, Color.neonPurple],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private func artistCircle(_ a: OnboardingArtist) -> some View {
        let active = selectedArtistIds.contains(a.id)
        return Button {
            if active { selectedArtistIds.remove(a.id) }
            else { selectedArtistIds.insert(a.id) }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    AsyncImage(url: URL(string: a.displayImage ?? "")) { phase in
                        if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                        else { Color.bgSurfaceHi }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(active ? Color.neonPink : Color.white.opacity(0.15),
                                        lineWidth: active ? 3 : 1)
                    )

                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.neonPink)
                            .background(Circle().fill(.black))
                            .offset(x: 30, y: 30)
                    }
                }
                Text(a.name ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 100)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Done

    private var stepDone: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("🎶")
                .font(.system(size: 80))
            Text("¡Todo listo!")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(.white)
            if selectedArtistIds.isEmpty {
                Text("Vamos a empezar y descubrirás cosas chulas mientras escuchas.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textMid)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text("Con \(selectedArtistIds.count) artista\(selectedArtistIds.count == 1 ? "" : "s") y \(selectedGenres.count) género\(selectedGenres.count == 1 ? "" : "s") preparamos tu inicio.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textMid)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()

            Button { Task { await finish() } } label: {
                Text(loading ? "Preparando..." : "Empezar")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(
                        LinearGradient(colors: [Color.neonPink, Color.neonPurple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(loading)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Common header

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Spacer().frame(height: 20)
            Text(title)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
            Spacer().frame(height: 6)
            // Stepper indicator
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i <= step ? Color.neonPink : Color.white.opacity(0.18))
                        .frame(width: i == step ? 24 : 8, height: 4)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Actions

    private func goToArtists() async {
        if selectedGenres.isEmpty { step = 2; return }
        loading = true
        defer { loading = false }
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
        step = 1
    }

    private func finish() async {
        loading = true
        defer { loading = false }
        for aid in selectedArtistIds {
            _ = try? await TemazoAPI.shared.followToggle(artistId: aid)
        }
        // Retry hasta 3 veces — si falla aquí, el próximo launch repetiría el flow.
        for _ in 0..<3 {
            do {
                let r = try await TemazoAPI.shared.onboardingFinish()
                if r.ok == true { break }
            } catch {}
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        onFinish()
    }
}
