import SwiftUI

struct TeamView: View {
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue

    @State private var employeeEmail = ""
    @State private var employeeRole: TeamInviteRole = .member
    @State private var organizationMembers: [OrganizationMemberSummary] = []
    @State private var pendingInvitations: [OrganizationInvitationSummary] = []
    @State private var isInvitingEmployee = false
    @State private var updatingMemberIDs: Set<UUID> = []
    @State private var updatingInvitationIDs: Set<UUID> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showingAccount = false
    @State private var showingSettings = false
    @State private var showingInviteComposer = false

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    var body: some View {
        NavigationStack {
            List {
                if roleAccessViewModel.hasOwnerAccess {
                    Section {
                        inviteToggleButton
                            .listRowBackground(Color.clear)

                        if showingInviteComposer {
                            inviteComposerCard
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        AppSectionHeader(language.localized("Invite Employee", "Invitar empleado"))
                    }
                }

                if !pendingInvitations.isEmpty {
                    Section {
                        ForEach(pendingInvitations) { invitation in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invitation.invitedEmail)
                                        .font(.poppins(.subheadline))
                                    Text(localizedRoleName(invitation.role))
                                        .font(.poppins(.caption))
                                        .foregroundStyle(AppTheme.inkSecondary)
                                }
                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    if roleAccessViewModel.hasAdminAccess {
                                        if updatingInvitationIDs.contains(invitation.id) {
                                            ProgressView()
                                        } else {
                                            Menu {
                                                ForEach(TeamInviteRole.allCases) { role in
                                                    Button(role.displayName(language: language)) {
                                                        Task {
                                                            await updatePendingInvitationRole(
                                                                invitation,
                                                                newRole: role
                                                            )
                                                        }
                                                    }
                                                }
                                            } label: {
                                                roleBadge(localizedRoleName(invitation.role), role: invitation.role)
                                            }
                                        }
                                    } else {
                                        roleBadge(localizedRoleName(invitation.role), role: invitation.role)
                                    }

                                    if let invitedAt = invitation.invitedAt {
                                        Text(invitedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.poppins(.caption2))
                                            .foregroundStyle(AppTheme.inkSecondary)
                                    }
                                }
                            }
                            .listRowBackground(AppTheme.card)
                        }
                    } header: {
                        AppSectionHeader(language.localized("Pending Invites", "Invitaciones pendientes"))
                    }
                }

