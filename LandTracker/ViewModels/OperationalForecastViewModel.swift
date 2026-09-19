import Foundation

/// Pure, synchronous transform over `LandTask` data for the operational forecast feature.
///
/// Unlike `AuthViewModel` / `RoleAccessViewModel`, this type owns no persisted or
/// asynchronously-updated state — it is a plain value derived entirely from the
/// `[LandTask]` array it's initialized with, so it does not need `ObservableObject` /
/// `@Published`. Construct a fresh instance whenever the underlying `@Query` result
/// changes (Views own the `@Query`; this type never touches SwiftData or SwiftUI).
///
/// v1 scope: pending (incomplete) tasks only. A "show completed" toggle is deferred.
struct OperationalForecastViewModel {

    /// How pending tasks should be grouped for display on a future forecast screen.
    enum Grouping {
        /// Today's default: flat chronological order by due date (see `pendingTasks`).
        case dueDate
        case land
        case taskType
    }

    /// Minimal, role-safe projection of a `Land` for display purposes only.
    ///
    /// Intentionally excludes economic fields (`incomeAnnual`, cost fields,
    /// `annualNetMargin`, etc.) so this type can be handed to any view regardless
    /// of `RoleAccessViewModel.canViewEconomics` — never store the full `Land` here.
    struct LandRef {
        let id: UUID
        let name: String
    }

    /// A single labeled group of tasks under a given `Grouping` mode.
    struct Section: Identifiable {
        enum Key: Hashable {
            case all
            case land(UUID)
            case unassignedLand
            case taskType(LandTaskType)
        }

        var id: Key { key }

        let key: Key
        let land: LandRef?
        let taskType: LandTaskType?
        let tasks: [LandTask]
    }

    /// All incomplete tasks, sorted by due date ascending, tie-broken by most recently updated first.
    let pendingTasks: [LandTask]

    /// Pending tasks whose due date is before the start of today.
    let overdueTasks: [LandTask]

    /// Pending tasks due today (from the start of today, up to but excluding tomorrow).
    let dueTodayTasks: [LandTask]

    /// The next tasks to act on, capped to `upcomingLimit` entries, in `pendingTasks` order.
    let upcomingTasks: [LandTask]

    init(
        tasks: [LandTask],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        upcomingLimit: Int = 5
    ) {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday

        let pending = tasks
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.dueDate == rhs.dueDate {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.dueDate < rhs.dueDate
            }

        pendingTasks = pending
        overdueTasks = pending.filter { $0.dueDate < startOfToday }
        dueTodayTasks = pending.filter { $0.dueDate >= startOfToday && $0.dueDate < endOfToday }
        upcomingTasks = Array(pending.prefix(upcomingLimit))
    }

    /// Pending tasks grouped for the given mode. Each section preserves the chronological
    /// order already established by `pendingTasks`; only the bucketing changes.
    func sections(groupedBy grouping: Grouping) -> [Section] {
        switch grouping {
        case .dueDate:
            return [Section(key: .all, land: nil, taskType: nil, tasks: pendingTasks)]
        case .land:
            return groupedByLand()
        case .taskType:
            return groupedByTaskType()
        }
    }

    private func groupedByLand() -> [Section] {
        var order: [Section.Key] = []
        var lands: [Section.Key: LandRef?] = [:]
        var buckets: [Section.Key: [LandTask]] = [:]

        for task in pendingTasks {
            let key: Section.Key = task.land.map { .land($0.id) } ?? .unassignedLand

            if buckets[key] == nil {
                buckets[key] = []
                lands[key] = task.land.map { LandRef(id: $0.id, name: $0.name) }
                order.append(key)
            }
            buckets[key, default: []].append(task)
        }

        return order.map { key in
            Section(key: key, land: lands[key] ?? nil, taskType: nil, tasks: buckets[key] ?? [])
        }
    }

    private func groupedByTaskType() -> [Section] {
        var buckets: [LandTaskType: [LandTask]] = [:]

        for task in pendingTasks {
            buckets[task.type, default: []].append(task)
        }

        return LandTaskType.allCases.compactMap { type in
            guard let tasks = buckets[type], !tasks.isEmpty else { return nil }
            return Section(key: .taskType(type), land: nil, taskType: type, tasks: tasks)
        }
    }
}
