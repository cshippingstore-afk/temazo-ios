import SwiftUI

struct RegisterScreen: View {
    let onClose: () -> Void
    @EnvironmentObject var auth: AuthRepository

    @State private var email = ""
    @State private var password = ""
    @State private var birthDate = ""   // YYYY-MM-DD
    @State private var gender = "M"
    @State private var country = "ES"
    @State private var showPwd = false
    @State private var error: String? = nil

    private let countries: [(String, String)] = [
        ("ES","España"),("MX","México"),("AR","Argentina"),("CO","Colombia"),
        ("CL","Chile"),("PE","Perú"),("VE","Venezuela"),("CU","Cuba"),
        ("DO","Rep. Dominicana"),("PR","Puerto Rico"),("UY","Uruguay"),
        ("PY","Paraguay"),("EC","Ecuador"),("BO","Bolivia"),("GT","Guatemala"),
        ("HN","Honduras"),("NI","Nicaragua"),("CR","Costa Rica"),("PA","Panamá"),
        ("SV","El Salvador"),("US","USA")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("🎵 Únete a Temazo").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Text("Crea tu cuenta para guardar favoritos y playlists")
                        .font(.system(size: 12)).foregroundStyle(.textLow)

                    field("Email", $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()

                    HStack {
                        Group {
                            if showPwd { TextField("Contraseña (mín 8 + 1 número)", text: $password) }
                            else { SecureField("Contraseña (mín 8 + 1 número)", text: $password) }
                        }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .foregroundStyle(.white)
                        Button { showPwd.toggle() } label: {
                            Image(systemName: showPwd ? "eye.slash" : "eye").foregroundStyle(.textLow)
                        }
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))

                    field("Fecha nacimiento (YYYY-MM-DD)", $birthDate)
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: birthDate) { _, v in autoFormatBirthDate(v) }

                    HStack(spacing: 8) {
                        chip(label: "Hombre", value: "M", current: gender) { gender = "M" }
                        chip(label: "Mujer", value: "F", current: gender) { gender = "F" }
                        chip(label: "Otro",  value: "O", current: gender) { gender = "O" }
                    }

                    Picker("País", selection: $country) {
                        ForEach(countries, id: \.0) { c in
                            Text("\(c.1) (\(c.0))").tag(c.0)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
                    .tint(.neonCyan)

                    if let e = error { Text(e).font(.system(size: 12)).foregroundStyle(.liveRed) }

                    Button {
                        Task { await doRegister() }
                    } label: {
                        Group {
                            if auth.isLoading { ProgressView().tint(.white) }
                            else { Text("Crear cuenta").font(.system(size: 15, weight: .semibold)) }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.neonPink))
                        .foregroundStyle(.white)
                    }
                    .disabled(auth.isLoading)
                }
                .padding(16)
            }
            .background(Color.bgRoot)
            .navigationTitle("Crear cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onClose() } label: { Image(systemName: "xmark").foregroundStyle(.white) }
                }
            }
            .toolbarBackground(Color.bgRoot, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func field(_ placeholder: String, _ binding: Binding<String>) -> some View {
        TextField(placeholder, text: binding)
            .padding(12).foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
    }

    private func chip(label: String, value: String, current: String, action: @escaping ()->Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14).fill(current == value ? Color.neonPink : Color.bgSurfaceHi))
                .foregroundStyle(current == value ? .white : .textMid)
        }
    }

    private func autoFormatBirthDate(_ v: String) {
        // Inserta '-' automáticamente: YYYY-MM-DD (max 10 chars)
        let raw = v.filter { $0.isNumber }
        var out = ""
        for (i, ch) in raw.enumerated() {
            if i == 4 || i == 6 { out.append("-") }
            if out.count >= 10 { break }
            out.append(ch)
        }
        if out != v { birthDate = out }
    }

    private func doRegister() async {
        error = nil
        guard password.count >= 8, password.contains(where: { $0.isNumber }) else {
            error = "Contraseña: mín 8 caracteres con un número"; return
        }
        guard birthDate.count == 10 else {
            error = "Fecha en formato YYYY-MM-DD"; return
        }
        let result = await auth.register(email: email, password: password,
                                         birthDate: birthDate, gender: gender,
                                         countryCode: country)
        switch result {
        case .success: onClose()
        case .failure(let e): error = e.errorDescription
        }
    }
}
