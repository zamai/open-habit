import SwiftUI
import UniformTypeIdentifiers
import OpenHabitCore

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
private struct PendingDataImport: Identifiable {
    let id = UUID()
    let plan: DataImportPlan
    let source: DataImportSource
}
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var importing = false
    @State private var nativeImport = true
    @State private var choosingImport = false
    @State private var document = BackupDocument(data: Data())
    @State private var pending: PendingDataImport?
    @State private var deleting = false
    @State private var problem: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: Binding(get: { model.data.settings.appearance }, set: { value in model.setSettings { $0.appearance = value } })) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("First day of week", selection: Binding(get: { model.data.settings.weekStart }, set: { value in model.setSettings { $0.weekStart = value } })) {
                        ForEach(WeekStart.allCases, id: \.self) { Text($0 == .system ? "System Default" : $0.rawValue.capitalized).tag($0) }
                    }
                }
                Section {
                    HStack {
                        Label(model.syncStatus, systemImage: model.syncStatus == "Synced" ? "checkmark.icloud" : "icloud")
                        Spacer()
                        Button {
                            Task { await model.sync() }
                        } label: {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.syncing)
                    }
                } footer: { Text("Private iCloud sync keeps your devices together and can recover your data after reinstalling. It isn’t a versioned backup: edits and deletions sync too.") }
                Section {
                    NavigationLink { ArchivedHabitsView() } label: { Label("Archived Habits", systemImage: "archivebox") }
                    Button {
                        do { document = BackupDocument(data: try Backup(dataset: sharedStore().read().dataset).encoded()); exporting = true }
                        catch { problem = error.localizedDescription }
                    } label: {
                        Label {
                            Text("Export Backup").foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(.green)
                        }
                    }
                    .buttonStyle(.plain)
                    Button { choosingImport = true } label: {
                        Label {
                            Text("Import").foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "arrow.counterclockwise").foregroundStyle(.green)
                        }
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Import", isPresented: $choosingImport, titleVisibility: .visible) {
                        Button("Open Habit import") { nativeImport = true; importing = true }
                        Button("HabitKit data import") { nativeImport = false; importing = true }
                    }
                    NavigationLink("Recovery Backups") { RecoveryBackupsView() }
                }
                Section {
                    NavigationLink("About Open Habit") {
                        VStack(spacing: 20) {
                            Image(systemName: "leaf.circle.fill").font(.system(size: 72)).foregroundStyle(.green)
                            Text("Open Habit").font(.largeTitle.bold())
                            Text("A little, every day.").font(.title3)
                            Text("Private habits. Small steps. Your data.\nBuilt for iPhone and iPad, with no Open Habit account and no hosted user-data service.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Text(appVersion).font(.caption).foregroundStyle(.secondary)
                        }.padding(30).navigationTitle("About")
                    }
                    Button("Delete All Data", role: .destructive) { deleting = true }
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Open-Habit-\(LocalDay.string())") { result in if case .failure(let error) = result { problem = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                var selectedFileName: String?
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    selectedFileName = url.lastPathComponent
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    let source: DataImportSource = nativeImport ? .openHabit : .habitKit
                    pending = PendingDataImport(plan: try model.prepareDataImport(data, source: source), source: source)
                } catch {
                    problem = selectedFileName.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription
                }
            }
            .sheet(item: $pending) { item in
                ImportConfirmation(plan: item.plan, source: item.source) { dismiss() }
            }
            .alert("Delete all data from every synchronized device?", isPresented: $deleting) {
                Button("Yes, erase all", role: .destructive) {
                    model.eraseData()
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes all Habits, Completions, Day Notes, and categories from synchronized devices. A recovery backup is kept on this device under Recovery Backups. Example Habits will not return.") }
            .alert("Backup problem", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) { Button("OK") { problem = nil } } message: { Text(problem ?? "") }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }
}
private struct ImportConfirmation: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var plan: DataImportPlan
    let source: DataImportSource
    var onImported: () -> Void = {}
    @State private var mode: DataImportMode
    @State private var addWasActionable: Bool
    @State private var choices: [String: DuplicateDayResolution] = [:]
    @State private var problem: String?
    init(
        plan: DataImportPlan,
        source: DataImportSource,
        mode: DataImportMode? = nil,
        onImported: @escaping () -> Void = {}
    ) {
        self.source = source
        self.onImported = onImported
        _plan = State(initialValue: plan)
        _mode = State(initialValue: mode ?? plan.suggestedMode)
        _addWasActionable = State(initialValue: !plan.newHabits.isEmpty || !plan.newCategories.isEmpty)
    }
    private var replacing: Bool { mode == .replaceAllData }
    var body: some View {
        NavigationStack {
            Form {
                Section("How to import") {
                    Picker("Import mode", selection: $mode) {
                        Text("Add new habits").tag(DataImportMode.addNewHabits)
                        Text("Replace all data").tag(DataImportMode.replaceAllData)
                    }.pickerStyle(.segmented)
                }
                Section("File contents") {
                    if let date = plan.exportedAt { LabeledContent("Exported", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    LabeledContent("Active Habits", value: "\(plan.dataset.active.count)")
                    LabeledContent("Archived Habits", value: "\(plan.dataset.habits.filter(\.archived).count)")
                    LabeledContent("Recorded Habit Days", value: "\(plan.dataset.days.count)")
                    LabeledContent("Day Notes", value: "\(plan.dataset.days.values.filter { !$0.note.isEmpty }.count)")
                    LabeledContent("Categories", value: "\((plan.dataset.categories ?? []).count)")
                    if !replacing {
                        LabeledContent("Habits to add", value: "\(plan.newHabits.count)")
                        LabeledContent("Existing or deleted — skipped", value: "\(plan.dataset.habits.count - plan.newHabits.count)")
                        if plan.newHabits.isEmpty {
                            Text("No new Habits in this file. Add mode does not update Habits already imported or previously deleted. Choose Replace all data to restore this file instead.")
                                .accessibilityIdentifier("no-new-habits")
                        }
                    }
                }
                Section("Habits") {
                    ForEach(plan.dataset.habits) { habit in
                        VStack(alignment: .leading) {
                            Text("\(habit.emoji) \(habit.name)")
                            Text(habitSummary(habit))
                                .font(.caption).foregroundStyle(.secondary)
                            if !replacing && plan.unavailableHabitIDs.contains(habit.id) { Text("Existing or previously deleted; this Habit will not be imported again.").font(.caption) }
                            let categories = (plan.dataset.categories ?? []).filter { (habit.categoryIDs ?? []).contains($0.id) }
                            if !categories.isEmpty { Text(categories.map(\.name).joined(separator: ", ")).font(.caption) }
                        }
                    }
                }
                if !(plan.dataset.categories ?? []).isEmpty {
                    Section("Categories") {
                        ForEach(plan.dataset.categories ?? []) { category in Text(category.name) }
                        Text("Categories and assignments are preserved in your data and exports. Category filtering and editing are not available yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !plan.warnings.isEmpty {
                    Section("Changes to review") {
                        ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in Text(warning) }
                    }
                }
                ForEach(plan.conflicts) { conflict in
                    Section("\(conflict.habitName) · \(conflict.day)") {
                        Text("Multiple records: \(conflict.amounts.map(String.init).joined(separator: ", ")). Choose the intended count.")
                        Picker("Count", selection: Binding(get: { choices[conflict.id]?.rawValue ?? "" }, set: { choices[conflict.id] = DuplicateDayResolution(rawValue: $0) })) {
                            Text("Choose…").tag("")
                            ForEach(DuplicateDayResolution.allCases, id: \.self) { choice in
                                Text("\(choice.rawValue): \((try? conflict.count(choice)).map(String.init) ?? "too large")").tag(choice.rawValue)
                            }
                        }
                        .accessibilityIdentifier("duplicate-\(conflict.id)")
                    }
                }
                Section {
                    Text(replacing
                         ? "This replaces all data, settings, and habit order on synchronized devices. A recovery backup will be saved on this device first."
                         : "Only new Habit IDs are added. Existing habits, history, and preferences stay unchanged. Matching names are not treated as duplicates. A recovery backup will be saved before changes.")
                    Button(replacing ? "Replace Data and Restore" : "Import Data", role: replacing ? .destructive : nil) {
                        do {
                            if try model.applyDataImport(plan, mode: mode, conflictChoices: choices) { onImported() }
                        } catch { problem = error.localizedDescription }
                    }
                    .disabled((!replacing && !addWasActionable) || plan.conflicts.contains { choices[$0.id] == nil })
                    .accessibilityIdentifier("confirm-import")
                }
            }
            .navigationTitle(source == .openHabit ? "Open Habit import" : "HabitKit data import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: mode) { _, mode in
                if mode == .addNewHabits { refreshPlan() }
            }
            .onChange(of: model.data) { _, _ in
                if mode == .addNewHabits { refreshPlan() }
            }
            .alert("Import problem", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK") { problem = nil }
            } message: { Text(problem ?? "") }
        }
    }

    private func habitSummary(_ habit: Habit) -> String {
        guard let goal = habit.streakGoal, goal.period == .weekly else {
            return "Daily Target: \(habit.target)"
        }
        return "Daily Target: \(habit.target) · Weekly goal: \(goal.target) days"
    }

    private func refreshPlan() {
        do {
            let refreshed = try model.refreshDataImport(plan)
            addWasActionable = addWasActionable || !refreshed.newHabits.isEmpty || !refreshed.newCategories.isEmpty
            plan = refreshed
        }
        catch { problem = error.localizedDescription }
    }
}
private struct RecoveryBackupsView: View {
    @Environment(AppModel.self) private var model
    @State private var files: [URL] = []
    @State private var pending: PendingDataImport?
    @State private var problem: String?
    var body: some View {
        List {
            Section {
                Text("Saved locally before data changes. These files survive Delete All Data, but not uninstalling the app. Export a copy to keep it elsewhere.")
                if files.isEmpty { Text("No recovery backups yet.") }
                ForEach(files, id: \.self) { file in
                    VStack(alignment: .leading) {
                        Text((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.formatted(date: .abbreviated, time: .standard) ?? file.lastPathComponent).font(.caption)
                        HStack {
                            Button("Restore") {
                                do {
                                    let plan = try model.prepareDataImport(Data(contentsOf: file), source: .openHabit)
                                    pending = PendingDataImport(plan: plan, source: .openHabit)
                                }
                                catch { problem = error.localizedDescription }
                            }.buttonStyle(.bordered)
                            ShareLink("Export", item: file).buttonStyle(.bordered)
                        }
                    }
                }
                .onDelete { offsets in
                    do {
                        for index in offsets { try FileManager.default.removeItem(at: files[index]) }
                        files = try sharedStore().recoveryBackups()
                    } catch { problem = error.localizedDescription }
                }
            }
        }
        .navigationTitle("Recovery Backups")
        .onAppear {
            do { files = try sharedStore().recoveryBackups() }
            catch { problem = error.localizedDescription }
        }
        .sheet(item: $pending) { item in ImportConfirmation(plan: item.plan, source: item.source, mode: .replaceAllData) }
        .alert("Backup problem", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
    }
}
private struct ArchivedHabitsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Habit?
    var body: some View {
        List {
            if model.data.habits.filter(\.archived).isEmpty { Text("No Archived Habits").foregroundStyle(.secondary) }
            ForEach(model.data.habits.filter(\.archived)) { habit in
                HStack {
                    NavigationLink { HabitDetailView(habitID: habit.id) } label: { Text("\(habit.emoji) \(habit.name)") }
                    Button("Restore") { model.update { $0.append(.archive(habit.id, false)) } }.buttonStyle(.bordered)
                }.contextMenu { Button("Edit Habit") { editing = habit } }
            }
        }.navigationTitle("Archived Habits")
            .sheet(item: $editing) { habit in HabitEditor(habit: habit, isNew: false) }
    }
}
