import Foundation
import SwiftData

enum PendingSyncEntityType: String, Codable, CaseIterable {
    case land
    case group
    case historyEntry
    case task
}

enum PendingSyncActionType: String, Codable, CaseIterable {
    case upsert
    case delete
}

@Model
final class PendingSyncOperation {
    var id: UUID
    var entityTypeRaw: String
    var actionTypeRaw: String
    var recordID: UUID
    var createdAt: Date
    var updatedAt: Date
    var retryCount: Int
    var nextRetryAt: Date?
    var lastError: String?

    init(
        entityType: PendingSyncEntityType,
        actionType: PendingSyncActionType,
        recordID: UUID,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.entityTypeRaw = entityType.rawValue
        self.actionTypeRaw = actionType.rawValue
        self.recordID = recordID
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.retryCount = 0
        self.nextRetryAt = nil
        self.lastError = nil
    }

    var entityType: PendingSyncEntityType {
        get { PendingSyncEntityType(rawValue: entityTypeRaw) ?? .land }
        set { entityTypeRaw = newValue.rawValue }
    }

    var actionType: PendingSyncActionType {
        get { PendingSyncActionType(rawValue: actionTypeRaw) ?? .upsert }
        set { actionTypeRaw = newValue.rawValue }
    }

    func markSuccess(at date: Date = Date()) {
        updatedAt = date
        retryCount = 0
        nextRetryAt = nil
        lastError = nil
    }

    func markRetry(error: String, at date: Date = Date()) {
        retryCount += 1
        updatedAt = date
        lastError = error
        nextRetryAt = date.addingTimeInterval(Self.backoffSeconds(for: retryCount))
    }

    private static func backoffSeconds(for attempt: Int) -> TimeInterval {
        switch attempt {
        case 1:
            return 60
        case 2:
            return 300
        case 3:
            return 900
        case 4:
            return 1800
        default:
            return 3600
        }
    }
}
