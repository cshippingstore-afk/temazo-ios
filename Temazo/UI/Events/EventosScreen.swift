import SwiftUI

private struct CountryOpt: Identifiable, Hashable {
    var id: String { iso }
    let iso: String
    let label: String
}

private let EVENTS_COUNTRIES: [CountryOpt] = [
    CountryOpt(iso: "ES", label: "España"),
    CountryOpt(iso: "MX", label: "México"),
    CountryOpt(iso: "AR", label: "Argentina"),
    CountryOpt(iso: "CO", label: "Colombia"),
    CountryOpt(iso: "CL", label: "Chile"),
    CountryOpt(iso: "PE", label: "Perú"),
    CountryOpt(iso: "VE", label: "Venezuela"),
    CountryOpt(iso: "EC", label: "Ecuador"),
    CountryOpt(iso: "UY", label: "Uruguay"),
    CountryOpt(iso: "PR", label: "Puerto Rico"),
    CountryOpt(iso: "DO", label: "República Dominicana"),
    CountryOpt(iso: "PY", label: "Paraguay"),
    CountryOpt(iso: "US", label: "EE.UU."),
    CountryOpt(iso: "PT", label: "Portugal"),
    CountryOpt(iso: "all", label: "Todos")
]

struct EventosScreen: View {
    let onBack: () -> Void
    let onAvatarClick: () -> Void
    let onBellClick: () -> Void
    let onNewsClick: () -> Void

    @State private var country: String = "ES"
    @State private var query: String = ""
    @State private var events: [EventListItem] = []
    @State private var loading: Bool = true
    @State private var error: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            TemazoSubScreenHeader(
                title: "Eventos",
                onBack: onBack,
                onAvatarClick: onAvatarClick,
                onBellClick: onBellClick,
                onEventsClick: {},  // ya estás aquí
                onNewsClick: onNewsClick
            )

            // Buscador
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Buscar artista, evento…", text: $query)
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 12).padding(.vertical, 8)

            // Chips de país
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EVENTS_COUNTRIES) { c in
                        Button {
                            country = c.iso
                        } label: {
                            Text(c.label)
                                .font(.system(size: 12, weight: country == c.iso ? .semibold : .regular))
                                .foregroundStyle(country == c.iso ? .white : Color.white.opacity(0.7))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(country == c.iso ? Color.neonPink : Color.white.opacity(0.06))
                                )
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(country == c.iso ? 0 : 0.15), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
            }

            // Contenido
            if loading {
                Spacer()
                ProgressView().tint(Color.neonPink)
                Spacer()
            } else if let err = error {
                Spacer()
                Text(err).foregroundStyle(.white.opacity(0.6))
                Spacer()
            } else if events.isEmpty {
                Spacer()
                Text("No hay eventos para mostrar")
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(events) { ev in
                            EventCard(ev: ev)
                                .onTapGesture { openEvent(ev) }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .task(id: country) { await reload() }
        .onChange(of: query) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if !Task.isCancelled { await reload() }
            }
        }
    }

    private func reload() async {
        await MainActor.run { loading = true }
        do {
            let r = try await TemazoAPI.shared.eventsList(
                country: country == "all" ? nil : country,
                q: query.isEmpty ? nil : query,
                limit: 60
            )
            await MainActor.run {
                self.events = r.events ?? []
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

    private func openEvent(_ ev: EventListItem) {
        let urlStr = ev.permalink ?? "https://temazo.es/eventos/\(ev.slug ?? "")"
        guard let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }
}

private struct EventCard: View {
    let ev: EventListItem

    var body: some View {
        HStack(spacing: 0) {
            if let img = ev.image_url, !img.isEmpty, let u = URL(string: img) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(Color.neonPink.opacity(0.15))
                    }
                }
                .frame(width: 80, height: 80)
                .clipped()
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        bottomLeadingRadius: 12,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
            } else {
                Rectangle().fill(Color.neonPink.opacity(0.15))
                    .frame(width: 80, height: 80)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                let sub = [ev.primary_artist, ev.venue_name].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                HStack(spacing: 3) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.neonPink)
                    let loc = [ev.city_name, ev.country_iso].compactMap { $0 }.joined(separator: ", ")
                    Text(loc)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    if let sd = ev.start_date, !sd.isEmpty {
                        Text("  ·  \(String(sd.prefix(10)))")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                if let dc = ev.dates_count, dc > 1 {
                    Text("+\(dc - 1) fechas más")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.neonPink)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Spacer(minLength: 0)
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