                Section {
                    if organizationMembers.isEmpty {
                        Text(language.localized("No active employees yet.", "Aún no hay empleados activos."))
                            .font(.poppins(.body))
                            .foregroundStyle(AppTheme.inkSecondary)
                            .listRowBackground(AppTheme.card)
                    } else {
                        activeTeamCards
                            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 6, trailing: 4))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    AppSectionHeader(language.localized("Active Team", "Equipo activo"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.poppins(.footnote))
                            .foregroundStyle(AppTheme.negative)
                            .listRowBackground(AppTheme.card)
                    }
                }

                if let successMessage {
                    Section {
                        Text(successMessage)
                            .font(.poppins(.footnote))
                            .foregroundStyle(AppTheme.inkSecondary)
                            .listRowBackground(AppTheme.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(language.localized("Team", "Equipo"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    SettingsToolbarButton(language: language) {
                        showingSettings = true
                    }
                    AccountToolbarButton(language: language) {
                        showingAccount = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshData() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                    .accessibilityLabel(language.localized("Refresh", "Actualizar"))
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .sheet(isPresented: $showingAccount) {
                NavigationStack {
                    AccountView()
                }
            }
            .refreshable {
                await refreshData()
            }
            .task {
                await refreshData()
            }
        }
    }

    private var canSendInvite: Bool {
        !isInvitingEmployee && !employeeEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var memberCardColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 100), spacing: 14, alignment: .top)
        ]
    }

    private var inviteToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.24)) {
                showingInviteComposer.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.clay)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.clay.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.localized("Invite employee", "Invitar empleado"))
                        .font(.poppins(.headline))
                    Text(language.localized("Open invite composer", "Abrir formulario de invitación"))
                        .font(.poppins(.caption))
                        .foregroundStyle(AppTheme.inkSecondary)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkSecondary)
                    .rotationEffect(.degrees(showingInviteComposer ? 180 : 0))
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var inviteComposerCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(AppTheme.inkSecondary)
                    .frame(width: 18)

                TextField(
                    language.localized("Employee email", "Email del empleado"),
                    text: $employeeEmail
                )
                .font(.poppins(.callout, .medium))
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(language.localized("Role", "Rol"))
                        .font(.poppins(.caption, .semibold))
                        .foregroundStyle(AppTheme.inkSecondary)

                    VStack(spacing: 8) {
                        ForEach(TeamInviteRole.allCases) { role in
                            roleOptionButton(role)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                VStack {
                    Spacer(minLength: 0)

                    Button {
                        Task { await inviteEmployee() }
                    } label: {
                        Group {
                            if isInvitingEmployee {
                                ProgressView()
                                    .tint(.white)
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.headline.weight(.semibold))
                            }
                        }
                        .frame(width: 54, height: 54)
                        .background(Color.accentColor, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.92), lineWidth: 0.9)
                        )
                        .shadow(color: Color.black.opacity(0.14), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .disabled(!canSendInvite)
                    .opacity(canSendInvite ? 1 : 0.44)

                    Text(language.localized("Send", "Enviar"))
                        .font(.poppins(.caption2, .semibold))
                        .foregroundStyle(AppTheme.inkSecondary)

                    Spacer(minLength: 0)
                }
                .frame(width: 92)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [AppTheme.clay.opacity(0.12), AppTheme.olive.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func roleOptionButton(_ role: TeamInviteRole) -> some View {
        let isSelected = employeeRole == role
        Button {
            employeeRole = role
        } label: {
            HStack(spacing: 10) {
                Image(systemName: role.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : role.tintColor)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.22) : role.tintColor.opacity(0.16))
                    )

                Text(role.displayName(language: language))
                    .font(.poppins(.subheadline, .semibold))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.94))
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? role.fillColor : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private var activeTeamCards: some View {
        LazyVGrid(columns: memberCardColumns, alignment: .center, spacing: 14) {
            ForEach(organizationMembers) { member in
                memberFavoriteCard(member)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func memberFavoriteCard(_ member: OrganizationMemberSummary) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [memberAccentColor(member), memberAccentColor(member).opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(memberInitials(member))
                    .font(.poppins(.title3, .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 70, height: 70)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .overlay {
                if updatingMemberIDs.contains(member.userID) {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }
            }

            Text(memberDisplayName(member))
                .font(.poppins(.footnote, .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if roleAccessViewModel.hasAdminAccess, member.role.lowercased() != "owner" {
                Menu {
                    ForEach(TeamInviteRole.allCases) { role in
                        Button(role.displayName(language: language)) {
                            Task { await updateActiveMemberRole(member, newRole: role) }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(localizedRoleName(member.role))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.poppins(.caption, .semibold))
                    .foregroundStyle(roleColors(member.role).text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(roleColors(member.role).tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                roleBadge(localizedRoleName(member.role), role: member.role)
            }

            Text(member.memberState.capitalized)
                .font(.poppins(.caption2))
                .foregroundStyle(AppTheme.inkSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func memberDisplayName(_ member: OrganizationMemberSummary) -> String {
        let raw = member.emailOrID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = raw.firstIndex(of: "@") else {
            return raw.count > 12 ? "\(raw.prefix(12))…" : raw
        }

        let localPart = String(raw[..<atIndex])
        return localPart.isEmpty ? raw : localPart
    }

    private func memberInitials(_ member: OrganizationMemberSummary) -> String {
        let source = memberDisplayName(member)
        let components = source
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        if components.count >= 2 {
            let first = components[0].prefix(1)
            let second = components[1].prefix(1)
            return "\(first)\(second)".uppercased()
        }

        if let first = components.first {
            let chars = first.prefix(2)
            return chars.uppercased()
        }

        return "?"
    }

    private func memberAccentColor(_ member: OrganizationMemberSummary) -> Color {
        let palette = [
            AppTheme.oliveFill,
            AppTheme.clayFill,
            AppTheme.goldFill,
            AppTheme.oliveDeepFill,
            AppTheme.clayDeepFill,
            AppTheme.negativeFill
        ]
        let hash = abs(member.userID.uuidString.hashValue)
        return palette[hash % palette.count]
    }

    /// Brand tint (badge fill) and text color for a role badge: owner = clay, admin = olive,
    /// member = gold, viewer/unknown = neutral. Text uses the AA-safe clay and secondary ink.
    private func roleColors(_ rawRole: String) -> (tint: Color, text: Color) {
        if rawRole.lowercased() == "owner" {
            return (AppTheme.clay, AppTheme.clayText)
        }
        switch TeamInviteRole(rawCloudRole: rawRole) {
        case .admin?:
            return (AppTheme.olive, AppTheme.olive)
        case .member?:
            return (AppTheme.highlight, AppTheme.highlight)
        case .viewer?, nil:
            return (AppTheme.neutral, AppTheme.inkSecondary)
        }
    }

    private func roleBadge(_ text: String, role rawRole: String) -> some View {
        let colors = roleColors(rawRole)
        return Text(text)
            .font(.poppins(.caption, .semibold))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colors.tint.opacity(0.12), in: Capsule())
    }

    private func refreshData() async {
        guard roleAccessViewModel.canManageTeam else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await SupabaseSyncService.shared.fetchOwnerWorkspaceTeamSnapshot()
            organizationMembers = snapshot.members
            pendingInvitations = snapshot.invitations
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateActiveMemberRole(_ member: OrganizationMemberSummary, newRole: TeamInviteRole) async {
        let normalizedCurrentRole = member.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedCurrentRole != newRole.rawValue else { return }
        guard member.role.lowercased() != "owner" else { return }

        updatingMemberIDs.insert(member.userID)
        defer { updatingMemberIDs.remove(member.userID) }

        do {
            try await SupabaseSyncService.shared.updateWorkspaceMemberRole(
                memberUserID: member.userID,
                role: newRole.rawValue
            )
            successMessage = language.localized("Role updated.", "Rol actualizado.")
            errorMessage = nil
            await refreshData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updatePendingInvitationRole(_ invitation: OrganizationInvitationSummary, newRole: TeamInviteRole) async {
        let normalizedCurrentRole = invitation.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedCurrentRole != newRole.rawValue else { return }

        updatingInvitationIDs.insert(invitation.id)
        defer { updatingInvitationIDs.remove(invitation.id) }

        do {
            try await SupabaseSyncService.shared.updateWorkspaceInvitationRole(
                invitationID: invitation.id,
                role: newRole.rawValue
            )
            successMessage = language.localized("Pending role updated.", "Rol pendiente actualizado.")
            errorMessage = nil
            await refreshData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func inviteEmployee() async {
        isInvitingEmployee = true
        defer { isInvitingEmployee = false }

        do {
            try await SupabaseSyncService.shared.inviteEmployeeToOwnerWorkspace(
                email: employeeEmail,
                role: employeeRole.rawValue
            )
            employeeEmail = ""
            showingInviteComposer = false
            successMessage = language.localized("Invite sent.", "Invitación enviada.")
            errorMessage = nil
            await refreshData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func localizedRoleName(_ role: String) -> String {
        guard let mapped = TeamInviteRole(rawCloudRole: role) else {
            return role.capitalized
        }
        return mapped.displayName(language: language)
    }
}

private enum TeamInviteRole: String, CaseIterable, Identifiable {
    case admin
    case member
    case viewer

    var id: String { rawValue }

    init?(rawCloudRole: String) {
        self.init(rawValue: rawCloudRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .admin:
            return language.localized("Admin", "Administrador")
        case .member:
            return language.localized("Member", "Miembro")
        case .viewer:
            return language.localized("Viewer", "Lector")
        }
    }

    var iconName: String {
        switch self {
        case .admin:
            return "shield.lefthalf.filled"
        case .member:
            return "person.fill"
        case .viewer:
            return "eye.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .admin:
            return AppTheme.olive
        case .member:
            return AppTheme.highlight
        case .viewer:
            return AppTheme.neutral
        }
    }

    /// Solid version of `tintColor` for the selected state, which sits under white text.
    var fillColor: Color {
        switch self {
        case .admin:
            return AppTheme.oliveFill
        case .member:
            return AppTheme.goldFill
        case .viewer:
            return AppTheme.neutralFill
        }
    }
}
