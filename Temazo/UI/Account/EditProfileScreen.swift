import SwiftUI
import PhotosUI

/// Editar perfil: bio, playlist destacada (pinned) y avatar.
/// Equivalente del Android `EditProfileScreen.kt`.
struct EditProfileScreen: View {
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onEventsClick: () -> Void
    let onNewsClick: () -> Void

    @EnvironmentObject var auth: AuthRepository

    @State private var loading: Bool = true
    @State private var error: String? = nil

    // Bio
    @State private var bio: String = ""
    @State private var savingBio: Bool = false
    @State private var bioMsg: String? = nil

    // Pinned playlist
    @State private var publicPlaylists: [Playlist] = []
    @State private var pinnedId: Int64? = nil
    @State private var showPicker: Bool = false
    @State private var savingPinned: Bool = false
    @State private var pinnedMsg: String? = nil

    // Avatar
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var uploadingAvatar: Bool = false
    @State private var avatarUrl: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            TemazoSubScreenHeader(
                title: "Editar perfil",
                onBack: onBack,
                onAvatarClick: onAvatarClick,
                onBellClick: onBellClick,
                onEventsClick: onEventsClick,
                onNewsClick: onNewsClick
            )

            if loading {
                Spacer()
                ProgressView().tint(Color.neonPink)
                Spacer()
            } else if let e = error {
                Spacer()
                Text(e).foregroundStyle(Color.white.opacity(0.7))
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        avatarSection
                        Divider().background(Color.white.opacity(0.07))
                        bioSection
                        Divider().background(Color.white.opacity(0.07))
                        pinnedSection
                        Spacer().frame(height: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .task { await load() }
        .onChange(of: photoItem) { _, newItem in
            handlePickedPhoto(newItem)
        }
        .sheet(isPresented: $showPicker) {
            pinnedPickerSheet
        }
    }

    // MARK: - Sections

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Foto de perfil")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Sube una imagen cuadrada — máx 5 MB.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 14) {
                ZStack {
                    if let u = makeURL(avatarUrl) {
                        AsyncImage(url: u) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.05)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.neonPink.opacity(0.25))
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white)
                            )
                    }
                    if uploadingAvatar {
                        Circle().fill(Color.black.opacity(0.5))
                            .frame(width: 72, height: 72)
                        ProgressView().tint(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("Cambiar foto")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Color.neonPink))
                    }
                    .disabled(uploadingAvatar)

                    if avatarUrl != nil {
                        Button {
                            Task { await deleteAvatar() }
                        } label: {
                            Text("Quitar foto")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .disabled(uploadingAvatar)
                    }
                }
                Spacer()
            }
        }
    }

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Biografía")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Cuenta algo sobre ti — máximo 160 caracteres. Visible en tu perfil público.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Spacer().frame(height: 4)
            ZStack(alignment: .topLeading) {
                if bio.isEmpty {
                    Text("Tu biografía…")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.horizontal, 12).padding(.vertical, 10)
                }
                TextEditor(text: Binding(
                    get: { bio },
                    set: { bio = String($0.prefix(160)) }
                ))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundStyle(.white)
                .font(.system(size: 14))
                .frame(minHeight: 80, maxHeight: 140)
                .padding(.horizontal, 6).padding(.vertical, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            HStack {
                Text(bioMsg ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(bio.count)/160")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer().frame(height: 4)
            Button {
                Task { await saveBio() }
            } label: {
                HStack(spacing: 8) {
                    if savingBio { ProgressView().tint(.white).scaleEffect(0.7) }
                    Text("Guardar bio")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(Color.neonPink))
            }
            .disabled(savingBio)
        }
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Playlist destacada")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Elige una de tus playlists públicas para destacarla arriba en tu perfil.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Spacer().frame(height: 6)

            let pinned = publicPlaylists.first { $0.id == pinnedId }
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 10) {
                    pinnedThumb(playlist: pinned)
                    Text(pinned?.name ?? "— Ninguna —")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("▾")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if publicPlaylists.isEmpty {
                Spacer().frame(height: 4)
                Text("Aún no tienes ninguna playlist pública. Marca una como pública para destacarla.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }

            HStack {
                Text(pinnedMsg ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
            Spacer().frame(height: 4)
            Button {
                Task { await savePinned() }
            } label: {
                HStack(spacing: 8) {
                    if savingPinned { ProgressView().tint(.white).scaleEffect(0.7) }
                    Text("Guardar destacada")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(Color.neonPink))
            }
            .disabled(savingPinned)
        }
    }

    private func pinnedThumb(playlist: Playlist?) -> some View {
        Group {
            if let p = playlist, let u = makeURL(p.displayCover) {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { Color.white.opacity(0.06) }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if playlist != nil {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.neonPink.opacity(0.25))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "nosign")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }
        }
    }

    // MARK: - Pinned picker sheet

    private var pinnedPickerSheet: some View {
        ZStack {
            Color(red: 0.094, green: 0.078, blue: 0.110).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 0) {
                        pinnedOptionRow(label: "— Ninguna —", cover: nil, selected: pinnedId == nil, isNone: true) {
                            pinnedId = nil
                            showPicker = false
                        }
                        ForEach(publicPlaylists, id: \.id) { p in
                            pinnedOptionRow(label: p.name, cover: p.displayCover, selected: pinnedId == p.id, isNone: false) {
                                pinnedId = p.id
                                showPicker = false
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pinnedOptionRow(label: String, cover: String?, selected: Bool, isNone: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if isNone {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "nosign")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.55))
                        )
                } else if let u = makeURL(cover) {
                    AsyncImage(url: u) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Color.white.opacity(0.06) }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.55))
                        )
                }
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.neonPink)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load & save

    private func load() async {
        loading = true
        do {
            guard let myId = auth.currentUser?.id else {
                error = "Sin sesión"
                loading = false
                return
            }
            async let pubReq = TemazoAPI.shared.userPublicById(Int64(myId))
            async let plsReq = TemazoAPI.shared.playlists()
            let pub = try await pubReq
            let pls = try await plsReq

            bio = pub.user?.bio ?? ""
            pinnedId = pub.pinned_playlist?.id
            avatarUrl = pub.user?.displayAvatar
            publicPlaylists = pls.playlists.filter { $0.isPublic == true }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func saveBio() async {
        savingBio = true
        bioMsg = nil
        do {
            let r = try await TemazoAPI.shared.userBioSet(bio.trimmingCharacters(in: .whitespacesAndNewlines))
            bioMsg = (r.ok == true) ? "Guardado ✓" : "Error"
        } catch {
            bioMsg = "Error"
        }
        savingBio = false
    }

    private func savePinned() async {
        savingPinned = true
        pinnedMsg = nil
        do {
            let r = try await TemazoAPI.shared.userPinnedSet(playlistId: pinnedId ?? 0)
            pinnedMsg = (r.ok == true) ? "Guardado ✓" : (r.error ?? "Error")
        } catch {
            pinnedMsg = "Error"
        }
        savingPinned = false
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        uploadingAvatar = true
        Task {
            defer {
                Task { @MainActor in
                    uploadingAvatar = false
                    photoItem = nil
                }
            }
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { return }
            let mime: String = {
                if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
                if data.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
                if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
                if data.count > 12, data[0..<4] == Data([0x52,0x49,0x46,0x46]), data[8..<12] == Data([0x57,0x45,0x42,0x50]) { return "image/webp" }
                return "image/jpeg"
            }()
            do {
                let r = try await TemazoAPI.shared.avatarUpload(imageData: data, mime: mime)
                if r.ok {
                    await MainActor.run { avatarUrl = r.avatarUrl }
                }
            } catch {}
        }
    }

    private func deleteAvatar() async {
        uploadingAvatar = true
        defer { uploadingAvatar = false }
        do {
            let r = try await TemazoAPI.shared.avatarDelete()
            if r.ok == true {
                avatarUrl = nil
            }
        } catch {}
    }
}
