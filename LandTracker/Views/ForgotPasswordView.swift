import SwiftUI

/// Sheet opened from the login screen so a user who forgot the password can get a reset link.
///
/// The confirmation never says whether an account exists for the address: it reads the same in
/// both cases.
struct ForgotPasswordView: View {
    private enum Phase {
        case form
        case sent
    }

    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @State private var email: String
    @State private var phase: Phase = .form
    @State private var sentEmail = ""
    @State private var errorText: String?
    @FocusState private var emailFocused: Bool

    init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
        self._email = State(initialValue: viewModel.email)
    }

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        switch phase {
                        case .form:
                            formContent
                        case .sent:
                            sentContent
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(language.localized("Reset password", "Recuperar contraseña"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(language.localized("Close", "Cerrar")) {
                        dismiss()
                    }
                }
            }
            // A reset link opened while this sheet is up takes over: RootView presents the
            // "new password" sheet, and two sheets cannot be up at once.
            .onChange(of: viewModel.isSettingNewPassword) { _, isSetting in
                if isSetting { dismiss() }
            }
        }
    }

    // MARK: Form

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(
                language.localized(
                    "Enter the email of your account and we will send you a link to choose a new password.",
                    "Introduce el correo de tu cuenta y te enviaremos un enlace para elegir una nueva contraseña."
                )
            )
            .font(.poppins(.subheadline))
            .foregroundStyle(AppTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)

            LoginCredentialField(
                label: language.localized("Email", "Correo electrónico"),
                icon: "envelope.fill"
            ) {
                TextField(language.localized("you@email.com", "tu@email.com"), text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .submitLabel(.send)
                    .focused($emailFocused)
                    .onSubmit {
                        Task { await send() }
                    }
                    .onChange(of: email) { _, _ in
                        errorText = nil
                    }
            }

            if let errorText {
                StatusBanner(text: errorText, icon: "exclamationmark.triangle.fill", tint: AppTheme.negative)
            }

            Button {
                Task { await send() }
            } label: {
                if viewModel.isSendingPasswordReset {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                } else {
                    Text(language.localized("Send link", "Enviar enlace"))
                        .font(.poppins(.body, .semibold))
                        .foregroundStyle(AppTheme.onBrand)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.clay)
            .disabled(viewModel.isSendingPasswordReset)
        }
    }

    // MARK: Confirmation

    private var sentContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.positive)
                .accessibilityHidden(true)

            Text(language.localized("Check your email", "Revisa tu correo"))
                .font(.poppins(.title3, .semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(
                language.localized(
                    "If an account exists for \(sentEmail), we sent a link to choose a new password. Check your spam folder. The link opens this app.",
                    "Si existe una cuenta para \(sentEmail), hemos enviado un enlace para elegir una nueva contraseña. Revisa la carpeta de spam. El enlace abre esta app."
                )
            )
            .font(.poppins(.subheadline))
            .foregroundStyle(AppTheme.inkSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            // Each request replaces the previous one on the server side of the flow.
            Text(
                language.localized(
                    "Only the link in the most recent email works.",
                    "Solo funciona el enlace del correo más reciente."
                )
            )
            .font(.poppins(.footnote))
            .foregroundStyle(AppTheme.inkSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                StatusBanner(text: errorText, icon: "exclamationmark.triangle.fill", tint: AppTheme.negative)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                // The cooldown lives in the view model so reopening the sheet cannot skip it.
                let availableAt = viewModel.passwordResetAvailableAt ?? .distantPast
                let remaining = Int(max(0, availableAt.timeIntervalSince(context.date)).rounded(.up))

                if remaining > 0 {
                    // A disabled bordered button dims its label to about 1.2:1 contrast on the medium
                    // sheet in light mode, so the countdown reads as plain text on a card instead.
                    Text(language.localized("Resend in \(remaining) s", "Reenviar en \(remaining) s"))
                        .font(.poppins(.body, .semibold))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppTheme.card))
                        .overlay(Capsule().stroke(AppTheme.hairline, lineWidth: 1))
                } else {
                    Button {
                        Task { await resend() }
                    } label: {
                        Group {
                            if viewModel.isSendingPasswordReset {
                                ProgressView()
                            } else if remaining > 0 {
                                Text(language.localized("Resend in \(remaining) s", "Reenviar en \(remaining) s"))
                            } else {
                                Text(language.localized("Resend link", "Reenviar enlace"))
                            }
                        }
                        .font(.poppins(.body, .semibold))
                        .foregroundStyle(remaining > 0 ? AppTheme.inkSecondary : AppTheme.clayText)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(AppTheme.clay)
                    .disabled(remaining > 0 || viewModel.isSendingPasswordReset)
                }
            }

            Button {
                errorText = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = .form
                }
            } label: {
                Text(language.localized("Use a different email", "Usar otro correo"))
                    .font(.poppins(.callout, .semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.clayText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    @MainActor
    private func send() async {
        emailFocused = false
        errorText = nil

        switch await viewModel.requestPasswordReset(email: email) {
        case .sent(let normalizedEmail):
            sentEmail = normalizedEmail
            withAnimation(.easeInOut(duration: 0.2)) {
                phase = .sent
            }
            AccessibilityNotification.Announcement(
                language.localized("Check your email", "Revisa tu correo")
            ).post()
        case .failed(let message):
            errorText = message
        }
    }

    @MainActor
    private func resend() async {
        errorText = nil

        switch await viewModel.requestPasswordReset(email: sentEmail) {
        case .sent:
            break
        case .failed(let message):
            errorText = message
        }
    }
}

// MARK: - Preview

#Preview {
    ForgotPasswordView(viewModel: AuthViewModel())
}
