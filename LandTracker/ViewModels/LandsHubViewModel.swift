import Foundation

/// Pure, synchronous transform that turns the flat `[Land]` / `[LandGroup]` query results
/// into the sectioned structure shown by the merged "Lands" tab (list and map browser).
///
/// Like `OperationalForecastViewModel`, this type owns no state and never touches SwiftData
/// queries, services, the environment or SwiftUI: Views own the `@Query` results and call
/// `sections(...)` whenever they change. That keeps it trivially unit-testable.
///
/// Economic fields (`incomeAnnual`, costs, margins) are intentionally never read here, so the
/// output is safe to hand to any role regardless of `canViewEconomics`.
enum LandsHubViewModel {

    /// Stable id of the trailing "Ungrouped" section. Real groups use their UUID string.
    static let ungroupedSectionID = "ungrouped"

    /// One block of the Lands tab: a real group (`group != nil`) or the "Ungrouped" bucket.
    struct Section: Identifiable {
        let id: String
        /// `nil` means the "Ungrouped" section.
        let group: LandGroup?
        let lands: [Land]

        var isUngrouped: Bool { group == nil }
    }

    /// The section a land belongs to, by id. Lands with no group belong to `ungroupedSectionID`.
    static func sectionID(for land: Land) -> String {
        land.group?.id.uuidString ?? ungroupedSectionID
    }

    /// Builds the ordered sections.
    ///
    /// - Empty search: every group appears (including groups with zero lands, so owners can
    ///   still manage them) plus one trailing Ungrouped section only if some land has no group.
    /// - Non-empty search (trimmed): a group whose name matches contributes all of its lands;
    ///   otherwise only the lands matching the query are kept. Sections left with no lands are
    ///   dropped, and Ungrouped appears only when it has matching lands.
    /// - Groups are sorted by name and lands inside a section by name (both
    ///   `localizedCaseInsensitive`, ties broken by id so the order is deterministic).
    static func sections(
        lands: [Land],
        groups: [LandGroup],
        searchText: String,
        language: AppLanguage
    ) -> [Section] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !query.isEmpty

        let sortedGroups = groups.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
            return order == .orderedAscending
        }
        let knownGroupIDs = Set(sortedGroups.map(\.id))

        var landsByGroupID: [UUID: [Land]] = [:]
        var ungroupedLands: [Land] = []
        for land in lands {
            if let groupID = land.group?.id, knownGroupIDs.contains(groupID) {
                landsByGroupID[groupID, default: []].append(land)
            } else {
                ungroupedLands.append(land)
            }
        }

        var result: [Section] = []

        for group in sortedGroups {
            let groupLands = sortedByName(landsByGroupID[group.id] ?? [])

            guard isSearching else {
                result.append(Section(id: group.id.uuidString, group: group, lands: groupLands))
                continue
            }

            let visibleLands = contains(group.name, query)
                ? groupLands
                : groupLands.filter { landMatches($0, query: query, language: language) }
            if !visibleLands.isEmpty {
                result.append(Section(id: group.id.uuidString, group: group, lands: visibleLands))
            }
        }

        let visibleUngrouped = isSearching
            ? sortedByName(ungroupedLands).filter { landMatches($0, query: query, language: language) }
            : sortedByName(ungroupedLands)
        if !visibleUngrouped.isEmpty {
            result.append(Section(id: ungroupedSectionID, group: nil, lands: visibleUngrouped))
        }

        return result
    }

    /// Whether a land matches an already-trimmed, non-empty query on its own fields: name,
    /// activity, production type, variety (raw and localized) and notes. The group name is
    /// handled at section level by `sections(...)`.
    static func landMatches(_ land: Land, query: String, language: AppLanguage) -> Bool {
        let localizedActivity = ActivityCatalog.displayName(for: land.activityType, language: language)
        let localizedProduction = ProductionCatalog.displayName(for: land.productionType, language: language)
        let localizedSubtype = ProductionCatalog.displayVarietyName(for: land.productionSubtype, language: language)

        return contains(land.name, query) ||
            contains(land.activityType, query) ||
            contains(localizedActivity, query) ||
            contains(land.productionType, query) ||
            contains(localizedProduction, query) ||
            contains(land.productionSubtype, query) ||
            contains(localizedSubtype, query) ||
            contains(land.notes, query)
    }

    /// Case- and diacritic-insensitive, so "vinedo" finds "Viñedo" and "citricos" finds "Cítricos".
    private static func contains(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func sortedByName(_ lands: [Land]) -> [Land] {
        lands.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
            return order == .orderedAscending
        }
    }
}
