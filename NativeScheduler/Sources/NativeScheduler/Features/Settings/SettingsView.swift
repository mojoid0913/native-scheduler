// NativeScheduler/Sources/NativeScheduler/Features/Settings/SettingsView.swift
import CoreData
import SwiftUI
import ServiceManagement

struct LaunchAtLoginMutationOutcome: Equatable {
    let isEnabled: Bool
    let errorMessage: String?
}

enum LaunchAtLoginMutation {
    static func apply(
        desiredEnabled: Bool,
        previousEnabled: Bool,
        perform: () throws -> Void
    ) -> LaunchAtLoginMutationOutcome {
        do {
            try perform()
            return LaunchAtLoginMutationOutcome(
                isEnabled: desiredEnabled,
                errorMessage: nil
            )
        } catch {
            return LaunchAtLoginMutationOutcome(
                isEnabled: previousEnabled,
                errorMessage: "Launch at login could not be updated and was restored."
            )
        }
    }
}

struct SettingsLaunchAtLoginSection: View {
    static let errorColor = Color.daylineError

    @Binding var isEnabled: Bool
    let errorMessage: String?
    let onChange: (Bool) -> Void

    init(
        isEnabled: Binding<Bool>,
        errorMessage: String?,
        onChange: @escaping (Bool) -> Void
    ) {
        _isEnabled = isEnabled
        self.errorMessage = errorMessage
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $isEnabled) {
                Text("Launch at login")
                    .font(SchedulerType.body)
                    .foregroundColor(.nsTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("settings.launchAtLogin.toggle")
            .padding(.horizontal, SchedulerSpacing.cardInset)
            .padding(.vertical, 9)
            .onChange(of: isEnabled) { _, newValue in
                onChange(newValue)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(SchedulerType.metadata)
                    .foregroundColor(Self.errorColor)
                    .padding(.horizontal, SchedulerSpacing.cardInset)
                    .padding(.bottom, SchedulerSpacing.xs)
                    .accessibilityLabel("Settings error: \(errorMessage)")
                    .accessibilityIdentifier("settings.launchAtLogin.error")
            }
        }
    }
}

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var categories: [CategoryEntity] = []
    @State private var launchAtLogin: Bool = false
    @State private var newCatName: String = ""
    @State private var newCatColor: Color = .blue
    @State private var persistenceError: String?
    @State private var launchAtLoginError: String?
    @State private var isReconcilingLaunchAtLogin = false
    @State private var categoryEditorVersion = UUID()
    @State private var categoryContext: NSManagedObjectContext
    // Pending delete — drives the confirmationDialog below.
    // Keeping it as optional category avoids a separate Bool + separate stored category.
    @State private var categoryToDelete: CategoryEntity? = nil
    // @AppStorage binds directly to UserDefaults — no manual save/load needed.
    @AppStorage("defaultTimerDuration") private var defaultDurationMinutes: Int    = 25
    @AppStorage("defaultTimerMode")     private var defaultTimerMode:       String = "duration"

    private let stack: CoreDataStack
    private let onSettingsChanged: () -> Void
    private let launchAtLoginStatus: () -> Bool
    private let setLaunchAtLoginEnabled: (Bool) throws -> Void

    init(
        stack: CoreDataStack? = nil,
        onSettingsChanged: @escaping () -> Void = {},
        launchAtLoginStatus: @escaping () -> Bool = {
            SMAppService.mainApp.status == .enabled
        },
        initialLaunchAtLoginError: String? = nil,
        setLaunchAtLoginEnabled: @escaping (Bool) throws -> Void = { enabled in
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    ) {
        let resolvedStack = stack ?? .shared
        self.stack = resolvedStack
        self.onSettingsChanged = onSettingsChanged
        self.launchAtLoginStatus = launchAtLoginStatus
        self.setLaunchAtLoginEnabled = setLaunchAtLoginEnabled
        _launchAtLoginError = State(initialValue: initialLaunchAtLoginError)
        _categoryContext = State(initialValue: resolvedStack.makeSettingsContext())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack {
                Text("Settings")
                    .font(SchedulerType.cardTitle)
                    .foregroundColor(.nsTextPrimary)
                    .lineLimit(1)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.nsTextSecondary)
                        .frame(
                            width: SchedulerControl.minimumTarget,
                            height: SchedulerControl.minimumTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Settings")
            }
            .padding(.horizontal, SchedulerSpacing.cardInset)
            .padding(.vertical, SchedulerSpacing.cardInset)

            Divider().background(Color.nsBorder.opacity(0.72))

            // ── Scrollable body ───────────────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    SettingsLaunchAtLoginSection(
                        isEnabled: $launchAtLogin,
                        errorMessage: launchAtLoginError
                    ) { newValue in
                            if isReconcilingLaunchAtLogin {
                                isReconcilingLaunchAtLogin = false
                                return
                            }
                            toggleLaunchAtLogin(newValue)
                    }

                    sectionDivider

                    // ── Timer defaults section ────────────────────────────
                    sectionHeader("Timer defaults")
                        .padding(.top, SchedulerSpacing.cardInset)
                        .padding(.horizontal, SchedulerSpacing.cardInset)

                    // Default duration stepper
                    settingsRow {
                        HStack {
                            Text("Default duration")
                                .font(SchedulerType.body)
                                .foregroundColor(.nsTextPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            HStack(spacing: 6) {
                                Text("\(defaultDurationMinutes) min")
                                    .font(SchedulerType.monospacedContext)
                                    .foregroundColor(.nsTextPrimary)
                                    .frame(minWidth: 52, alignment: .trailing)
                                    .lineLimit(1)
                                Stepper("", value: $defaultDurationMinutes, in: 1...120, step: 5)
                                    .labelsHidden()
                                    .colorScheme(.dark)
                                    .onChange(of: defaultDurationMinutes) { _, _ in
                                        onSettingsChanged()
                                    }
                                    .accessibilityLabel("Default duration: \(defaultDurationMinutes) minutes")
                            }
                        }
                    }

                    // Default mode segmented control
                    settingsRow {
                        HStack {
                            Text("Default mode")
                                .font(SchedulerType.body)
                                .foregroundColor(.nsTextPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Picker("", selection: $defaultTimerMode) {
                                Text("Duration").tag("duration")
                                Text("End Time").tag("endTime")
                                Text("Count Up").tag("countUp")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 210)
                            .colorScheme(.dark)
                            .onChange(of: defaultTimerMode) { _, _ in
                                onSettingsChanged()
                            }
                            .accessibilityLabel("Default timer mode")
                        }
                    }

                    sectionDivider

                    // ── Categories section ────────────────────────────────
                    sectionHeader("Categories")
                        .padding(.top, SchedulerSpacing.cardInset)
                        .padding(.horizontal, SchedulerSpacing.cardInset)

                    if let persistenceError {
                        Text(persistenceError)
                            .font(SchedulerType.metadata)
                            .foregroundColor(.red.opacity(0.85))
                            .padding(.top, SchedulerSpacing.xs)
                            .padding(.horizontal, SchedulerSpacing.cardInset)
                            .accessibilityLabel("Settings error: \(persistenceError)")
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(categories, id: \.objectID) { cat in
                            CategoryRowView(
                                cat: cat,
                                // Stage the delete — confirmationDialog fires before actual delete
                                onDelete: { categoryToDelete = cat },
                                onChange: saveCategoryChanges
                            )
                            .padding(.horizontal, SchedulerSpacing.cardInset)
                            .padding(.vertical, SchedulerSpacing.xs)
                        }

                        // Add category row
                        HStack(spacing: 8) {
                            ColorPicker("", selection: $newCatColor)
                                .labelsHidden()
                                .frame(width: 24, height: 24)
                                .accessibilityLabel("New category color")

                            TextField("New category…", text: $newCatName)
                                .textFieldStyle(.plain)
                                .font(SchedulerType.body)
                                .lineLimit(1)
                                .foregroundColor(.nsTextPrimary)
                                .onSubmit { addCategory() }
                                .accessibilityLabel("New category name")

                            Spacer()

                            Button(action: addCategory) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                    .imageScale(.small)
                                    .foregroundColor(newCatName.trimmingCharacters(in: .whitespaces).isEmpty
                                                     ? .nsTextSecondary
                                                     : .nsChevron)
                                    .frame(
                                        width: SchedulerControl.minimumTarget,
                                        height: SchedulerControl.minimumTarget
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(newCatName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityLabel("Add category")
                        }
                        .padding(.horizontal, SchedulerSpacing.cardInset)
                        .padding(.vertical, SchedulerSpacing.xs)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .id(categoryEditorVersion)
                }
            }
        }
        .frame(width: 336, height: 472)
        .schedulerCardSurface(radius: SchedulerRadius.sheet, elevated: true)
        // ── Category delete confirmation ───────────────────────────────────
        // Deleting a category cascades to all linked TodoItems and Sessions.
        // A confirmationDialog prevents accidental destructive action.
        .confirmationDialog(
            "Delete \"\(categoryToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get:  { categoryToDelete != nil },
                set:  { if !$0 { categoryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let cat = categoryToDelete {
                    deleteCategory(cat)
                }
                categoryToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
            }
        } message: {
            Text("Removing '\(categoryToDelete?.name ?? "")' will unlink it from all connected tasks and timer sessions. This cannot be undone.")
        }
        .onAppear {
            loadCategories()
        launchAtLogin = launchAtLoginStatus()
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, SchedulerSpacing.cardInset)
            .padding(.vertical, 9)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SchedulerType.metadata)
            .foregroundColor(.nsTextTertiary)
            .lineLimit(1)
    }

    private var sectionDivider: some View {
        Divider().background(Color.nsBorder.opacity(0.72))
    }

    // MARK: - Actions

    private func loadCategories() {
        categories = CategoryEntity.fetchAll(in: categoryContext)
    }

    private func addCategory() {
        let name = newCatName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, categories.count < 12 else { return }
        let order = Int32(categories.count)
        _ = CategoryEntity.create(
            name: name,
            colorHex: newCatColor.hexString,
            sortOrder: order,
            in: categoryContext
        )
        switch stack.save(context: categoryContext) {
        case .success:
            persistenceError = nil
            newCatName = ""
            loadCategories()
            onSettingsChanged()
        case .failure:
            recoverFromCategorySaveFailure(message: "Category could not be added. Your entry was kept.")
        }
    }

    private func saveCategoryChanges() {
        guard categoryContext.hasChanges else { return }
        switch stack.save(context: categoryContext) {
        case .success:
            persistenceError = nil
            loadCategories()
            onSettingsChanged()
        case .failure:
            recoverFromCategorySaveFailure(message: "Category changes could not be saved and were reverted.")
        }
    }

    private func deleteCategory(_ cat: CategoryEntity) {
        categoryContext.delete(cat)
        switch stack.save(context: categoryContext) {
        case .success:
            persistenceError = nil
            loadCategories()
            onSettingsChanged()
        case .failure:
            recoverFromCategorySaveFailure(message: "Category could not be deleted and was restored.")
        }
    }

    private func recoverFromCategorySaveFailure(message: String) {
        categoryContext.rollback()
        loadCategories()
        categoryEditorVersion = UUID()
        persistenceError = message
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        let outcome = LaunchAtLoginMutation.apply(
            desiredEnabled: enabled,
            previousEnabled: !enabled
        ) {
            try setLaunchAtLoginEnabled(enabled)
        }
        launchAtLoginError = outcome.errorMessage
        guard launchAtLogin != outcome.isEnabled else { return }
        isReconcilingLaunchAtLogin = true
        launchAtLogin = outcome.isEnabled
        if let errorMessage = outcome.errorMessage {
            print("[LaunchAtLogin] \(errorMessage)")
        }
    }
}

// CategoryRowView is defined in CategoryEditorView.swift (same module — no import needed).
