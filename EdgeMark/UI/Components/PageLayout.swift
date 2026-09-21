import SwiftUI

/// Shared floating-card layout used across all panel screens.
struct PageLayout<Header: View, Content: View>: View {
    @Environment(AppSettings.self) private var appSettings
    var onSwipeBack: (() -> Void)?
    var onContentSwipeRight: (() -> Void)?
    var onContentSwipeLeft: (() -> Void)?
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    private let cornerRadius: CGFloat = 16

    init(
        onSwipeBack: (() -> Void)? = nil,
        onContentSwipeRight: (() -> Void)? = nil,
        onContentSwipeLeft: (() -> Void)? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
    ) {
        self.onSwipeBack = onSwipeBack
        self.onContentSwipeRight = onContentSwipeRight
        self.onContentSwipeLeft = onContentSwipeLeft
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    VisualEffectView(
                        tint: appSettings.panelTint.color,
                        material: appSettings.panelStyle.material,
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
                .overlay {
                    if let onSwipeBack {
                        SwipeDetectorView(onSwipeBack: onSwipeBack)
                    }
                }

            content
                .background {
                    VisualEffectView(
                        tint: appSettings.panelTint.color,
                        material: appSettings.panelStyle.material,
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.20), radius: 16, y: 7)
                .overlay {
                    if onContentSwipeRight != nil || onContentSwipeLeft != nil {
                        SwipeDetectorView(
                            onSwipeBack: onContentSwipeRight,
                            onSwipeForward: onContentSwipeLeft,
                        )
                    }
                }
        }
        .padding(10)
    }
}
