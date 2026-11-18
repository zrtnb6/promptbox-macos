import SwiftUI

struct VariableFieldView: View {
    let variable: TemplateVariable
    @Binding var value: VariableValue

    private var stringValue: String {
        if case .string(let s) = value { return s }
        return ""
    }

    private var selectedStrings: [String] {
        if case .strings(let a) = value { return a }
        return []
    }

    private var numberValue: Double {
        switch value {
        case .number(let n): return n
        case .string(let s): return Double(s) ?? (variable.min ?? 0)
        default: return variable.min ?? 0
        }
    }

    private var numberRange: ClosedRange<Double> {
        let lo = variable.min ?? 0
        let hi = variable.max ?? 10000
        return hi > lo ? lo...hi : lo...(lo + 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(variable.label)
                    .font(.system(.body, weight: .medium))
                if variable.required == true {
                    Text("*").foregroundStyle(.red)
                }
                Spacer()
                if variable.placeholder == nil || variable.type != .number {
                    Text("{{\(variable.key)}}")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            if let description = variable.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            control
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var control: some View {
        switch variable.type {
        case .text:
            TextField(variable.placeholder ?? "", text: Binding(
                get: { stringValue },
                set: { value = .string($0) }
            ))
            .textFieldStyle(.roundedBorder)

        case .textarea:
            TextEditor(text: Binding(
                get: { stringValue },
                set: { value = .string($0) }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(height: 92)
            .overlay {
                RoundedRectangle(cornerRadius: 5).stroke(.quaternary)
            }

        case .select:
            Picker("", selection: Binding(
                get: { stringValue },
                set: { value = .string($0) }
            )) {
                ForEach(variable.options ?? []) { option in
                    Text(optionValue(option)).tag(optionValue(option))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .multiselect:
            FlowLayout(spacing: 6) {
                ForEach(variable.options ?? [], id: \.id) { option in
                    ChipView(
                        text: optionValue(option),
                        selected: selectedStrings.contains(optionValue(option))
                    ) {
                        toggleOption(optionValue(option))
                    }
                }
            }

        case .toggle:
            Toggle(isOn: Binding(
                get: { value == .bool(true) },
                set: { value = .bool($0) }
            )) {
                Text(value == .bool(true) ? (variable.onText ?? "是") : (variable.offText ?? "否"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)

        case .number:
            HStack(spacing: 10) {
                Slider(value: Binding(
                    get: { numberValue },
                    set: { value = .number($0) }
                ), in: numberRange, step: variable.step ?? 1)
                TextField("", value: Binding(
                    get: { numberValue },
                    set: { value = .number($0) }
                ), formatter: NumberFormatter())
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                if let unit = variable.unit {
                    Text(unit).foregroundStyle(.secondary).font(.caption)
                }
            }

        case .date:
            DatePicker("", selection: Binding(
                get: { dateFromISO(stringValue) },
                set: { value = .string(isoFromDate($0)) }
            ), displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleOption(_ text: String) {
        var current = selectedStrings
        if let index = current.firstIndex(of: text) {
            current.remove(at: index)
        } else {
            current.append(text)
        }
        value = .strings(current)
    }

    private func dateFromISO(_ s: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: s) ?? Date()
    }

    private func isoFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct ChipView: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if selected { Image(systemName: "checkmark") }
                Text(text)
            }
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.gray.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 简易流式布局，用于多选标签
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
