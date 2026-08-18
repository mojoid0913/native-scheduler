// NativeScheduler/Sources/NativeScheduler/Features/Settings/CategoryEditorView.swift
import SwiftUI
import CoreData

// MARK: - Category row editor

/// A single editable row in the Settings category list.
/// Displays an inline color picker and name text field; calls back on any change.
struct CategoryRowView: View {
    let cat: CategoryEntity
    let onDelete: () -> Void
    let onChange: () -> Void

    @State private var name: String = ""
    @State private var color: Color = .gray

    var body: some View {
        HStack(spacing: SchedulerSpacing.compact) {
            ColorPicker("", selection: $color)
                .labelsHidden()
                .frame(width: 24, height: 24)
                .onChange(of: color) { cat.colorHex = color.hexString; onChange() }
                .accessibilityLabel("Color for \(name)")

            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(SchedulerType.body)
                .foregroundColor(.nsTextPrimary)
                .lineLimit(1)
                .onChange(of: name) { cat.name = name; onChange() }
                .accessibilityLabel("Category name")

            Spacer()

            // Trash button uses .red tint at reduced opacity — signals destructive intent
            // without shouting. The actual deletion is guarded by a confirmationDialog
            // in SettingsView, so this can be visually clear without being alarming.
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.55))
                    .frame(
                        width: SchedulerControl.minimumTarget,
                        height: SchedulerControl.minimumTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(name)")
        }
        .frame(minHeight: 28)
        .onAppear {
            name  = cat.name
            color = Color(hex: cat.colorHex)
        }
    }
}
