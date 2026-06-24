import SwiftUI
import UIKit

struct ProfileAvatarView: View {
    let imageData: Data?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .background(.thinMaterial)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
