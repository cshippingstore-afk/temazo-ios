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
    @State private var showQueue = false
    @State private var showSleepTimer = false
    @State private var showRecommend = false
    @ObservedObject private var sleepTimer = SleepTimer.shared

    /// Cache de la imagen large del artista resuelta por /api/artist.php cuando
    /// la track no trae `artist_image_medium`. Réplica del Android FullPlayer.
    @State private var fetchedArtistImg: String? = nil

    /// URL efectiva del avatar del artista — la de la track si existe, si no la fetcheada.
    private var artistAvatarUrl: String? {
        if let raw = player.state.currentTrack?.artistImageMedium, !raw.isEmpty { return raw }
        return fetchedArtistImg
    }

    /// Inicial del nombre del artista para fallback cuando no hay imagen.
    private var initialChar: String {
        guard let n = player.state.currentTrack?.artistName, let c = n.first else { return "?" }
        return String(c).uppercased()
    }

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
                .task(id: t.artistId ?? -1) { await ensureArtistImage() }
            }
        )
    }

    // MARK: - Subviews

    private func topBar(closeAction: @escaping () -> Void) -> some View {
        let track = player.state.currentTrack
        let canGoArtist = (track?.artistId != nil) || (track?.artistSlug?.isEmpty == false)
        return HStack {
            Button { closeAction() } label: {
                Image(systemName: "chevron.down").font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("REPRODUCIENDO")
                .font(.system(size: 10, weight: .bold)).tracking(1.5)
                .foregroundStyle(Color.textMid)
            Spacer()
            // Avatar circular del artista (réplica Android) → tap abre ArtistScreen.
            // Reemplaza al icono "music.note.list" que está movido a bottomActions.
            Button {
                if canGoArtist { onArtistClick() }
            } label: {
                ZStack {
                    Circle().fill(Color.white.opacity(0.08))
                    Circle().stroke(Color.neonPink.opacity(0.6), lineWidth: 1)
                    if let raw = artistAvatarUrl, !raw.isEmpty,
                       let url = URL(string: raw.hasPrefix("http") ? raw
                                     : "https://temazo.es\(raw.hasPrefix("/") ? "" : "/")\(raw)") {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                Text(initialChar)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .clipShape(Circle())
                    } else {
                        Text(initialChar)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!canGoArtist)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    /// Fetcha la imagen del artista vía /api/artist.php si la track no la trae.
    private func ensureArtistImage() async {
        guard let t = player.state.currentTrack else { return }
        if let m = t.artistImageMedium, !m.isEmpty { return }
        guard t.artistId != nil || (t.artistSlug?.isEmpty == false) else { return }
        if let r = try? await TemazoAPI.shared.artist(
            id: t.artistId, slug: t.artistSlug, name: nil
        ) {
            // Artist model tiene imageLarge + image (no imageMedium — eso es de AlbumSummary).
            let url = r.artist?.imageLarge ?? r.artist?.image
            await MainActor.run { fetchedArtistImg = url }
        }
    }

    private func cover(track: Track) -> some View {
        ZStack {
            CoverImage(url: track.coverUrl, size: 320, cornerRadius: 20)
            SourceRibbon(
                source: player.state.source,
                trackId: track.id,
                ribbonWidth: 130,
                ribbonHeight: 28,
                fontSize: 14
            )
            .frame(width: 320, height: 320)
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
            MarqueeText(text: track.title,
                        font: .system(size: 22, weight: .bold),
                        color: .white, velocity: 36)
                .frame(height: 28)
                .padding(.horizontal, 18)
            Text(track.artistName ?? "")
                .font(.system(size: 14))
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
        // Layout paridad Android: shuffle izquierda | prev/play/next centrados | repeat derecha.
        // El botón de "cola" (list.bullet) se mueve a bottomActions porque ahí pega visual.
        HStack {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(player.state.shuffle ? Color.neonPink : Color.textMid)
            }
            Spacer()
            HStack(spacing: 8) {
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
            Spacer()
            Button { player.toggleRepeat() } label: {
                Image(systemName: player.state.repeatMode == 2 ? "repeat.1" : "repeat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(player.state.repeatMode == 0 ? Color.textMid : Color.neonPink)
            }
        }
        .padding(.horizontal, 18)
    }

    private func bottomActions(isFav: Bool, trackId: Int64) -> some View {
        // Layout paridad Android: pill "Letra" centrada arriba, luego 2 filas
        // SpaceEvenly de acciones (4 + 3). El helper circleBtn unifica el estilo.
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button { showLyrics.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.alignleft")
                        Text("Letra").font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(showLyrics ? Color.neonPink : Color.white.opacity(0.08)))
                    .foregroundStyle(.white)
                    .shadow(color: showLyrics ? Color.neonPink.opacity(0.5) : .clear, radius: 8)
                }
                Spacer()
            }
            // FILA 1: Favorito · Añadir a playlist · Cargar playlist · Cola
            HStack {
                Spacer()
                circleBtn(systemName: isFav ? "heart.fill" : "heart",
                          tint: isFav ? Color.neonPink : Color.white.opacity(0.7)) {
                    FavToggle.toggle(trackId: trackId, favRepo: favorites)
                }
                Spacer()
                circleBtn(systemName: "plus.rectangle.on.rectangle") { onAddToPlaylist() }
                Spacer()
                circleBtn(systemName: "music.note.list") { onLoadPlaylist() }
                Spacer()
                circleBtn(systemName: "list.bullet") { showQueue = true }
                Spacer()
            }
            // FILA 2: Sleep timer · Recomendar · Compartir
            HStack {
                Spacer()
                circleBtn(systemName: sleepTimer.isActive ? "moon.fill" : "moon",
                          tint: sleepTimer.isActive ? Color.neonCyan : Color.white.opacity(0.7)) {
                    showSleepTimer = true
                }
                Spacer()
                circleBtn(systemName: "paperplane") { showRecommend = true }
                Spacer()
                circleBtn(systemName: "square.and.arrow.up") { shareCurrent() }
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .sheet(isPresented: $showQueue) {
            QueueSheet(onClose: { showQueue = false })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheet(onClose: { showSleepTimer = false })
                .presentationDetents([.fraction(0.45)])
        }
        .sheet(isPresented: $showRecommend) {
            if let t = player.state.currentTrack {
                RecommendTrackSheet(track: t, onClose: { showRecommend = false })
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Botón circular 44×44 con icono SF Symbols. Réplica del Android `CircleBtn`.
    private func circleBtn(systemName: String,
                           tint: Color = Color.white.opacity(0.7),
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func shareCurrent() {
        guard let t = player.state.currentTrack else { return }
        TemazoShare.shareTrack(t)
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
