import SwiftUI

struct AccountToolbarButton: View {
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
        .accessibilityLabel("Cuenta")
    }
}
