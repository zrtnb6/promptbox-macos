import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard raw.count == 6, let value = Int(raw, radix: 16) else {
            self = .accentColor
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }
}

enum UI {
    static func accent(_ settings: Settings) -> Color {
        settings.useSystemAccent ? Color.accentColor : Color(hex: settings.accent)
    }

    static let accents: [(name: String, hex: String)] = [
        ("蓝", "#2563EB"),
        ("绿", "#16A34A"),
        ("紫", "#9333EA"),
        ("橙", "#F59E0B"),
        ("红", "#EF4444"),
        ("青", "#0891B2"),
        ("灰", "#64748B")
    ]
}

struct FormRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: 104, alignment: .leading)
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.quaternary, lineWidth: 1)
            }
    }
}

struct ToastOverlay: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack {
            Spacer()
            if let toast = store.toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.kind == "error" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(toast.text)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(toast.kind == "error" ? .red.opacity(0.5) : .green.opacity(0.4), lineWidth: 1)
                }
                .shadow(radius: 8, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: store.toast?.id)
        .padding(.bottom, 24)
        .allowsHitTesting(false)
    }
}

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("选择一个模板开始使用")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("按 ⌥⌘P 可随时呼出快速使用面板")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
