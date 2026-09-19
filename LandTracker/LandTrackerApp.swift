import SwiftUI
import SwiftData

@main
struct LandTrackerApp: App {
    private let container: ModelContainer
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var roleAccessViewModel = RoleAccessViewModel()

    init() {
        AppTheme.registerFonts()
        AppTheme.configureNavigationTitleFonts()
        do {
            let schema = Schema([Land.self, LandGroup.self, LandHistoryEntry.self, LandTask.self, PendingSyncOperation.self])
            let configuration = ModelConfiguration(schema: schema)
            container = try ModelContainer(for: schema, configurations: [configuration])
            UserDefaults.standard.removeObject(forKey: "account.profileImageBase64")
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(roleAccessViewModel)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var roleAccessViewModel: RoleAccessViewModel
    @State private var showGlassTransition = false
    @State private var glassPulseActive = false
    @State private var overlayDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if authViewModel.isAuthenticated {
                ContentView()
                    .transition(.asymmetric(insertion: .glassSwap(blur: 18, scale: 1.02), removal: .opacity))
            } else {
                LoginView(viewModel: authViewModel)
                    .transition(.asymmetric(insertion: .opacity, removal: .glassSwap(blur: 16, scale: 0.985)))
            }

            if showGlassTransition {
                LoginGlassOverlay(isPulsing: glassPulseActive)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.58, dampingFraction: 0.9), value: authViewModel.isAuthenticated)
        .onChange(of: authViewModel.isAuthenticated) { oldValue, newValue in
            if !oldValue && newValue {
                triggerGlassTransition()
            }

            if oldValue && !newValue {
                SupabaseSyncService.shared.clearLocalCache(context: context)
                ProfileImageStore.shared.imageData = nil
                roleAccessViewModel.resetForSignedOut()
            }
        }
        .onDisappear {
            overlayDismissTask?.cancel()
        }
    }

    private func triggerGlassTransition() {
        overlayDismissTask?.cancel()
        glassPulseActive = false
        withAnimation(.easeIn(duration: 0.16)) {
            showGlassTransition = true
        }
        withAnimation(.easeOut(duration: 0.55)) {
            glassPulseActive = true
        }

        overlayDismissTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.28)) {
                    showGlassTransition = false
                }
            }
        }
    }
}

private struct GlassSwapModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static func glassSwap(blur: CGFloat, scale: CGFloat) -> AnyTransition {
        .modifier(
            active: GlassSwapModifier(opacity: 0, blur: blur, scale: scale),
            identity: GlassSwapModifier(opacity: 1, blur: 0, scale: 1)
        )
    }
}

private struct LoginGlassOverlay: View {
    let isPulsing: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.5)

            LinearGradient(
                colors: [Color.white.opacity(0.55), Color.clear, Color.cyan.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .rotationEffect(.degrees(isPulsing ? 8 : -8))
            .scaleEffect(isPulsing ? 1.08 : 1.24)
            .opacity(isPulsing ? 0.42 : 0.2)

            Rectangle()
                .fill(Color.white.opacity(isPulsing ? 0.16 : 0.06))
                .blur(radius: isPulsing ? 4 : 14)
        }
        .ignoresSafeArea()
    }
}
