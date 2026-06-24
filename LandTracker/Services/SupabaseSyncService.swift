import Foundation
import SwiftData
import Supabase

enum SupabaseSyncError: LocalizedError {
    case noActiveSession
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No hay una sesión activa para sincronizar."
        case .invalidInput(let message):
            return message
        }
    }
}

struct SpreadsheetSourceReference {
    let fileName: String
    let storagePath: String
    let fileHash: String
    let updatedAt: Date?
}

struct OrganizationMemberSummary: Identifiable {
    let userID: UUID
    let role: String
    let memberState: String
    let invitedEmail: String?

    var id: UUID { userID }

    var emailOrID: String {
        let email = invitedEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? userID.uuidString : email
    }
}

struct OrganizationInvitationSummary: Identifiable {
    let id: UUID
    let invitedEmail: String
    let role: String
    let state: String
    let invitedAt: Date?
}

private extension UUID {
    var serverLowercasedString: String {
        uuidString.lowercased()
    }
}

final class SupabaseSyncService {
    static let shared = SupabaseSyncService()

    private enum Constants {
        static let groupsTable = "land_groups"
        static let landsTable = "lands"
        static let historyTable = "land_history_entries"
        static let tasksTable = "land_tasks"
        static let pushDevicesTable = "push_devices"
        static let profilesTable = "profiles"
        static let spreadsheetSourcesTable = "spreadsheet_sources"
        static let organizationsTable = "organizations"
        static let organizationMembersTable = "organization_members"
        static let organizationInvitationsTable = "organization_invitations"
        static let profileImagesBucket = "profile-images"
        static let spreadsheetFilesBucket = "spreadsheet-files"
        static let initialSyncKeyPrefix = "sync.initial.completed."
        static let activeUserIDKey = "sync.active.user.id"
        static let lastSuccessfulSyncAtKey = "sync.last.successful.at"
    }

    private let authService = SupabaseAuthService.shared
    private let defaults = UserDefaults.standard

    private init() {}

    @MainActor
    func performStartupSync(context: ModelContext) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        let previousUserID = defaults.string(forKey: Constants.activeUserIDKey)
        if let previousUserID, previousUserID != user.id.uuidString {
            clearLocalCache(context: context)
        }
        defaults.set(user.id.uuidString, forKey: Constants.activeUserIDKey)
        await syncStoredPushToken(userID: user.id, organizationID: organizationID)

        try await processPendingOperations(context: context, userID: user.id, includeDelayed: true)
        let pendingOperations = (try? context.fetch(FetchDescriptor<PendingSyncOperation>())) ?? []
        if !pendingOperations.isEmpty {
            return
        }

        let initialSyncKey = "\(Constants.initialSyncKeyPrefix)\(user.id.uuidString)"

        let localGroups = try context.fetch(FetchDescriptor<LandGroup>())
        let localLands = try context.fetch(FetchDescriptor<Land>())
        let localHistory = try context.fetch(FetchDescriptor<LandHistoryEntry>())
        let localTasks = try context.fetch(FetchDescriptor<LandTask>())

        var remoteGroups = try await fetchRemoteGroups(organizationID: organizationID)
        var remoteLands = try await fetchRemoteLands(organizationID: organizationID)
        var remoteHistory = try await fetchRemoteHistory(organizationID: organizationID)
        var remoteTasks = try await fetchRemoteTasks(organizationID: organizationID)

        let hasCompletedInitialSync = defaults.bool(forKey: initialSyncKey)
        let remoteIsEmpty = remoteGroups.isEmpty && remoteLands.isEmpty && remoteHistory.isEmpty && remoteTasks.isEmpty
        let localHasData = !localGroups.isEmpty || !localLands.isEmpty || !localHistory.isEmpty || !localTasks.isEmpty

        if !hasCompletedInitialSync && remoteIsEmpty && localHasData {
            try await upsertGroups(localGroups, userID: user.id, organizationID: organizationID)
            try await upsertLands(localLands, userID: user.id, organizationID: organizationID)
            try await upsertHistoryEntries(localHistory, userID: user.id, organizationID: organizationID)
            try await upsertTasks(localTasks, userID: user.id, organizationID: organizationID)
        } else {
            try await pushLocalChanges(
                localGroups: localGroups,
                localLands: localLands,
                localHistory: localHistory,
                localTasks: localTasks,
                remoteGroups: remoteGroups,
                remoteLands: remoteLands,
                remoteHistory: remoteHistory,
                remoteTasks: remoteTasks,
                userID: user.id,
                organizationID: organizationID
            )
        }

        remoteGroups = try await fetchRemoteGroups(organizationID: organizationID)
        remoteLands = try await fetchRemoteLands(organizationID: organizationID)
        remoteHistory = try await fetchRemoteHistory(organizationID: organizationID)
        remoteTasks = try await fetchRemoteTasks(organizationID: organizationID)

        apply(
            remoteGroups: remoteGroups,
            remoteLands: remoteLands,
            remoteHistory: remoteHistory,
            remoteTasks: remoteTasks,
            to: context
        )
        try? context.save()
        await refreshTaskReminders(context: context)
        try await refreshProfileCacheFromCloud(fallbackEmail: user.email)
        try? await refreshSpreadsheetSourceCache()

