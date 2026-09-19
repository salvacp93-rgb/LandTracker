import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.poppins(.subheadline))
                .foregroundStyle(AppTheme.inkSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.poppins(.body))
            Spacer(minLength: 0)
        }
    }
}
