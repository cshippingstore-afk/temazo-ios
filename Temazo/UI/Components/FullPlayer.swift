import SwiftUI

struct FullPlayer: View {
    let onClose: () -> Void
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesRepo

    @State private var showLyrics = false
    @State private var lyrics: [LyricLine] = []
    @State private var lyricsLoaded = false
    @State private var seekValue: Float = 0
    @State private var isSeeking = false

    var body: some View {
        guard let t = player.state.currentTrack else { return AnyView(EmptyView()) }
        let isFav = favorites.contains(t.id)
        return AnyView(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1a0a2e), Color(hex: 0x0a0a1a)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    // Top bar
                    HStack {
                        Button { onClose() } label: {
                            Image(systemName: "chevron.down").font(.system(size: 22))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Text("REPRODUCIENDO")
                            .font(.system(size: 10, weight: .bold)).tracking(1.5)
                            .foregroundStyle(.textMid)
                        Spacer()
                        Button { /* queue */ } label: {
                            Image(systemName: "list.bullet").font(.system(size: 20))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    // Cover OR Lyrics
                    if showLyrics {
                        LyricsView(lines: lyrics, posSec: player.state.positionSec) { sec in
                            player.seekTo(seconds: sec)
                        }
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal, 18)
                    } else {
                        Spacer(minLength: 4)
                        CoverImage(url: t.coverUrl, size: 320, cornerRadius: 20)
                            .shadow(color: Color.neonPink.opacity(0.3), radius: 30, y: 10)
                        Spacer(minLength: 4)
                    }

                    // Title + artist
                    VStack(spacing: 4) {
                        Text(t.title).font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white).multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(t.artistName ?? "").font(.system(size: 14))
                            .foregroundStyle(.textMid)
                    }
                    .padding(.horizontal, 18)

                    // Progress slider
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { isSeeking ? Double(seekValue) : Double(player.state.positionSec) },
                                set: { v in seekValue = Float(v); isSeeking = true }
                            ),
                            in: 0...Double(max(player.state.durationSec, 1)),
                            onEditingChanged: { editing in
                                if !editing {
                                    player.seekTo(seconds: seekValue)
                                    isSeeking = false
                                }
                            }
                        )
                        .tint(.neonPink)
                        HStack {
                            Text(format(player.state.positionSec)).font(.system(size: 11)).foregroundStyle(.textLow)
                            Spacer()
                            Text(format(player.state.durationSec)).font(.system(size: 11)).foregroundStyle(.textLow)
                        }
                    }
                    .padding(.horizontal, 18)

                    // Controls
                    HStack(spacing: 30) {
                        Button { player.prev() } label: {
                            Image(systemName: "backward.fill").font(.system(size: 30))
                                .foregroundStyle(.white)
                        }
                        Button { player.togglePlay() } label: {
                            Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 38)).foregroundStyle(.white)
                                .frame(width: 76, height: 76)
                                .background(Circle().fill(Color.neonPink))
                        }
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(.system(size: 30))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.vertical, 8)

                    // Bottom row: fav + lyrics toggle
                    HStack(spacing: 30) {
                        Button { favorites.toggle(t.id) } label: {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(.system(size: 24))
                                .foregroundStyle(isFav ? Color.neonPink : Color.textMid)
                        }
                        Button { showLyrics.toggle() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "text.alignleft")
                                Text("Letra").font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(showLyrics ? Color.neonPink : Color.bgSurfaceHi))
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .task(id: t.id) { await loadLyrics(trackId: t.id) }
        )
    }

    private func loadLyrics(trackId: Int64) async {
        lyricsLoaded = false
        lyrics = []
        do {
            let resp = try await TemazoAPI.shared.lyrics(trackId)
            if let lrc = resp.synced, !lrc.isEmpty {
                lyrics = LRCParser.parse(lrc)
            }
            lyricsLoaded = true
        } catch {
            lyricsLoaded = true
        }
    }

    private func format(_ sec: Float) -> String {
        guard sec.isFinite, sec >= 0 else { return "0:00" }
        let s = Int(sec)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct LyricsView: View {
    let lines: [LyricLine]
    let posSec: Float
    let onSeek: (Float) -> Void

    var current: Int { LRCParser.currentLineIndex(lines, posSec: posSec) }

    var body: some View {
        if lines.isEmpty {
            VStack {
                Spacer()
                Text("Letra no disponible").foregroundStyle(.textLow)
                Spacer()
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                            Text(line.text)
                                .font(.system(size: i == current ? 22 : 17, weight: i == current ? .bold : .regular))
                                .foregroundStyle(i == current ? .white :
                                                 (i < current ? Color.white.opacity(0.35) : Color.white.opacity(0.7)))
                                .multilineTextAlignment(.center)
                                .id(i)
                                .onTapGesture { onSeek(line.timeSec) }
                        }
                    }
                    .padding(.vertical, 100)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: current) { _, new in
                    withAnimation(.easeInOut) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
        }
    }
}
