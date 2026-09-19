import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @State private var selectedTab: AppTab = .dashboard
    @State private var syncError: String?
    @State private var hasAttemptedStartupSync = false

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tag(AppTab.dashboard)
                    .tabItem {
                        Label(language.localized("Dashboard", "Dashboard"), image: "TabGrid")
                    }

                LandsView()
                    .tag(AppTab.lands)
                    .tabItem {
                        Label(language.localized("Lands", "Terrenos"), image: "TabDiamond")
                    }

                if roleAccessViewModel.canViewEconomics {
                    InsightsView()
                        .tag(AppTab.insights)
                        .tabItem {
                            Label(language.localized("Insights", "Estadísticas"), image: "TabChart")
                        }
                }

                if roleAccessViewModel.canManageTeam {
                    TeamView()
                        .tag(AppTab.team)
                        .tabItem {
                            Label(language.localized("Team", "Equipo"), image: "TabTeam")
                        }
                }
            }
        }
        .task(id: authViewModel.userID) {
            await roleAccessViewModel.refreshRolesFromCloud()
            await runStartupSyncIfNeeded()
        }
        .onChange(of: authViewModel.userID) { _, _ in
            hasAttemptedStartupSync = false
        }
        .alert("Cloud Sync Error", isPresented: Binding(get: { syncError != nil }, set: { _ in syncError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncError ?? "")
        }
    }

    @MainActor
    private func runStartupSyncIfNeeded() async {
        guard authViewModel.isAuthenticated else {
            hasAttemptedStartupSync = false
            return
        }

        guard !hasAttemptedStartupSync else { return }
        hasAttemptedStartupSync = true

        do {
            try await SupabaseSyncService.shared.performStartupSync(context: context)
        } catch {
            syncError = error.localizedDescription
        }
    }
}

private enum AppTab: Hashable {
    case dashboard
    case lands
    case insights
    case team
}
