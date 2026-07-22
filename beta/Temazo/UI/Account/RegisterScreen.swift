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
            ScrollView { content }
                .background(Color.bgRoot)
                .navigationTitle("Crear cuenta")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .toolbarBackground(Color.bgRoot, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            header
            emailField
            passwordField
            birthField
            genderRow
            countryPicker
            errorMessage
            submitButton
        }
        .padding(16)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { onClose() } label: { Image(systemName: "xmark").foregroundStyle(.white) }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("🎵 Únete a Temazo")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("Crea tu cuenta para guardar favoritos y playlists")
                .font(.system(size: 12))
                .foregroundStyle(.textLow)
        }
    }

    private var emailField: some View {
        TextField("Email", text: $email)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .padding(12)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
    }

    private var passwordField: some View {
        HStack {
            Group {
                if showPwd {
                    TextField("Contraseña (mín 8 + 1 número)", text: $password)
                } else {
                    SecureField("Contraseña (mín 8 + 1 número)", text: $password)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(.white)

            Button { showPwd.toggle() } label: {
                Image(systemName: showPwd ? "eye.slash" : "eye")
                    .foregroundStyle(.textLow)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
    }

    private var birthField: some View {
        TextField("Fecha nacimiento (YYYY-MM-DD)", text: $birthDate)
            .keyboardType(.numbersAndPunctuation)
            .padding(12)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
            .onChange(of: birthDate) { _, v in autoFormatBirthDate(v) }
    }

    private var genderRow: some View {
        HStack(spacing: 8) {
            chip(label: "Hombre", value: "M") { gender = "M" }
            chip(label: "Mujer",  value: "F") { gender = "F" }
            chip(label: "Otro",   value: "O") { gender = "O" }
        }
    }

    private var countryPicker: some View {
        Picker("País", selection: $country) {
            ForEach(countries, id: \.0) { c in
                Text("\(c.1) (\(c.0))").tag(c.0)
            }
        }
        .pickerStyle(.menu)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSurface))
        .tint(.neonCyan)
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let e = error {
            Text(e).font(.system(size: 12)).foregroundStyle(.liveRed)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await doRegister() }
        } label: {
            Group {
                if auth.isLoading { ProgressView().tint(.white) }
                else { Text("Crear cuenta").font(.system(size: 15, weight: .semibold)) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.neonPink))
            .foregroundStyle(.white)
        }
        .disabled(auth.isLoading)
    }

    private func chip(label: String, value: String, action: @escaping () -> Void) -> some View {
        let active = gender == value
        return Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14).fill(active ? Color.neonPink : Color.bgSurfaceHi))
                .foregroundStyle(active ? .white : .textMid)
        }
    }

    private func autoFormatBirthDate(_ v: String) {
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
