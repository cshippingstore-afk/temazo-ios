import SwiftUI

struct NoticiasScreen: View {
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void

    @State private var news: [NewsItem] = []
    @State private var loading: Bool = true
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            TemazoSubScreenHeader(
                title: "Noticias",
                onBack: onBack,
                onAvatarClick: onAvatarClick,
                onBellClick: onBellClick,
                onEventsClick: onEventsClick,
                onNewsClick: {}  // ya estás aquí
            )

            if loading {
                Spacer()
                ProgressView().tint(Color.neonPink)
                Spacer()
            } else if let err = error {
                Spacer()
                Text(err).foregroundStyle(.white.opacity(0.6))
                Spacer()
            } else if news.isEmpty {
                Spacer()
                Text("Sin noticias por ahora")
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(news) { n in
                            NewsCard(n: n)
                                .onTapGesture { open(n) }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        await MainActor.run { loading = true }
        do {
            let r = try await TemazoAPI.shared.newsList(limit: 50)
            await MainActor.run {
                self.news = r.news ?? []
                self.error = nil
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }

    private func open(_ n: NewsItem) {
        guard let urlStr = n.url, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }
}

private struct NewsCard: View {
    let n: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let img = n.image, !img.isEmpty, let u = URL(string: img) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(Color.neonPink.opacity(0.12))
                    }
                }
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 12
                    )
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(n.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)

                if let s = n.summary, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(3)
                }

                HStack {
                    Text(n.source ?? "—")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.neonPink)
                    Spacer()
                    if let pa = n.published_at, !pa.isEmpty {
                        Text(String(pa.prefix(10)))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}
