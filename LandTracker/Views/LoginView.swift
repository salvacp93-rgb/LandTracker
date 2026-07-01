import SwiftUI

struct LoginView: View {
    private enum LoginField: Hashable {
        case email
        case password
    }

    @ObservedObject var viewModel: AuthViewModel
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @State private var showingRegistration = false
    @State private var showingEmployeeInviteInfo = false
    @State private var autoSubmitTask: Task<Void, Never>?
    @FocusState private var focusedField: LoginField?

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    var body: some View {
        ZStack {
            loginBackground

            if showingEmployeeInviteInfo {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideEmployeeInviteInfo()
                    }
                    .zIndex(1)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    brandHeader
                        .padding(.top, 32)

                    credentialCard

                    if let error = viewModel.errorMessage {
                        StatusBanner(text: error, icon: "exclamationmark.triangle.fill", tint: .red)
                            .padding(.horizontal, 24)
                    }

                    if let success = viewModel.successMessage {
                        StatusBanner(text: success, icon: "checkmark.circle.fill", tint: .green)
                            .padding(.horizontal, 24)
                    }

                    Button(action: { Task { await submitLogin() } }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                        } else {
                            Text(language.localized("Sign in", "Iniciar sesión"))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(brandBlue)
                    .padding(.horizontal, 24)
                    .disabled(viewModel.isLoading)

                    Button {
                        viewModel.errorMessage = nil
                        hideEmployeeInviteInfo(animated: false)
                        showingRegistration = true
                    } label: {
                        Text(language.localized("Create account", "Crear cuenta"))
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(brandBlue)
                    .disabled(viewModel.isLoading)

                    EmployeeInviteInfoButton(
                        title: language.localized("Employee registration info", "Información sobre el registro"),
                        action: toggleEmployeeInviteInfo
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if showingEmployeeInviteInfo {
                EmployeeInviteGlassPopover(
                    text: language.localized(
                        "Employees must be invited by an owner from Team before they can register.",
                        "Los empleados deben ser invitados por un propietario desde Equipo antes de registrarse."
                    )
                )
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.bottom, 116)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                .zIndex(2)
                .onTapGesture {
                    hideEmployeeInviteInfo()
                }
            }
        }
        .sheet(isPresented: $showingRegistration) {
            RegistrationSheetView(
                viewModel: viewModel,
                isPresented: $showingRegistration
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            viewModel.mode = .login
            Task { await viewModel.loadSession() }
        }
        .onChange(of: viewModel.password) { oldValue, newValue in
            scheduleAutoSubmitIfNeeded(from: oldValue, to: newValue)
        }
        .onChange(of: viewModel.isAuthenticated) { _, newValue in
            if newValue {
                dismissKeyboard()
                cancelAutoSubmit()
            }
        }
        .onDisappear {
            cancelAutoSubmit()
        }
    }

    @MainActor
    private func submitLogin() async {
        dismissKeyboard()
        cancelAutoSubmit()
        viewModel.mode = .login
        await viewModel.submit()
    }

    private var brandBlue: Color {
        Color(red: 0.06, green: 0.22, blue: 0.42)
    }

    private var loginBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(brandBlue.opacity(0.14))
                .frame(width: 340, height: 340)
                .blur(radius: 52)
                .offset(x: -150, y: -280)

            Circle()
                .fill(Color.cyan.opacity(0.1))
                .frame(width: 300, height: 300)
                .blur(radius: 48)
                .offset(x: 160, y: -40)
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)

                Image("AppLogoCircle")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 112, height: 112)
                    .clipShape(Circle())
                    .offset(x: -2, y: -4)
            }
            .frame(width: 128, height: 128)
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(y: -4)

            Text("LandTracker")
                .font(.custom("AvenirNext-HeavyItalic", size: 44))
                .foregroundStyle(brandBlue)
                .kerning(-0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("LandTracker")

            Text(
                language.localized(
                    "Sign in to keep your lands and team synced.",
                    "Accede para mantener tus tierras y tu equipo sincronizados."
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 26)
        }
        .accessibilityElement(children: .combine)
    }

    private var credentialCard: some View {
        VStack(spacing: 14) {
            LoginCredentialField(
                label: language.localized("Email", "Correo electrónico"),
                icon: "envelope.fill"
            ) {
                TextField(language.localized("you@email.com", "tu@email.com"), text: $viewModel.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit {
                        focusedField = .password
                    }
            }

            LoginCredentialField(
                label: language.localized("Password", "Contraseña"),
                icon: "lock.fill"
            ) {
                SecureField(language.localized("Enter your password", "Introduce tu contraseña"), text: $viewModel.password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        Task { await submitLogin() }
                    }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        .padding(.horizontal, 24)
    }

    private func toggleEmployeeInviteInfo() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showingEmployeeInviteInfo.toggle()
        }
    }

    private func scheduleAutoSubmitIfNeeded(from oldValue: String, to newValue: String) {
        cancelAutoSubmit()

        let normalizedEmail = viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let insertedCount = newValue.count - oldValue.count
        let likelyAutofill = insertedCount > 1 || (oldValue.isEmpty && newValue.count >= 8)

        guard focusedField == .password,
              !viewModel.isLoading,
              !normalizedEmail.isEmpty,
              !newValue.isEmpty,
              likelyAutofill else {
            return
        }

        autoSubmitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled,
                  focusedField == .password,
                  viewModel.password == newValue,
                  !viewModel.isLoading else {
                return
            }
            await submitLogin()
        }
    }

