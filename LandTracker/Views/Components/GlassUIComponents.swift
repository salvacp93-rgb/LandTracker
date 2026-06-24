import SwiftUI

struct GlassSelectionCard: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let iconText: String?
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    init(
        title: String,
        subtitle: String?,
        systemImage: String,
        iconText: String? = nil,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconText = iconText
        self.tint = tint
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                iconBadge

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.secondary.opacity(isSelected ? 0.88 : 1))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? tint : Color.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                cardBackground
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.025), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }

    private var iconBadge: some View {
        Group {
            if let iconText, !iconText.isEmpty {
                Text(iconText)
                    .font(.headline)
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint.opacity(isSelected ? 0.98 : 0.82))
                    .frame(width: 30, height: 30)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.22 : 0.08),
                                tint.opacity(isSelected ? 0.24 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isSelected ? 0.24 : 0.10),
                            tint.opacity(isSelected ? 0.14 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(isSelected ? 1 : 0.82)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cardStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isSelected ? 0.42 : 0.18),
                tint.opacity(isSelected ? 0.24 : 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct GradientInfoPill: View {
    let title: String
    let value: String
    let systemImage: String
    let iconText: String?
    let colors: [Color]

    init(
        title: String,
        value: String,
        systemImage: String,
        iconText: String? = nil,
        colors: [Color]
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.iconText = iconText
        self.colors = colors
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let iconText, !iconText.isEmpty {
                    Text(iconText)
                        .font(.caption)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                }
            }
            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

struct GlassPanelCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if hasHeader {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        if let title, !title.isEmpty {
                            Text(title)
                                .font(.headline.weight(.semibold))
                        }

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        )
    }

    private var hasHeader: Bool {
        if let title, !title.isEmpty {
            return true
        }

        if let subtitle, !subtitle.isEmpty {
            return true
        }

        return false
    }
}

struct GlassHeroSummaryTile: View {
    let title: String
    let value: String
    let systemImage: String
    let iconText: String?
    let colors: [Color]

    init(
        title: String,
        value: String,
        systemImage: String,
        iconText: String? = nil,
        colors: [Color]
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.iconText = iconText
        self.colors = colors
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let iconText, !iconText.isEmpty {
                    Text(iconText)
                        .font(.title3)
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
            }
            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(spacing: 3) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }
}
