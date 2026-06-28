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
                        Label(language.localized("Dashboard", "Dashboard"), systemImage: "rectangle.3.group.bubble.left.fill")
                    }

                GroupListView()
                    .tag(AppTab.groups)
                    .tabItem {
                        Label(language.localized("Groups", "Grupos"), systemImage: "square.grid.2x2")
                    }

                LandListView()
                    .tag(AppTab.lands)
                    .tabItem {
                        Label(language.localized("Lands", "Terrenos"), systemImage: "list.bullet")
                    }

                if roleAccessViewModel.canManageTeam {
                    TeamView()
                        .tag(AppTab.team)
                        .tabItem {
                            Label(language.localized("Team", "Equipo"), systemImage: "person.2")
                        }
                }
            }

            if roleAccessViewModel.canSwitchAccessRole {
                RoleSwitchButton()
                    .padding(.leading, 16)
                    .padding(.bottom, 84)
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
    case groups
    case lands
    case team
}
