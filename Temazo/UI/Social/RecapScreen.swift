import SwiftUI

/// Recap mensual del usuario — minutos escuchados, plays totales,
/// top tracks/artistas/géneros.
struct RecapScreen: View {
    let onBack: () -> Void

    @State private var recap: MonthlyRecapResponse? = nil
    @State private var loading: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if loading && recap == nil {
                    ProgressView().tint(.neonPink).padding(.top, 60)
                } else if let r = recap {
                    statsCards(r)
                    if !r.top_tracks.isEmpty { topTracksSection(r) }
                    if !r.top_artists.isEmpty { topArtistsSection(r) }
                    if !r.top_genres.isEmpty { topGenresSection(r) }
                } else {
                    Text("Todavía no hay suficiente historial.\nSigue escuchando y vuelve.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMid)
                        .multilineTextAlignment(.center)
                        .padding(.top, 60)
                }
                Spacer(minLength: 30)
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
            Text("Tu recap")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func statsCards(_ r: MonthlyRecapResponse) -> some View {
        HStack(spacing: 12) {
            stat("\(r.minutes)", "minutos")
            stat("\(r.plays)", "reproducciones")
        }
        .padding(.horizontal, 18)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(
                    LinearGradient(colors: [Color.neonPink, Color.neonCyan],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.textMid)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.bgSurface.opacity(0.6)))
    }

    private func topTracksSection(_ r: MonthlyRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top canciones")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
            VStack(spacing: 6) {
                ForEach(Array(r.top_tracks.prefix(10).enumerated()), id: \.offset) { idx, t in
                    HStack(spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(idx < 3 ? Color.neonPink : Color.textMid)
                            .frame(width: 22)
                        AsyncImage(url: URL(string: t.cover_medium ?? "")) { phase in
                            if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                            else { Color.bgSurfaceHi }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title ?? "").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white).lineLimit(1)
                            Text(t.artist_name ?? "").font(.system(size: 11))
                                .foregroundStyle(Color.textLow).lineLimit(1)
                        }
                        Spacer()
                        if let p = t.plays {
                            Text("\(p)")
                                .font(.system(size: 11)).foregroundStyle(Color.textLow)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 4)
                }
            }
        }
    }

    private func topArtistsSection(_ r: MonthlyRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top artistas")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(r.top_artists.prefix(10).enumerated()), id: \.offset) { idx, a in
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: URL(string: a.image_medium ?? "")) { phase in
                                    if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                                    else { Color.bgSurfaceHi }
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                                Text("\(idx + 1)")
                                    .font(.system(size: 11, weight: .black))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.neonPink))
                                    .foregroundStyle(.white)
                            }
                            Text(a.name ?? "").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white).lineLimit(1).frame(width: 84)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func topGenresSection(_ r: MonthlyRecapResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tus géneros")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(r.top_genres.prefix(8).enumerated()), id: \.offset) { _, g in
                        Text(g.genre ?? "—")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Color.neonPink.opacity(0.18)))
                            .overlay(Capsule().stroke(Color.neonPink.opacity(0.4)))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        recap = try? await TemazoAPI.shared.monthlyRecap()
    }
}