        defaults.set(true, forKey: initialSyncKey)
        markSyncSuccess()
    }

    @MainActor
    func clearLocalCache(context: ModelContext) {
        TaskReminderService.shared.clearAllTaskReminders()

        if let tasks = try? context.fetch(FetchDescriptor<LandTask>()) {
            for task in tasks {
                context.delete(task)
            }
        }

        if let historyEntries = try? context.fetch(FetchDescriptor<LandHistoryEntry>()) {
            for entry in historyEntries {
                context.delete(entry)
            }
        }

        if let lands = try? context.fetch(FetchDescriptor<Land>()) {
            for land in lands {
                context.delete(land)
            }
        }

        if let groups = try? context.fetch(FetchDescriptor<LandGroup>()) {
            for group in groups {
                context.delete(group)
            }
        }

        if let operations = try? context.fetch(FetchDescriptor<PendingSyncOperation>()) {
            for operation in operations {
                context.delete(operation)
            }
        }

        try? context.save()
        defaults.removeObject(forKey: Constants.lastSuccessfulSyncAtKey)
        defaults.removeObject(forKey: AccountPreferences.accountTypeKey)
        defaults.removeObject(forKey: AccountPreferences.spreadsheetSourcePathKey)
        defaults.removeObject(forKey: AccountPreferences.spreadsheetSourceHashKey)
        defaults.removeObject(forKey: AccountPreferences.spreadsheetSourceFileNameKey)
        defaults.removeObject(forKey: AccountPreferences.spreadsheetSourceUpdatedAtKey)
        defaults.removeObject(forKey: AccountPreferences.spreadsheetLastProcessedHashKey)
        defaults.removeObject(forKey: AccountPreferences.spreadsheetLastProcessedAtKey)
    }

    @MainActor
    func queueLandUpsert(id: UUID, context: ModelContext) async {
        enqueueOperation(
            actionType: .upsert,
            entityType: .land,
            recordID: id,
            context: context
        )
        try? context.save()
        do {
            try await processPendingOperations(context: context)
        } catch {}
    }

    @MainActor
    func queueLandDelete(id: UUID, context: ModelContext) async {
        enqueueOperation(
            actionType: .delete,
            entityType: .land,
            recordID: id,
            context: context
        )
        try? context.save()
        do {
            try await processPendingOperations(context: context)
        } catch {}
    }

    @MainActor
    func queueGroupUpsert(id: UUID, context: ModelContext) async {
        enqueueOperation(
            actionType: .upsert,
            entityType: .group,
            recordID: id,
            context: context
        )
        try? context.save()
        do {
            try await processPendingOperations(context: context)
        } catch {}
    }

    @MainActor
    func queueGroupDelete(id: UUID, context: ModelContext) async {
        enqueueOperation(
            actionType: .delete,
            entityType: .group,
            recordID: id,
            context: context
        )
        try? context.save()
        do {
            try await processPendingOperations(context: context)
        } catch {}
    }

    @MainActor
    func queueHistoryEntryUpsert(id: UUID, context: ModelContext) async {
        enqueueOperation(
            actionType: .upsert,
            entityType: .historyEntry,
            recordID: id,
            context: context
        )
        try? context.save()
        do {
            try await processPendingOperations(context: context)
        } catch {}
    }

    @MainActor
    func queueHistoryEntryDelete(id: UUID, context: ModelContext) async {
        enqueueOperation(
            actionType: .delete,
            entityType: .historyEntry,
            recordID: id,
            context: context
        )
        try? context.save()
        do {
            try await processPendingOperations(context: context)
        } catch {}
    }

    @MainActor
    func queueTaskUpsert(id: UUID, context: ModelContext) async {
        enqueueOperation(
            actionType: .upsert,
            entityType: .task,
            recordID: id,
            context: context
        )
        try? context.save()
        do {
            try await processPendingOperations(context: context)
        } catch {}
    }

    @MainActor
    func queueTaskDelete(id: UUID, context: ModelContext) async {
        enqueueOperation(
            actionType: .delete,
            entityType: .task,
            recordID: id,
            context: context
        )
        try? context.save()
        do {
            try await processPendingOperations(context: context)
        } catch {}
    }

    @MainActor
    func queueAllLocalDataForSync(context: ModelContext) async {
        let groups = (try? context.fetch(FetchDescriptor<LandGroup>())) ?? []
        let lands = (try? context.fetch(FetchDescriptor<Land>())) ?? []
        let historyEntries = (try? context.fetch(FetchDescriptor<LandHistoryEntry>())) ?? []
        let tasks = (try? context.fetch(FetchDescriptor<LandTask>())) ?? []

        for group in groups {
            enqueueOperation(
                actionType: .upsert,
                entityType: .group,
                recordID: group.id,
                context: context
            )
        }

        for land in lands {
            enqueueOperation(
                actionType: .upsert,
                entityType: .land,
                recordID: land.id,
                context: context
            )
        }

        for entry in historyEntries where entry.source == .manual {
            enqueueOperation(
                actionType: .upsert,
                entityType: .historyEntry,
                recordID: entry.id,
                context: context
            )
        }

        for task in tasks {
            enqueueOperation(
                actionType: .upsert,
                entityType: .task,
                recordID: task.id,
                context: context
            )
        }

        try? context.save()
        do {
            try await processPendingOperations(context: context)
        } catch {}
    }

    @MainActor
    func retryPendingOperationsNow(context: ModelContext) async {
        do {
            try await processPendingOperations(context: context, includeDelayed: true)
        } catch {}
    }

    func lastSuccessfulSyncAt() -> Date? {
        defaults.object(forKey: Constants.lastSuccessfulSyncAtKey) as? Date
    }

    @MainActor
    func pushAllLocalData(context: ModelContext) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        let groups = try context.fetch(FetchDescriptor<LandGroup>())
        let lands = try context.fetch(FetchDescriptor<Land>())
        let historyEntries = try context.fetch(FetchDescriptor<LandHistoryEntry>())
        let tasks = try context.fetch(FetchDescriptor<LandTask>())
        try await upsertGroups(groups, userID: user.id, organizationID: organizationID)
        try await upsertLands(lands, userID: user.id, organizationID: organizationID)
        try await upsertHistoryEntries(historyEntries, userID: user.id, organizationID: organizationID)
        try await upsertTasks(tasks, userID: user.id, organizationID: organizationID)
        markSyncSuccess()
    }

    func upsertGroup(_ group: LandGroup) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await upsertGroup(group, userID: user.id, organizationID: organizationID)
    }

    func deleteGroup(id: UUID) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await deleteGroup(id: id, organizationID: organizationID)
    }

    func upsertLand(_ land: Land) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await upsertLand(land, userID: user.id, organizationID: organizationID)
    }

    func deleteLand(id: UUID) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await deleteLand(id: id, organizationID: organizationID)
    }

    func upsertHistoryEntry(_ entry: LandHistoryEntry) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await upsertHistoryEntry(entry, userID: user.id, organizationID: organizationID)
    }

    func deleteHistoryEntry(id: UUID) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await deleteHistoryEntry(id: id, organizationID: organizationID)
    }

    func upsertTask(_ task: LandTask) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await upsertTask(task, userID: user.id, organizationID: organizationID)
    }

    func deleteTask(id: UUID) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await deleteTask(id: id, organizationID: organizationID)
    }

    func upsertPushDeviceToken(_ token: String) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await upsertPushDeviceToken(token, userID: user.id, organizationID: organizationID)
    }

    func deletePushDeviceToken(_ token: String) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        try await deletePushDeviceToken(token, userID: user.id, organizationID: organizationID)
    }

    func fetchCurrentUserOrganizationRoles() async throws -> [String] {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        let memberships: [CloudOrganizationMemberRoleRecord] = try await authService.client
            .from(Constants.organizationMembersTable)
            .select("role,member_state")
            .eq("user_id", value: user.id.serverLowercasedString)
            .eq("organization_id", value: organizationID.uuidString)
            .eq("member_state", value: "active")
            .execute()
            .value

        return memberships.map(\.role)
    }

    func fetchOwnerWorkspaceMembers() async throws -> [OrganizationMemberSummary] {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        return try await fetchWorkspaceMembers(organizationID: organizationID)
    }

    func fetchOwnerWorkspaceInvitations() async throws -> [OrganizationInvitationSummary] {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)
        return try await fetchWorkspaceInvitations(organizationID: organizationID)
    }

    func fetchOwnerWorkspaceTeamSnapshot() async throws -> (
        members: [OrganizationMemberSummary],
        invitations: [OrganizationInvitationSummary]
    ) {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)

        async let membersTask = fetchWorkspaceMembers(organizationID: organizationID)
        async let invitationsTask = fetchWorkspaceInvitations(organizationID: organizationID)
        let (members, invitations) = try await (membersTask, invitationsTask)
        return (members: members, invitations: invitations)
    }

    func inviteEmployeeToOwnerWorkspace(email: String, role: String) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else {
            throw SupabaseSyncError.invalidInput("Introduce un email válido para invitar al empleado.")
        }

        let normalizedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["admin", "member", "viewer"].contains(normalizedRole) else {
            throw SupabaseSyncError.invalidInput("Rol de empleado no válido.")
        }

        try await authService.client
            .rpc(
                "invite_organization_employee",
                params: [
                    "p_organization_id": organizationID.uuidString,
                    "p_invited_email": normalizedEmail,
                    "p_role": normalizedRole
                ]
            )
            .execute()
    }

    func updateWorkspaceMemberRole(memberUserID: UUID, role: String) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)

        let normalizedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["admin", "member", "viewer"].contains(normalizedRole) else {
            throw SupabaseSyncError.invalidInput("Rol de empleado no válido.")
        }

        let payload = CloudOrganizationMemberRoleUpdatePayload(
            role: normalizedRole,
            updatedAt: Date()
        )

        try await authService.client
            .from(Constants.organizationMembersTable)
            .update(payload)
            .eq("organization_id", value: organizationID.uuidString)
            .eq("user_id", value: memberUserID.serverLowercasedString)
            .neq("role", value: "owner")
            .execute()
    }

    func updateWorkspaceInvitationRole(invitationID: UUID, role: String) async throws {
        let user = try await currentUser()
        let organizationID = try await currentWorkspaceOrganizationID(for: user.id)

        let normalizedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["admin", "member", "viewer"].contains(normalizedRole) else {
            throw SupabaseSyncError.invalidInput("Rol de invitación no válido.")
        }

        let payload = CloudOrganizationInvitationRoleUpdatePayload(
            role: normalizedRole,
            updatedAt: Date()
        )

        try await authService.client
            .from(Constants.organizationInvitationsTable)
            .update(payload)
            .eq("id", value: invitationID.uuidString)
            .eq("organization_id", value: organizationID.uuidString)
            .eq("state", value: "pending")
            .execute()
    }

    func upsertProfile(
        displayName: String,
        showIncomeInList: Bool,
        showSubtypeInList: Bool,
        profilePhotoPath: String?
    ) async throws {
        let user = try await currentUser()
        let payload = CloudProfilePayload(
            id: user.id.serverLowercasedString,
            email: user.email,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : displayName,
            showIncomeInList: showIncomeInList,
            showSubtypeInList: showSubtypeInList,
            profilePhotoPath: normalized(profilePhotoPath),
            updatedAt: Date()
        )
        try await authService.client
            .from(Constants.profilesTable)
            .upsert(payload, onConflict: "id")
            .execute()

        defaults.set(displayName, forKey: AccountPreferences.displayNameKey)
        defaults.set(showIncomeInList, forKey: AccountPreferences.showIncomeInListKey)
        defaults.set(showSubtypeInList, forKey: AccountPreferences.showSubtypeInListKey)
        defaults.set(normalized(profilePhotoPath) ?? "", forKey: AccountPreferences.profilePhotoPathKey)
    }

    func refreshProfileCacheFromCloud(fallbackEmail: String? = nil) async throws {
        let user = try await currentUser()
        let rows: [CloudProfileRecord] = try await authService.client
            .from(Constants.profilesTable)
            .select()
            .eq("id", value: user.id.serverLowercasedString)
            .limit(1)
            .execute()
            .value

        if let profile = rows.first {
            defaults.set(profile.displayName ?? "", forKey: AccountPreferences.displayNameKey)
            defaults.set(profile.showIncomeInList ?? true, forKey: AccountPreferences.showIncomeInListKey)
            defaults.set(profile.showSubtypeInList ?? true, forKey: AccountPreferences.showSubtypeInListKey)
            defaults.set(profile.profilePhotoPath ?? "", forKey: AccountPreferences.profilePhotoPathKey)
            defaults.set(profile.accountType ?? "individual", forKey: AccountPreferences.accountTypeKey)
            defaults.set(profile.email ?? fallbackEmail ?? user.email ?? "", forKey: AccountPreferences.cachedEmailKey)

            if let path = profile.profilePhotoPath, !path.isEmpty {
                if let imageData = try? await downloadProfileImage(path: path) {
                    await MainActor.run {
                        ProfileImageStore.shared.imageData = imageData
                    }
                }
            } else {
                await MainActor.run {
                    ProfileImageStore.shared.imageData = nil
                }
            }
            return
        }

        let showIncome = boolFromDefaults(key: AccountPreferences.showIncomeInListKey, defaultValue: true)
        let showSubtype = boolFromDefaults(key: AccountPreferences.showSubtypeInListKey, defaultValue: true)
        let displayName = defaults.string(forKey: AccountPreferences.displayNameKey) ?? ""
        let localPhotoPath = defaults.string(forKey: AccountPreferences.profilePhotoPathKey)
        if (localPhotoPath ?? "").isEmpty {
            await MainActor.run {
                ProfileImageStore.shared.imageData = nil
            }
        }

        try await upsertProfile(
            displayName: displayName,
            showIncomeInList: showIncome,
            showSubtypeInList: showSubtype,
            profilePhotoPath: localPhotoPath
        )

        if let fallbackEmail, !fallbackEmail.isEmpty {
            defaults.set(fallbackEmail, forKey: AccountPreferences.cachedEmailKey)
        } else if let userEmail = user.email {
            defaults.set(userEmail, forKey: AccountPreferences.cachedEmailKey)
        }

        if defaults.string(forKey: AccountPreferences.accountTypeKey)?.isEmpty ?? true {
            defaults.set("individual", forKey: AccountPreferences.accountTypeKey)
        }
    }

    func uploadProfileImage(_ data: Data) async throws -> String {
        let user = try await currentUser()
        let path = profileImagePath(for: user.id)

        _ = try await authService.client.storage
            .from(Constants.profileImagesBucket)
            .upload(
                path,
                data: data,
                options: FileOptions(
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        defaults.set(path, forKey: AccountPreferences.profilePhotoPathKey)
        await MainActor.run {
            ProfileImageStore.shared.imageData = data
        }
        return path
    }

    func removeProfileImage() async throws {
        let user = try await currentUser()
        let path = profileImagePath(for: user.id)

        _ = try? await authService.client.storage
            .from(Constants.profileImagesBucket)
            .remove(paths: [path])

        defaults.set("", forKey: AccountPreferences.profilePhotoPathKey)
        await MainActor.run {
            ProfileImageStore.shared.imageData = nil
        }
    }

    func uploadSpreadsheetFile(_ data: Data, fileName: String) async throws -> String {
        let user = try await currentUser()
        let normalizedName = sanitizeFileName(fileName)
        let path = "\(user.id.uuidString)/\(UUID().uuidString)-\(normalizedName)"

        let contentType: String
        if normalizedName.lowercased().hasSuffix(".csv") {
            contentType = "text/csv"
        } else {
            contentType = "application/octet-stream"
        }

        _ = try await authService.client.storage
            .from(Constants.spreadsheetFilesBucket)
            .upload(
                path,
                data: data,
                options: FileOptions(
                    contentType: contentType,
                    upsert: true
                )
            )
        return path
    }

    func downloadSpreadsheetFile(path: String) async throws -> Data {
        try await authService.client.storage
            .from(Constants.spreadsheetFilesBucket)
            .download(path: path)
    }

    func upsertSpreadsheetSource(fileName: String, storagePath: String, fileHash: String) async throws {
        let user = try await currentUser()
        let payload = CloudSpreadsheetSourcePayload(
            userID: user.id.serverLowercasedString,
            fileName: fileName,
            storagePath: storagePath,
            fileHash: fileHash,
            updatedAt: Date()
        )

        try await authService.client
            .from(Constants.spreadsheetSourcesTable)
            .upsert(payload, onConflict: "user_id")
            .execute()

        defaults.set(fileName, forKey: AccountPreferences.spreadsheetSourceFileNameKey)
        defaults.set(storagePath, forKey: AccountPreferences.spreadsheetSourcePathKey)
        defaults.set(fileHash, forKey: AccountPreferences.spreadsheetSourceHashKey)
        defaults.set(Date().timeIntervalSince1970, forKey: AccountPreferences.spreadsheetSourceUpdatedAtKey)
    }

    func refreshSpreadsheetSourceCache() async throws {
        let user = try await currentUser()
        let rows: [CloudSpreadsheetSourceRecord] = try await authService.client
            .from(Constants.spreadsheetSourcesTable)
            .select()
            .eq("user_id", value: user.id.serverLowercasedString)
            .limit(1)
            .execute()
            .value

        guard let source = rows.first else {
            defaults.removeObject(forKey: AccountPreferences.spreadsheetSourceFileNameKey)
            defaults.removeObject(forKey: AccountPreferences.spreadsheetSourcePathKey)
            defaults.removeObject(forKey: AccountPreferences.spreadsheetSourceHashKey)
            defaults.removeObject(forKey: AccountPreferences.spreadsheetSourceUpdatedAtKey)
            return
        }

        defaults.set(source.fileName, forKey: AccountPreferences.spreadsheetSourceFileNameKey)
        defaults.set(source.storagePath, forKey: AccountPreferences.spreadsheetSourcePathKey)
        defaults.set(source.fileHash, forKey: AccountPreferences.spreadsheetSourceHashKey)
        if let updatedAt = source.updatedAt {
            defaults.set(updatedAt.timeIntervalSince1970, forKey: AccountPreferences.spreadsheetSourceUpdatedAtKey)
        } else {
            defaults.removeObject(forKey: AccountPreferences.spreadsheetSourceUpdatedAtKey)
        }
    }

    func spreadsheetSourceFromCache() -> SpreadsheetSourceReference? {
        guard
            let fileName = defaults.string(forKey: AccountPreferences.spreadsheetSourceFileNameKey),
            let storagePath = defaults.string(forKey: AccountPreferences.spreadsheetSourcePathKey),
            let fileHash = defaults.string(forKey: AccountPreferences.spreadsheetSourceHashKey),
            !fileName.isEmpty,
            !storagePath.isEmpty,
            !fileHash.isEmpty
        else {
            return nil
        }

        return SpreadsheetSourceReference(
            fileName: fileName,
            storagePath: storagePath,
            fileHash: fileHash,
            updatedAt: {
                let timestamp = defaults.double(forKey: AccountPreferences.spreadsheetSourceUpdatedAtKey)
                guard timestamp > 0 else { return nil }
                return Date(timeIntervalSince1970: timestamp)
            }()
        )
    }

    private func currentUser() async throws -> User {
        guard let session = try await authService.currentSession(), !session.isExpired else {
            throw SupabaseSyncError.noActiveSession
        }
        return session.user
    }

    private func currentPersonalOrganizationID(for userID: UUID) async throws -> UUID? {
        let rows: [CloudOrganizationIDRecord] = try await authService.client
            .from(Constants.organizationsTable)
            .select("id")
            .eq("owner_user_id", value: userID.serverLowercasedString)
            .eq("is_personal", value: true)
            .limit(1)
            .execute()
            .value

        return rows.first?.id
    }

    private func currentWorkspaceOrganizationID(for userID: UUID) async throws -> UUID {
        let personalOrganizationID = try await currentPersonalOrganizationID(for: userID)
        let membershipRows: [CloudOrganizationMemberOrganizationRecord] = try await authService.client
            .from(Constants.organizationMembersTable)
            .select("organization_id,member_state,created_at")
            .eq("user_id", value: userID.serverLowercasedString)
            .eq("member_state", value: "active")
            .order("created_at", ascending: true)
            .execute()
            .value

        if let personalOrganizationID,
           let sharedOrganization = membershipRows.first(where: { $0.organizationID != personalOrganizationID }) {
            return sharedOrganization.organizationID
        }

        if let personalOrganizationID {
            return personalOrganizationID
        }

        guard let fallbackOrganizationID = membershipRows.first?.organizationID else {
            throw SupabaseSyncError.invalidInput("No se encontró organización activa para este usuario.")
        }

        return fallbackOrganizationID
    }

    private func fetchWorkspaceMembers(organizationID: UUID) async throws -> [OrganizationMemberSummary] {
        let rows: [CloudOrganizationMembershipRecord] = try await authService.client
            .from(Constants.organizationMembersTable)
            .select("user_id,role,member_state,invited_email")
            .eq("organization_id", value: organizationID.uuidString)
            .execute()
            .value

        return rows.map { row in
            OrganizationMemberSummary(
                userID: row.userID,
                role: row.role,
                memberState: row.memberState ?? "active",
                invitedEmail: row.invitedEmail
            )
        }
    }

    private func fetchWorkspaceInvitations(organizationID: UUID) async throws -> [OrganizationInvitationSummary] {
        let rows: [CloudOrganizationInvitationRecord] = try await authService.client
            .from(Constants.organizationInvitationsTable)
            .select("id,invited_email,role,state,invited_at")
            .eq("organization_id", value: organizationID.uuidString)
            .eq("state", value: "pending")
            .execute()
            .value

        return rows.map { row in
            OrganizationInvitationSummary(
                id: row.id,
                invitedEmail: row.invitedEmail,
                role: row.role,
                state: row.state,
                invitedAt: row.invitedAt
            )
        }
    }

    private func fetchRemoteGroups(organizationID: UUID) async throws -> [CloudGroupRecord] {
        try await authService.client
            .from(Constants.groupsTable)
            .select()
            .eq("organization_id", value: organizationID.uuidString)
            .execute()
            .value
    }

    private func fetchRemoteLands(organizationID: UUID) async throws -> [CloudLandRecord] {
        try await authService.client
            .from(Constants.landsTable)
            .select()
            .eq("organization_id", value: organizationID.uuidString)
            .execute()
            .value
    }

    private func fetchRemoteHistory(organizationID: UUID) async throws -> [CloudHistoryRecord] {
        try await authService.client
            .from(Constants.historyTable)
            .select()
            .eq("organization_id", value: organizationID.uuidString)
            .execute()
            .value
    }

    private func fetchRemoteTasks(organizationID: UUID) async throws -> [CloudTaskRecord] {
        try await authService.client
            .from(Constants.tasksTable)
            .select()
            .eq("organization_id", value: organizationID.uuidString)
            .execute()
            .value
    }

    private func upsertGroups(_ groups: [LandGroup], userID: UUID, organizationID: UUID) async throws {
        guard !groups.isEmpty else { return }
        let payload = groups.map { CloudGroupPayload(group: $0, userID: userID, organizationID: organizationID) }
        try await authService.client
            .from(Constants.groupsTable)
            .upsert(payload, onConflict: "id")
            .execute()
    }

    private func upsertLands(_ lands: [Land], userID: UUID, organizationID: UUID) async throws {
        guard !lands.isEmpty else { return }
        for land in lands {
            if let group = land.group {
                try await upsertGroup(group, userID: userID, organizationID: organizationID)
            }
        }

        let payload = lands.map { CloudLandPayload(land: $0, userID: userID, organizationID: organizationID) }
        try await authService.client
            .from(Constants.landsTable)
            .upsert(payload, onConflict: "id")
            .execute()
    }

    private func upsertHistoryEntries(_ entries: [LandHistoryEntry], userID: UUID, organizationID: UUID) async throws {
        let manualEntries = entries.filter { $0.source == .manual }
        guard !manualEntries.isEmpty else { return }

        for entry in manualEntries {
            if let land = entry.land, let group = land.group {
                try await upsertGroup(group, userID: userID, organizationID: organizationID)
            }
            if let land = entry.land {
                try await upsertLand(land, userID: userID, organizationID: organizationID)
            }
        }

        let payload = manualEntries.compactMap {
            CloudHistoryPayload(entry: $0, userID: userID, organizationID: organizationID)
        }
        guard !payload.isEmpty else { return }
        try await authService.client
            .from(Constants.historyTable)
            .upsert(payload, onConflict: "id")
            .execute()
    }

    private func upsertTasks(_ tasks: [LandTask], userID: UUID, organizationID: UUID) async throws {
        guard !tasks.isEmpty else { return }

        var syncedLandIDs: Set<UUID> = []
        for task in tasks {
            guard let land = task.land else { continue }
            guard !syncedLandIDs.contains(land.id) else { continue }
            try await upsertLand(land, userID: userID, organizationID: organizationID)
            syncedLandIDs.insert(land.id)
        }

        let payload = tasks.compactMap { CloudTaskPayload(task: $0, userID: userID, organizationID: organizationID) }
        guard !payload.isEmpty else { return }
        try await authService.client
            .from(Constants.tasksTable)
            .upsert(payload, onConflict: "id")
            .execute()
    }

    private func pushLocalChanges(
        localGroups: [LandGroup],
        localLands: [Land],
        localHistory: [LandHistoryEntry],
        localTasks: [LandTask],
        remoteGroups: [CloudGroupRecord],
        remoteLands: [CloudLandRecord],
        remoteHistory: [CloudHistoryRecord],
        remoteTasks: [CloudTaskRecord],
        userID: UUID,
        organizationID: UUID
    ) async throws {
        let remoteGroupIDs = Set(remoteGroups.map(\.id))
        for group in localGroups where !remoteGroupIDs.contains(group.id) {
            try await upsertGroup(group, userID: userID, organizationID: organizationID)
        }

        let remoteLandsByID = Dictionary(uniqueKeysWithValues: remoteLands.map { ($0.id, $0) })
        for localLand in localLands {
            guard let remote = remoteLandsByID[localLand.id] else {
                try await upsertLand(localLand, userID: userID, organizationID: organizationID)
                continue
            }

            let remoteUpdatedAt = remote.updatedAt ?? .distantPast
            if localLand.updatedAt > remoteUpdatedAt {
                try await upsertLand(localLand, userID: userID, organizationID: organizationID)
            }
        }

        let remoteHistoryByID = Dictionary(uniqueKeysWithValues: remoteHistory.map { ($0.id, $0) })
        for localEntry in localHistory where localEntry.source == .manual {
            guard let remote = remoteHistoryByID[localEntry.id] else {
                try await upsertHistoryEntry(localEntry, userID: userID, organizationID: organizationID)
                continue
            }

            let remoteUpdatedAt = remote.updatedAt ?? .distantPast
            if localEntry.updatedAt > remoteUpdatedAt {
                try await upsertHistoryEntry(localEntry, userID: userID, organizationID: organizationID)
            }
        }

        let remoteTasksByID = Dictionary(uniqueKeysWithValues: remoteTasks.map { ($0.id, $0) })
        for localTask in localTasks {
            guard let remote = remoteTasksByID[localTask.id] else {
                try await upsertTask(localTask, userID: userID, organizationID: organizationID)
                continue
            }

            let remoteUpdatedAt = remote.updatedAt ?? .distantPast
            if localTask.updatedAt > remoteUpdatedAt {
                try await upsertTask(localTask, userID: userID, organizationID: organizationID)
            }
        }
    }

    @MainActor
    private func apply(
        remoteGroups: [CloudGroupRecord],
        remoteLands: [CloudLandRecord],
        remoteHistory: [CloudHistoryRecord],
        remoteTasks: [CloudTaskRecord],
        to context: ModelContext
    ) {
        var localGroupsByID: [UUID: LandGroup] = [:]
        if let localGroups = try? context.fetch(FetchDescriptor<LandGroup>()) {
            for group in localGroups {
                localGroupsByID[group.id] = group
            }
        }

        for remoteGroup in remoteGroups {
            if let existing = localGroupsByID[remoteGroup.id] {
                existing.name = remoteGroup.name
                existing.colorHex = remoteGroup.colorHex
                if let createdAt = remoteGroup.createdAt {
                    existing.createdAt = createdAt
                }
            } else {
                let group = LandGroup(name: remoteGroup.name, colorHex: remoteGroup.colorHex)
                group.id = remoteGroup.id
                if let createdAt = remoteGroup.createdAt {
                    group.createdAt = createdAt
                }
                context.insert(group)
                localGroupsByID[group.id] = group
            }
        }

        var localLandsByID: [UUID: Land] = [:]
        if let localLands = try? context.fetch(FetchDescriptor<Land>()) {
            for land in localLands {
                localLandsByID[land.id] = land
            }
        }

        for remoteLand in remoteLands {
            let linkedGroup = remoteLand.groupID.flatMap { localGroupsByID[$0] }

            if let existing = localLandsByID[remoteLand.id] {
                existing.name = remoteLand.name
                existing.latitude = remoteLand.latitude
                existing.longitude = remoteLand.longitude
                existing.sizeAcres = remoteLand.sizeAcres
                existing.activityType = remoteLand.activityType ?? ActivityCatalog.defaultName
                existing.productionType = remoteLand.productionType
                existing.productionSubtype = remoteLand.productionSubtype ?? ""
                existing.incomeAnnual = remoteLand.incomeAnnual
                existing.annualIrrigationCost = remoteLand.annualIrrigationCost ?? 0
                existing.annualFertilizerCost = remoteLand.annualFertilizerCost ?? 0
                existing.annualLaborCost = remoteLand.annualLaborCost ?? 0
                existing.annualMaintenanceCost = remoteLand.annualMaintenanceCost ?? 0
                existing.notes = remoteLand.notes ?? ""
                existing.installedCapacityKW = remoteLand.installedCapacityKW ?? 0
                existing.annualElectricityProductionKWh = remoteLand.annualElectricityProductionKWh ?? 0
                existing.selfConsumptionRate = remoteLand.selfConsumptionRate ?? 0
                existing.gridExportRate = remoteLand.gridExportRate ?? 0
                existing.catastroRefcat14 = remoteLand.catastroRefcat14
                existing.catastroAreaValue = remoteLand.catastroAreaValue
                existing.catastroAreaUom = remoteLand.catastroAreaUom
                existing.catastroLabel = remoteLand.catastroLabel
                existing.catastroRings = remoteLand.catastroRings ?? []
                existing.catastroFetchedAt = remoteLand.catastroFetchedAt
                existing.group = linkedGroup
                if let createdAt = remoteLand.createdAt {
                    existing.createdAt = createdAt
                }
                if let updatedAt = remoteLand.updatedAt {
                    existing.updatedAt = updatedAt
                }
            } else {
                let land = Land(
                    name: remoteLand.name,
                    latitude: remoteLand.latitude,
                    longitude: remoteLand.longitude,
                    sizeAcres: remoteLand.sizeAcres,
                    activityType: remoteLand.activityType ?? ActivityCatalog.defaultName,
                    productionType: remoteLand.productionType,
                    productionSubtype: remoteLand.productionSubtype ?? "",
                    incomeAnnual: remoteLand.incomeAnnual,
                    annualIrrigationCost: remoteLand.annualIrrigationCost ?? 0,
                    annualFertilizerCost: remoteLand.annualFertilizerCost ?? 0,
                    annualLaborCost: remoteLand.annualLaborCost ?? 0,
                    annualMaintenanceCost: remoteLand.annualMaintenanceCost ?? 0,
                    notes: remoteLand.notes ?? "",
                    installedCapacityKW: remoteLand.installedCapacityKW ?? 0,
                    annualElectricityProductionKWh: remoteLand.annualElectricityProductionKWh ?? 0,
                    selfConsumptionRate: remoteLand.selfConsumptionRate ?? 0,
                    gridExportRate: remoteLand.gridExportRate ?? 0,
                    catastroRefcat14: remoteLand.catastroRefcat14,
                    catastroAreaValue: remoteLand.catastroAreaValue,
                    catastroAreaUom: remoteLand.catastroAreaUom,
                    catastroLabel: remoteLand.catastroLabel,
                    catastroRings: remoteLand.catastroRings ?? [],
                    catastroFetchedAt: remoteLand.catastroFetchedAt,
                    group: linkedGroup
                )
                land.id = remoteLand.id
                land.createdAt = remoteLand.createdAt ?? Date()
                land.updatedAt = remoteLand.updatedAt ?? Date()
                context.insert(land)
                localLandsByID[land.id] = land
            }
        }

        var localHistoryByID: [UUID: LandHistoryEntry] = [:]
        if let localHistory = try? context.fetch(FetchDescriptor<LandHistoryEntry>()) {
            for entry in localHistory {
                localHistoryByID[entry.id] = entry
            }
        }

        for remoteEntry in remoteHistory {
            guard let linkedLand = localLandsByID[remoteEntry.landID] else { continue }

            if let existing = localHistoryByID[remoteEntry.id] {
                existing.year = remoteEntry.year
                existing.month = remoteEntry.month
                existing.incomeAmount = remoteEntry.incomeAmount
                existing.productionAmount = remoteEntry.productionAmount
                existing.productionUnit = remoteEntry.productionUnit
                existing.electricityKWh = remoteEntry.electricityKWh
                existing.notes = remoteEntry.notes ?? ""
                existing.source = .manual
                existing.land = linkedLand
                if let createdAt = remoteEntry.createdAt {
                    existing.createdAt = createdAt
                }
                if let updatedAt = remoteEntry.updatedAt {
                    existing.updatedAt = updatedAt
                }
            } else {
                let entry = LandHistoryEntry(
                    year: remoteEntry.year,
                    month: remoteEntry.month,
                    incomeAmount: remoteEntry.incomeAmount,
                    productionAmount: remoteEntry.productionAmount,
                    productionUnit: remoteEntry.productionUnit,
                    electricityKWh: remoteEntry.electricityKWh,
                    notes: remoteEntry.notes ?? "",
                    source: .manual,
                    land: linkedLand,
                    createdAt: remoteEntry.createdAt ?? Date()
                )
                entry.id = remoteEntry.id
                entry.updatedAt = remoteEntry.updatedAt ?? Date()
                context.insert(entry)
                localHistoryByID[entry.id] = entry
            }
        }

        var localTasksByID: [UUID: LandTask] = [:]
        if let localTasks = try? context.fetch(FetchDescriptor<LandTask>()) {
            for task in localTasks {
                localTasksByID[task.id] = task
            }
        }

        for remoteTask in remoteTasks {
            guard let linkedLand = localLandsByID[remoteTask.landID] else { continue }

            let taskType = LandTaskType(rawValue: remoteTask.typeRaw ?? "") ?? .other
            let taskNotes = remoteTask.notes ?? ""
            let taskIsCompleted = remoteTask.isCompleted ?? false
            let taskCompletedAt = taskIsCompleted ? remoteTask.completedAt : nil

            if let existing = localTasksByID[remoteTask.id] {
                existing.type = taskType
                existing.title = remoteTask.title
                existing.dueDate = remoteTask.dueDate
                existing.reminderDate = remoteTask.reminderDate
                existing.notes = taskNotes
                existing.isCompleted = taskIsCompleted
                existing.completedAt = taskCompletedAt
                existing.land = linkedLand
                if let createdAt = remoteTask.createdAt {
                    existing.createdAt = createdAt
                }
                if let updatedAt = remoteTask.updatedAt {
                    existing.updatedAt = updatedAt
                }
            } else {
                let task = LandTask(
                    type: taskType,
                    title: remoteTask.title,
                    dueDate: remoteTask.dueDate,
                    reminderDate: remoteTask.reminderDate,
                    notes: taskNotes,
                    isCompleted: taskIsCompleted,
                    completedAt: taskCompletedAt,
                    land: linkedLand,
                    createdAt: remoteTask.createdAt ?? Date()
                )
                task.id = remoteTask.id
                task.updatedAt = remoteTask.updatedAt ?? Date()
                context.insert(task)
                localTasksByID[task.id] = task
            }
        }
    }

    @MainActor
    private func processPendingOperations(
        context: ModelContext,
        userID: UUID? = nil,
        includeDelayed: Bool = false
    ) async throws {
        let resolvedUserID: UUID
        if let userID {
            resolvedUserID = userID
        } else {
            resolvedUserID = try await currentUser().id
        }
        let organizationID = try await currentWorkspaceOrganizationID(for: resolvedUserID)

        let now = Date()
        let operations = ((try? context.fetch(FetchDescriptor<PendingSyncOperation>())) ?? [])
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }

        var hasFailures = false
        var processedAny = false

        for operation in operations {
            if !includeDelayed, let nextRetryAt = operation.nextRetryAt, nextRetryAt > now {
                continue
            }

            do {
                processedAny = true
                switch (operation.entityType, operation.actionType) {
                case (.land, .upsert):
                    let localLand = try context
                        .fetch(FetchDescriptor<Land>())
                        .first(where: { $0.id == operation.recordID })
                    guard let localLand else {
                        context.delete(operation)
                        continue
                    }
                    try await upsertLand(localLand, userID: resolvedUserID, organizationID: organizationID)

                case (.land, .delete):
                    try await deleteLand(id: operation.recordID, organizationID: organizationID)

                case (.group, .upsert):
                    let localGroup = try context
                        .fetch(FetchDescriptor<LandGroup>())
                        .first(where: { $0.id == operation.recordID })
                    guard let localGroup else {
                        context.delete(operation)
                        continue
                    }
                    try await upsertGroup(localGroup, userID: resolvedUserID, organizationID: organizationID)

                case (.group, .delete):
                    try await deleteGroup(id: operation.recordID, organizationID: organizationID)

                case (.historyEntry, .upsert):
                    let localEntry = try context
                        .fetch(FetchDescriptor<LandHistoryEntry>())
                        .first(where: { $0.id == operation.recordID })
                    guard let localEntry else {
                        context.delete(operation)
                        continue
                    }
                    guard localEntry.source == .manual else {
                        context.delete(operation)
                        continue
                    }
                    try await upsertHistoryEntry(localEntry, userID: resolvedUserID, organizationID: organizationID)

                case (.historyEntry, .delete):
                    try await deleteHistoryEntry(id: operation.recordID, organizationID: organizationID)

                case (.task, .upsert):
                    let localTask = try context
                        .fetch(FetchDescriptor<LandTask>())
                        .first(where: { $0.id == operation.recordID })
                    guard let localTask else {
                        context.delete(operation)
                        continue
                    }
                    try await upsertTask(localTask, userID: resolvedUserID, organizationID: organizationID)

                case (.task, .delete):
                    try await deleteTask(id: operation.recordID, organizationID: organizationID)
                }

                operation.markSuccess()
                context.delete(operation)
            } catch {
                hasFailures = true
                operation.markRetry(error: error.localizedDescription)
            }
        }

        try? context.save()

        if processedAny && !hasFailures {
            markSyncSuccess()
        }
    }

    @MainActor
    private func enqueueOperation(
        actionType: PendingSyncActionType,
        entityType: PendingSyncEntityType,
        recordID: UUID,
        context: ModelContext
    ) {
        let existing = ((try? context.fetch(FetchDescriptor<PendingSyncOperation>())) ?? [])
            .filter {
                $0.entityType == entityType &&
                $0.recordID == recordID
            }

        switch actionType {
        case .delete:
            for item in existing {
                context.delete(item)
            }
            context.insert(
                PendingSyncOperation(
                    entityType: entityType,
                    actionType: .delete,
                    recordID: recordID
                )
            )

        case .upsert:
            if let existingUpsert = existing.first(where: { $0.actionType == .upsert }) {
                existingUpsert.updatedAt = Date()
                existingUpsert.nextRetryAt = nil
                existingUpsert.lastError = nil
                return
            }

            for item in existing where item.actionType == .delete {
                context.delete(item)
            }

            context.insert(
                PendingSyncOperation(
                    entityType: entityType,
                    actionType: .upsert,
                    recordID: recordID
                )
            )
        }
    }

    private func markSyncSuccess(at date: Date = Date()) {
        defaults.set(date, forKey: Constants.lastSuccessfulSyncAtKey)
    }

    @MainActor
    private func refreshTaskReminders(context: ModelContext) async {
        let tasks = (try? context.fetch(FetchDescriptor<LandTask>())) ?? []
        let languageRaw = defaults.string(forKey: AccountPreferences.appLanguageKey) ?? AppSettings.defaultLanguage.rawValue
        let language = AppSettings.language(from: languageRaw)
        await TaskReminderService.shared.syncReminders(for: tasks, language: language)
    }

    @MainActor
    private func syncStoredPushToken(userID: UUID, organizationID: UUID) async {
        guard let token = defaults.string(forKey: AccountPreferences.pushDeviceTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return
        }
        try? await upsertPushDeviceToken(token, userID: userID, organizationID: organizationID)
    }

    private func profileImagePath(for userID: UUID) -> String {
        "\(userID.uuidString)/avatar.jpg"
    }

    private func downloadProfileImage(path: String) async throws -> Data {
        try await authService.client.storage
            .from(Constants.profileImagesBucket)
            .download(path: path)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sanitizeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = value.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
        return sanitized.isEmpty ? "dataset.csv" : sanitized
    }

    private func boolFromDefaults(key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private func upsertGroup(_ group: LandGroup, userID: UUID, organizationID: UUID) async throws {
        let payload = CloudGroupPayload(group: group, userID: userID, organizationID: organizationID)
        try await authService.client
            .from(Constants.groupsTable)
            .upsert(payload, onConflict: "id")
            .execute()
    }

    private func deleteGroup(id: UUID, organizationID: UUID) async throws {
        try await authService.client
            .from(Constants.groupsTable)
            .delete()
            .eq("id", value: id.uuidString)
            .eq("organization_id", value: organizationID.uuidString)
            .execute()
    }

    private func upsertLand(_ land: Land, userID: UUID, organizationID: UUID) async throws {
        if let group = land.group {
            try await upsertGroup(group, userID: userID, organizationID: organizationID)
        }
        let payload = CloudLandPayload(land: land, userID: userID, organizationID: organizationID)
        try await authService.client
            .from(Constants.landsTable)
            .upsert(payload, onConflict: "id")
            .execute()
    }

    private func upsertHistoryEntry(_ entry: LandHistoryEntry, userID: UUID, organizationID: UUID) async throws {
        guard entry.source == .manual else { return }
        guard let payload = CloudHistoryPayload(entry: entry, userID: userID, organizationID: organizationID) else { return }
        if let land = entry.land, let group = land.group {
            try await upsertGroup(group, userID: userID, organizationID: organizationID)
        }
        if let land = entry.land {
            try await upsertLand(land, userID: userID, organizationID: organizationID)
        }
        try await authService.client
            .from(Constants.historyTable)
            .upsert(payload, onConflict: "id")
            .execute()
    }

    private func deleteLand(id: UUID, organizationID: UUID) async throws {
        try await authService.client
            .from(Constants.landsTable)
            .delete()
            .eq("id", value: id.uuidString)
            .eq("organization_id", value: organizationID.uuidString)
            .execute()
    }

    private func deleteHistoryEntry(id: UUID, organizationID: UUID) async throws {
        try await authService.client
            .from(Constants.historyTable)
            .delete()
            .eq("id", value: id.uuidString)
            .eq("organization_id", value: organizationID.uuidString)
            .execute()
    }

    private func upsertTask(_ task: LandTask, userID: UUID, organizationID: UUID) async throws {
        guard let payload = CloudTaskPayload(task: task, userID: userID, organizationID: organizationID) else { return }
        if let land = task.land, let group = land.group {
            try await upsertGroup(group, userID: userID, organizationID: organizationID)
        }
        if let land = task.land {
            try await upsertLand(land, userID: userID, organizationID: organizationID)
        }
        try await authService.client
            .from(Constants.tasksTable)
            .upsert(payload, onConflict: "id")
            .execute()
    }

    private func deleteTask(id: UUID, organizationID: UUID) async throws {
        try await authService.client
            .from(Constants.tasksTable)
            .delete()
            .eq("id", value: id.uuidString)
            .eq("organization_id", value: organizationID.uuidString)
            .execute()
    }

    private func upsertPushDeviceToken(_ token: String, userID: UUID, organizationID: UUID) async throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }

        let payload = CloudPushDevicePayload(
            userID: userID.serverLowercasedString,
            organizationID: organizationID,
            deviceToken: trimmedToken,
            platform: "ios",
            bundleID: Bundle.main.bundleIdentifier ?? "LandTracker",
            localeIdentifier: Locale.current.identifier,
            timezoneIdentifier: TimeZone.current.identifier,
            lastSeenAt: Date(),
            updatedAt: Date()
        )

        try await authService.client
            .from(Constants.pushDevicesTable)
            .upsert(payload, onConflict: "user_id,device_token")
            .execute()
    }

    private func deletePushDeviceToken(_ token: String, userID: UUID, organizationID: UUID) async throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }

        try await authService.client
            .from(Constants.pushDevicesTable)
            .delete()
            .eq("user_id", value: userID.serverLowercasedString)
            .eq("organization_id", value: organizationID.uuidString)
            .eq("device_token", value: trimmedToken)
            .execute()
    }
}

