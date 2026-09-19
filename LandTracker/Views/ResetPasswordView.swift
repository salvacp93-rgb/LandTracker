import SwiftUI

/// Shown over the app after the user opens the reset link from their email. It cannot be swiped
/// away: the user either saves a new password or cancels, which signs the temporary session out.
struct ResetPasswordView: View {
    private enum Field: Hashable {
        case password
        case confirmation
    }

    @ObservedObject var viewModel: AuthViewModel
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var didAttemptSave = false
    @State private var serverError: String?
    @FocusState private var focusedField: Field?

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var canSubmit: Bool {
        !newPassword.isEmpty && !confirmPassword.isEmpty && !viewModel.isUpdatingPassword
    }

    /// Shown once the user has started confirming (or tried to save), so it never nags on an empty form.
    private var inlineValidationMessage: String? {
        guard didAttemptSave || !confirmPassword.isEmpty else { return nil }
        return viewModel.newPasswordValidationMessage(password: newPassword, confirmation: confirmPassword)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(
                            language.localized(
                                "Choose a new password for your account. When you save it, you will be signed in.",
                                "Elige una nueva contraseña para tu cuenta. Al guardarla, entrarás en la app."
                            )
                        )
                        .font(.poppins(.subheadline))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                        LoginCredentialField(
                            label: language.localized("New password", "Contraseña nueva"),
                            icon: "lock.fill"
                        ) {
                            SecureField(language.localized("New password", "Contraseña nueva"), text: $newPassword)
                                .textContentType(.newPassword)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .password)
                                .onSubmit {
                                    focusedField = .confirmation
                                }
                        }

                        Text(
                            language.localized(
                                "At least \(AuthViewModel.minimumPasswordLength) characters.",
                                "Mínimo \(AuthViewModel.minimumPasswordLength) caracteres."
                            )
                        )
                        .font(.poppins(.caption))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .padding(.top, -10)

                        LoginCredentialField(
                            label: language.localized("Confirm password", "Confirmar contraseña"),
                            icon: "lock.fill"
                        ) {
                            SecureField(language.localized("Confirm password", "Confirmar contraseña"), text: $confirmPassword)
                                .textContentType(.newPassword)
                                .submitLabel(.go)
                                .focused($focusedField, equals: .confirmation)
                                .onSubmit {
                                    Task { await save() }
                                }
                        }

                        if let message = inlineValidationMessage {
                            Text(message)
                                .font(.poppins(.footnote))
                                .foregroundStyle(AppTheme.negative)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, -10)
                        }

                        if let serverError {
                            StatusBanner(text: serverError, icon: "exclamationmark.triangle.fill", tint: AppTheme.negative)
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            if viewModel.isUpdatingPassword {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 2)
                            } else {
                                Text(language.localized("Save password", "Guardar contraseña"))
                                    .font(.poppins(.body, .semibold))
                                    .foregroundStyle(AppTheme.onBrand)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(AppTheme.clay)
                        .disabled(!canSubmit)

                        Button {
                            focusedField = nil
                            Task { await viewModel.cancelPasswordRecovery() }
                        } label: {
                            Text(language.localized("Cancel", "Cancelar"))
                                .font(.poppins(.callout, .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.clayText)
                        .disabled(viewModel.isUpdatingPassword)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(language.localized("New password", "Contraseña nueva"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: newPassword) { _, _ in
                serverError = nil
            }
            .onChange(of: confirmPassword) { _, _ in
                serverError = nil
            }
        }
    }

    @MainActor
    private func save() async {
        guard canSubmit else { return }
        didAttemptSave = true
        serverError = nil

        if viewModel.newPasswordValidationMessage(password: newPassword, confirmation: confirmPassword) != nil {
            return
        }

        focusedField = nil
        // On success the view model closes this sheet and opens the app signed in.
        serverError = await viewModel.updatePassword(newPassword)
    }
}

// MARK: - Preview

#Preview {
    ResetPasswordView(viewModel: AuthViewModel())
}
