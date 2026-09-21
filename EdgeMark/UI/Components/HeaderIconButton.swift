import SwiftUI

/// Compact toolbar icon with a soft accent hover treatment.
struct HeaderIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isHovered
                                ? Color.accentColor.opacity(0.16)
                                : Color.primary.opacity(0.025),
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.primary.opacity(isHovered ? 0.10 : 0.05), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .scaleEffect(isHovered ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