private struct CloudOrganizationMemberRoleRecord: Codable {
    let role: String
    let memberState: String?

    enum CodingKeys: String, CodingKey {
        case role
        case memberState = "member_state"
    }
}

private struct CloudOrganizationIDRecord: Codable {
    let id: UUID
}

private struct CloudOrganizationMemberOrganizationRecord: Codable {
    let organizationID: UUID
    let memberState: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case organizationID = "organization_id"
        case memberState = "member_state"
        case createdAt = "created_at"
    }
}

private struct CloudOrganizationMembershipRecord: Codable {
    let userID: UUID
    let role: String
    let memberState: String?
    let invitedEmail: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case role
        case memberState = "member_state"
        case invitedEmail = "invited_email"
    }
}

private struct CloudOrganizationInvitationRecord: Codable {
    let id: UUID
    let invitedEmail: String
    let role: String
    let state: String
    let invitedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case invitedEmail = "invited_email"
        case role
        case state
        case invitedAt = "invited_at"
    }
}

private struct CloudOrganizationMemberRoleUpdatePayload: Encodable {
    let role: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case role
        case updatedAt = "updated_at"
    }
}

private struct CloudOrganizationInvitationRoleUpdatePayload: Encodable {
    let role: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case role
        case updatedAt = "updated_at"
    }
}

