import SwiftUI

struct AccountToolbarButton: View {
    let language: AppLanguage
    let action: () -> Void
    @ObservedObject private var profileImageStore = ProfileImageStore.shared

    var body: some View {
        Button(action: action) {
            ProfileAvatarView(
                imageData: profileImageStore.imageData,
                size: 30
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.localized("Account", "Cuenta"))
    }
}
