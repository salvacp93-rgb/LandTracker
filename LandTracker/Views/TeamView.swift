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
                    Section(language.localized("Invite Employee", "Invitar empleado")) {
                        inviteToggleButton
                            .listRowBackground(Color.clear)

                        if showingInviteComposer {
                            inviteComposerCard
                                .listRowBackground(Color.clear)
                        }
                    }
                }

                if !pendingInvitations.isEmpty {
                    Section(language.localized("Pending Invites", "Invitaciones pendientes")) {
                        ForEach(pendingInvitations) { invitation in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invitation.invitedEmail)
                                        .font(.subheadline)
                                    Text(localizedRoleName(invitation.role))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                                                Text(localizedRoleName(invitation.role))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    } else {
                                        Text(localizedRoleName(invitation.role))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let invitedAt = invitation.invitedAt {
                                        Text(invitedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(language.localized("Active Team", "Equipo activo")) {
                    if organizationMembers.isEmpty {
                        Text(language.localized("No active employees yet.", "Aún no hay empleados activos."))
                            .foregroundStyle(.secondary)
                    } else {
                        activeTeamCards
                            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 6, trailing: 4))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let successMessage {
                    Section {
                        Text(successMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
                    .foregroundStyle(Color.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.localized("Invite employee", "Invitar empleado"))
                        .font(.headline)
                    Text(language.localized("Open invite composer", "Abrir formulario de invitación"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                TextField(
                    language.localized("Employee email", "Email del empleado"),
                    text: $employeeEmail
                )
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

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
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .frame(width: 92)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.14), Color.cyan.opacity(0.08)],
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
                    .font(.subheadline.weight(.semibold))

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
                    .fill(isSelected ? role.tintColor : Color.primary.opacity(0.06))
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
                            colors: [memberAccentColor(member).opacity(0.95), memberAccentColor(member).opacity(0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(memberInitials(member))
                    .font(.title3.weight(.bold))
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
                .font(.footnote.weight(.semibold))
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text(localizedRoleName(member.role))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(member.memberState.capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
        let hash = abs(member.userID.uuidString.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.62, brightness: 0.82)
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
            return Color(red: 0.79, green: 0.45, blue: 0.08)
        case .member:
            return Color(red: 0.18, green: 0.47, blue: 0.86)
        case .viewer:
            return Color(red: 0.31, green: 0.58, blue: 0.49)
        }
    }
}