private struct CloudGroupRecord: Codable {
    let id: UUID
    let userID: UUID
    let name: String
    let colorHex: String
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case colorHex = "color_hex"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CloudGroupPayload: Encodable {
    let id: UUID
    let userID: String
    let organizationID: UUID
    let name: String
    let colorHex: String
    let createdAt: Date
    let updatedAt: Date

    init(group: LandGroup, userID: UUID, organizationID: UUID) {
        self.id = group.id
        self.userID = userID.serverLowercasedString
        self.organizationID = organizationID
        self.name = group.name
        self.colorHex = group.colorHex
        self.createdAt = group.createdAt
        self.updatedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case organizationID = "organization_id"
        case name
        case colorHex = "color_hex"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CloudLandRecord: Codable {
    let id: UUID
    let userID: UUID
    let groupID: UUID?
    let name: String
    let latitude: Double
    let longitude: Double
    let sizeAcres: Double
    let activityType: String?
    let productionType: String
    let productionSubtype: String?
    let incomeAnnual: Double
    let annualIrrigationCost: Double?
    let annualFertilizerCost: Double?
    let annualLaborCost: Double?
    let annualMaintenanceCost: Double?
    let notes: String?
    let installedCapacityKW: Double?
    let annualElectricityProductionKWh: Double?
    let selfConsumptionRate: Double?
    let gridExportRate: Double?
    let catastroRefcat14: String?
    let catastroAreaValue: Double?
    let catastroAreaUom: String?
    let catastroLabel: String?
    let catastroRings: [[Coordinate]]?
    let catastroFetchedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case groupID = "group_id"
        case name
        case latitude
        case longitude
        case sizeAcres = "size_acres"
        case activityType = "activity_type"
        case productionType = "production_type"
        case productionSubtype = "production_subtype"
        case incomeAnnual = "income_annual"
        case annualIrrigationCost = "annual_irrigation_cost"
        case annualFertilizerCost = "annual_fertilizer_cost"
        case annualLaborCost = "annual_labor_cost"
        case annualMaintenanceCost = "annual_maintenance_cost"
        case notes
        case installedCapacityKW = "installed_capacity_kw"
        case annualElectricityProductionKWh = "annual_electricity_production_kwh"
        case selfConsumptionRate = "self_consumption_rate"
        case gridExportRate = "grid_export_rate"
        case catastroRefcat14 = "catastro_refcat14"
        case catastroAreaValue = "catastro_area_value"
        case catastroAreaUom = "catastro_area_uom"
        case catastroLabel = "catastro_label"
        case catastroRings = "catastro_rings"
        case catastroFetchedAt = "catastro_fetched_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CloudLandPayload: Encodable {
    let id: UUID
    let userID: String
    let organizationID: UUID
    let groupID: UUID?
    let name: String
    let latitude: Double
    let longitude: Double
    let sizeAcres: Double
    let activityType: String
    let productionType: String
    let productionSubtype: String
    let incomeAnnual: Double
    let annualIrrigationCost: Double
    let annualFertilizerCost: Double
    let annualLaborCost: Double
    let annualMaintenanceCost: Double
    let notes: String
    let installedCapacityKW: Double
    let annualElectricityProductionKWh: Double
    let selfConsumptionRate: Double
    let gridExportRate: Double
    let catastroRefcat14: String?
    let catastroAreaValue: Double?
    let catastroAreaUom: String?
    let catastroLabel: String?
    let catastroRings: [[Coordinate]]
    let catastroFetchedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(land: Land, userID: UUID, organizationID: UUID) {
        id = land.id
        self.userID = userID.serverLowercasedString
        self.organizationID = organizationID
        groupID = land.group?.id
        name = land.name
        latitude = land.latitude
        longitude = land.longitude
        sizeAcres = land.sizeAcres
        activityType = land.activityType
        productionType = land.productionType
        productionSubtype = land.productionSubtype
        incomeAnnual = land.incomeAnnual
        annualIrrigationCost = land.annualIrrigationCost
        annualFertilizerCost = land.annualFertilizerCost
        annualLaborCost = land.annualLaborCost
        annualMaintenanceCost = land.annualMaintenanceCost
        notes = land.notes
        installedCapacityKW = land.installedCapacityKW
        annualElectricityProductionKWh = land.annualElectricityProductionKWh
        selfConsumptionRate = land.selfConsumptionRate
        gridExportRate = land.gridExportRate
        catastroRefcat14 = land.catastroRefcat14
        catastroAreaValue = land.catastroAreaValue
        catastroAreaUom = land.catastroAreaUom
        catastroLabel = land.catastroLabel
        catastroRings = land.catastroRings
        catastroFetchedAt = land.catastroFetchedAt
        createdAt = land.createdAt
        updatedAt = land.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case organizationID = "organization_id"
        case groupID = "group_id"
        case name
        case latitude
        case longitude
        case sizeAcres = "size_acres"
        case activityType = "activity_type"
        case productionType = "production_type"
        case productionSubtype = "production_subtype"
        case incomeAnnual = "income_annual"
        case annualIrrigationCost = "annual_irrigation_cost"
        case annualFertilizerCost = "annual_fertilizer_cost"
        case annualLaborCost = "annual_labor_cost"
        case annualMaintenanceCost = "annual_maintenance_cost"
        case notes
        case installedCapacityKW = "installed_capacity_kw"
        case annualElectricityProductionKWh = "annual_electricity_production_kwh"
        case selfConsumptionRate = "self_consumption_rate"
        case gridExportRate = "grid_export_rate"
        case catastroRefcat14 = "catastro_refcat14"
        case catastroAreaValue = "catastro_area_value"
        case catastroAreaUom = "catastro_area_uom"
        case catastroLabel = "catastro_label"
        case catastroRings = "catastro_rings"
        case catastroFetchedAt = "catastro_fetched_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CloudHistoryRecord: Codable {
    let id: UUID
    let userID: UUID
    let landID: UUID
    let year: Int
    let month: Int
    let incomeAmount: Double
    let productionAmount: Double
    let productionUnit: String
    let electricityKWh: Double
    let notes: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case landID = "land_id"
        case year
        case month
        case incomeAmount = "income_amount"
        case productionAmount = "production_amount"
        case productionUnit = "production_unit"
        case electricityKWh = "electricity_kwh"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CloudHistoryPayload: Encodable {
    let id: UUID
    let userID: String
    let organizationID: UUID
    let landID: UUID
    let year: Int
    let month: Int
    let incomeAmount: Double
    let productionAmount: Double
    let productionUnit: String
    let electricityKWh: Double
    let notes: String
    let createdAt: Date
    let updatedAt: Date

    init?(entry: LandHistoryEntry, userID: UUID, organizationID: UUID) {
        guard let landID = entry.land?.id else { return nil }
        id = entry.id
        self.userID = userID.serverLowercasedString
        self.organizationID = organizationID
        self.landID = landID
        year = entry.year
        month = entry.month
        incomeAmount = entry.incomeAmount
        productionAmount = entry.productionAmount
        productionUnit = entry.productionUnit
        electricityKWh = entry.electricityKWh
        notes = entry.notes
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case organizationID = "organization_id"
        case landID = "land_id"
        case year
        case month
        case incomeAmount = "income_amount"
        case productionAmount = "production_amount"
        case productionUnit = "production_unit"
        case electricityKWh = "electricity_kwh"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CloudTaskRecord: Codable {
    let id: UUID
    let userID: UUID
    let landID: UUID
    let typeRaw: String?
    let title: String
    let dueDate: Date
    let reminderDate: Date?
    let notes: String?
    let isCompleted: Bool?
    let completedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case landID = "land_id"
        case typeRaw = "type_raw"
        case title
        case dueDate = "due_date"
        case reminderDate = "reminder_date"
        case notes
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CloudTaskPayload: Encodable {
    let id: UUID
    let userID: String
    let organizationID: UUID
    let landID: UUID
    let typeRaw: String
    let title: String
    let dueDate: Date
    let reminderDate: Date?
    let notes: String
    let isCompleted: Bool
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init?(task: LandTask, userID: UUID, organizationID: UUID) {
        guard let landID = task.land?.id else { return nil }
        id = task.id
        self.userID = userID.serverLowercasedString
        self.organizationID = organizationID
        self.landID = landID
        typeRaw = task.type.rawValue
        title = task.title
        dueDate = task.dueDate
        reminderDate = task.reminderDate
        notes = task.notes
        isCompleted = task.isCompleted
        completedAt = task.isCompleted ? task.completedAt : nil
        createdAt = task.createdAt
        updatedAt = task.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case organizationID = "organization_id"
        case landID = "land_id"
        case typeRaw = "type_raw"
        case title
        case dueDate = "due_date"
        case reminderDate = "reminder_date"
        case notes
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CloudPushDevicePayload: Encodable {
    let userID: String
    let organizationID: UUID
    let deviceToken: String
    let platform: String
    let bundleID: String
    let localeIdentifier: String
    let timezoneIdentifier: String
    let lastSeenAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case organizationID = "organization_id"
        case deviceToken = "device_token"
        case platform
        case bundleID = "bundle_id"
        case localeIdentifier = "locale_identifier"
        case timezoneIdentifier = "timezone_identifier"
        case lastSeenAt = "last_seen_at"
        case updatedAt = "updated_at"
    }
}

private struct CloudSpreadsheetSourceRecord: Codable {
    let userID: UUID
    let fileName: String
    let storagePath: String
    let fileHash: String
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case fileName = "file_name"
        case storagePath = "storage_path"
        case fileHash = "file_hash"
        case updatedAt = "updated_at"
    }
}

private struct CloudSpreadsheetSourcePayload: Encodable {
    let userID: String
    let fileName: String
    let storagePath: String
    let fileHash: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case fileName = "file_name"
        case storagePath = "storage_path"
        case fileHash = "file_hash"
        case updatedAt = "updated_at"
    }
}

private struct CloudProfileRecord: Codable {
    let id: UUID
    let email: String?
    let displayName: String?
    let showIncomeInList: Bool?
    let showSubtypeInList: Bool?
    let profilePhotoPath: String?
    let accountType: String?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case showIncomeInList = "show_income_in_list"
        case showSubtypeInList = "show_subtype_in_list"
        case profilePhotoPath = "profile_photo_path"
        case accountType = "account_type"
        case updatedAt = "updated_at"
    }
}

private struct CloudProfilePayload: Encodable {
    let id: String
    let email: String?
    let displayName: String?
    let showIncomeInList: Bool
    let showSubtypeInList: Bool
    let profilePhotoPath: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case showIncomeInList = "show_income_in_list"
        case showSubtypeInList = "show_subtype_in_list"
        case profilePhotoPath = "profile_photo_path"
        case updatedAt = "updated_at"
    }
}
