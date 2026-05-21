import SwiftUI

struct FullPlayer: View {
    let onClose: () -> Void
    let onCoverClick: () -> Void
    let onArtistClick: () -> Void
    let onAddToPlaylist: () -> Void
    let onLoadPlaylist: () -> Void

    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesRepo

    @State private var showLyrics = false
    @State private var lyrics: [LyricLine] = []
    @State private var seekValue: Double = 0
    @State private var isSeeking = false

    var body: some View {
        guard let t = player.state.currentTrack else { return AnyView(EmptyView()) }
        let isFav = favorites.contains(t.id)
        return AnyView(
            GeometryReader { geo in
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x1a0a2e), Color(hex: 0x0a0a1a)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()

                    VStack(spacing: 14) {
                        topBar(closeAction: onClose)

                        if showLyrics {
                            LyricsView(lines: lyrics, posSec: player.state.positionSec) { sec in
                                player.seekTo(seconds: sec)
                            }
                            .frame(maxHeight: .infinity)
                            .padding(.horizontal, 18)
                        } else {
                            Spacer(minLength: 4)
                            cover(track: t)
                            Spacer(minLength: 4)
                        }

                        titleBlock(track: t)

                        progressBar()
                            .padding(.horizontal, 18)

                        transportRow()
                            .padding(.vertical, 8)

                        bottomActions(isFav: isFav, trackId: t.id)
                            .padding(.bottom, 24)
                    }
                }
                // Gestos Spotify:
                //  - Swipe ↓ cierra FullPlayer
                //  - Swipe ←/→ (en el 75% superior) siguiente/anterior canción
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { val in
                            let dx = val.translation.width
                            let dy = val.translation.height
                            let startY = val.startLocation.y
                            // Vertical down — siempre cierra
                            if abs(dy) > abs(dx), dy > 140 {
                                onClose()
                                return
                            }
                            // Horizontal — solo si empieza por encima del 75% (no choca con controles)
                            if abs(dx) > abs(dy), startY < geo.size.height * 0.75 {
                                if dx < -120 { player.next() }
                                else if dx > 120 { player.prev() }
                            }
                        }
                )
                .task(id: t.id) { await loadLyrics(trackId: t.id) }
            }
        )
    }

    // MARK: - Subviews

    private func topBar(closeAction: @escaping () -> Void) -> some View {
        HStack {
            Button { closeAction() } label: {
                Image(systemName: "chevron.down").font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("REPRODUCIENDO")
                .font(.system(size: 10, weight: .bold)).tracking(1.5)
                .foregroundStyle(Color.textMid)
            Spacer()
            Button { onLoadPlaylist() } label: {
                Image(systemName: "music.note.list").font(.system(size: 20))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func cover(track: Track) -> some View {
        CoverImage(url: track.coverUrl, size: 320, cornerRadius: 20)
            .shadow(color: Color.neonPink.opacity(0.5), radius: 40, y: 12)
            .shadow(color: Color.neonPurple.opacity(0.3), radius: 60, y: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(LinearGradient(colors: [Color.neonPink.opacity(0.6), Color.neonPurple.opacity(0.3)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.5)
            )
            .onTapGesture {
                if track.albumId != nil || (track.albumSlug?.isEmpty == false) {
                    onCoverClick()
                }
            }
    }

    private func titleBlock(track: Track) -> some View {
        VStack(spacing: 4) {
            Text(track.title).font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white).multilineTextAlignment(.center)
                .lineLimit(2)
            Text(track.artistName ?? "").font(.system(size: 14))
                .foregroundStyle(Color.textMid)
                .onTapGesture {
                    if track.artistId != nil || (track.artistSlug?.isEmpty == false) {
                        onArtistClick()
                    }
                }
        }
        .padding(.horizontal, 18)
    }

    private func progressBar() -> some View {
        VStack(spacing: 4) {
            NeonSlider(
                value: Binding(
                    get: { isSeeking ? seekValue : Double(player.state.positionSec) },
                    set: { seekValue = $0 }
                ),
                bounds: 0...Double(max(player.state.durationSec, 1)),
                onEditingChanged: { editing in
                    if editing {
                        isSeeking = true
                    } else {
                        player.seekTo(seconds: Float(seekValue))
                        isSeeking = false
                    }
                }
            )
            HStack {
                Text(format(player.state.positionSec)).font(.system(size: 11)).foregroundStyle(.textLow)
                Spacer()
                Text(format(player.state.durationSec)).font(.system(size: 11)).foregroundStyle(.textLow)
            }
        }
    }

    private func transportRow() -> some View {
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
                    .shadow(color: .neonPink.opacity(0.7), radius: 18, y: 0)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 30))
                    .foregroundStyle(.white)
            }
        }
    }

    private func bottomActions(isFav: Bool, trackId: Int64) -> some View {
        HStack(spacing: 20) {
            Button {
                FavToggle.toggle(trackId: trackId, favRepo: favorites)
            } label: {
                Image(systemName: isFav ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundStyle(isFav ? Color.neonPink : Color.textMid)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }

            Button { onAddToPlaylist() } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.textMid)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }

            Button { showLyrics.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                    Text("Letra").font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(showLyrics ? Color.neonPink : Color.white.opacity(0.08)))
                .foregroundStyle(.white)
                .shadow(color: showLyrics ? Color.neonPink.opacity(0.5) : .clear, radius: 8)
            }
        }
    }

    private func loadLyrics(trackId: Int64) async {
        lyrics = []
        do {
            let resp = try await TemazoAPI.shared.lyrics(trackId)
            if let lrc = resp.synced, !lrc.isEmpty {
                lyrics = LRCParser.parse(lrc)
            }
        } catch {}
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