    private func cancelAutoSubmit() {
        autoSubmitTask?.cancel()
        autoSubmitTask = nil
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func hideEmployeeInviteInfo(animated: Bool = true) {
        guard showingEmployeeInviteInfo else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                showingEmployeeInviteInfo = false
            }
        } else {
            showingEmployeeInviteInfo = false
        }
    }
}

private struct LoginCredentialField<Field: View>: View {
    let label: String
    let icon: String
    @ViewBuilder var field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                field()
                    .font(.body)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

private struct StatusBanner: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.footnote)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct RegistrationSheetView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Binding var isPresented: Bool
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @State private var email: String
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var registrationType: AuthViewModel.RegistrationType = .individual
    @State private var localError: String?

    init(viewModel: AuthViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        self._email = State(initialValue: viewModel.email)
    }

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var registrationBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    private var registrationRowBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                registrationBackground
                    .ignoresSafeArea()

                Form {
                    Section(language.localized("Account type", "Tipo de cuenta")) {
                        Picker("", selection: $registrationType) {
                            Text(language.localized("Individual", "Particular"))
                                .tag(AuthViewModel.RegistrationType.individual)
                            Text(language.localized("Organization", "Organización"))
                                .tag(AuthViewModel.RegistrationType.organization)
                            Text(language.localized("Employee", "Empleado"))
                                .tag(AuthViewModel.RegistrationType.employee)
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(registrationRowBackground)

                    Section(language.localized("Access data", "Datos de acceso")) {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            TextField("Email", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textContentType(.emailAddress)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            SecureField(language.localized("Password", "Contraseña"), text: $password)
                                .textContentType(.newPassword)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            SecureField(language.localized("Confirm password", "Confirmar contraseña"), text: $confirmPassword)
                                .textContentType(.newPassword)
                        }
                    }
                    .listRowBackground(registrationRowBackground)

                    if let message = errorMessageToDisplay {
                        Section {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        .listRowBackground(registrationRowBackground)
                    }

                    if let success = viewModel.successMessage {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(success)
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            }
                        }
                        .listRowBackground(registrationRowBackground)
                    }

                    Section {
                        HStack {
                            Spacer()
                            Button {
                                Task { await submitRegistration() }
                            } label: {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text(submitLabel)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(width: 220)
                            .disabled(!canSubmit || viewModel.isLoading)
                            Spacer()
                        }
                    }
                    .listRowBackground(registrationRowBackground)

                }
                .scrollContentBackground(.hidden)
                .background(registrationBackground)
                .listSectionSpacing(14)
            }
            .navigationTitle(language.localized("Create account", "Crear cuenta"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(language.localized("Close", "Cerrar")) {
                        dismissSheet()
                    }
                }
            }
            .onChange(of: registrationType) { _, _ in
                localError = nil
                viewModel.errorMessage = nil
            }
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        password == confirmPassword
    }

    private var errorMessageToDisplay: String? {
        localError ?? viewModel.errorMessage
    }

    private var submitLabel: String {
        switch registrationType {
        case .individual:
            return language.localized("Create account", "Crear cuenta")
        case .organization:
            return language.localized("Create account", "Crear cuenta")
        case .employee:
            return language.localized("Create account", "Crear cuenta")
        }
    }

    @MainActor
    private func submitRegistration() async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            localError = language.localized("Enter email and password.", "Introduce email y contraseña.")
            return
        }

        guard password == confirmPassword else {
            localError = language.localized("Passwords do not match.", "Las contraseñas no coinciden.")
            return
        }

        localError = nil
        viewModel.errorMessage = nil
        viewModel.successMessage = nil
        viewModel.mode = .register
        viewModel.registrationType = registrationType
        viewModel.email = normalizedEmail
        viewModel.password = password

        await viewModel.submit()

        let completedWithoutError = viewModel.errorMessage == nil
        let shouldDismiss = viewModel.isAuthenticated || viewModel.successMessage != nil
        if completedWithoutError && shouldDismiss {
            viewModel.mode = .login
            viewModel.password = ""
            isPresented = false
        }
    }

    private func dismissSheet() {
        viewModel.mode = .login
        viewModel.errorMessage = nil
        localError = nil
        isPresented = false
    }
}

private struct EmployeeInviteInfoButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.blue.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EmployeeInviteGlassPopover: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .font(.headline.weight(.semibold))

            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

// MARK: - Preview

#Preview {
    LoginView(viewModel: AuthViewModel())
}
