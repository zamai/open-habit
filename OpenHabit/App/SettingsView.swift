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
private struct PendingBackup: Identifiable {
    let id = UUID()
    let backup: Backup
}
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupDocument(data: Data())
    @State private var pending: PendingBackup?
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
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    Button { importing = true } label: {
                        Label {
                            Text("Restore from Backup").foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                }
                Section {
                    NavigationLink("About Open Habit") {
                        VStack(spacing: 20) {
                            Image(systemName: "leaf.circle.fill").font(.system(size: 72)).foregroundStyle(.green)
                            Text("Open Habit").font(.largeTitle.bold())
                            Text("A little, every day.").font(.title3)
                            Text("Private habits. Small steps. Your data.\nBuilt for iPhone and iPad, with no Open Habit account and no hosted user-data service.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Text("Version 1.0").font(.caption).foregroundStyle(.secondary)
                        }.padding(30).navigationTitle("About")
                    }
                    Button("Delete All Data", role: .destructive) { deleting = true }
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Open-Habit-\(LocalDay.string())") { result in if case .failure(let error) = result { problem = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    pending = PendingBackup(backup: try Backup.decode(Data(contentsOf: url)))
                } catch { problem = error.localizedDescription }
            }
            .sheet(item: $pending) { item in RestoreConfirmation(backup: item.backup) }
            .alert("Delete all data from every synchronized device?", isPresented: $deleting) {
                Button("Yes, erase all", role: .destructive) {
                    model.update { journal in var empty = Dataset(); empty.initialized = true; empty.settings.examplesDismissed = true; journal.append(.replace(empty)) }
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This permanently removes all Habits, Completions, and Day Notes. Export a backup first if you want to keep a copy. Example Habits will not return.") }
            .alert("Backup problem", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) { Button("OK") { problem = nil } } message: { Text(problem ?? "") }
        }
    }
}
private struct RestoreConfirmation: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let backup: Backup
    var body: some View {
        NavigationStack {
            Form {
                Section("Backup contents") {
                    LabeledContent("Exported", value: backup.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Active Habits", value: "\(backup.dataset.active.count)")
                    LabeledContent("Archived Habits", value: "\(backup.dataset.habits.filter(\.archived).count)")
                    LabeledContent("Recorded Habit Days", value: "\(backup.dataset.days.count)")
                    LabeledContent("Day Notes", value: "\(backup.dataset.days.values.filter { !$0.note.isEmpty }.count)")
                }
                Section {
                    Text("Restoring replaces your current dataset, including settings and habit order. The replacement will synchronize to your other devices. This cannot be undone without another backup.")
                    Button("Replace Data and Restore", role: .destructive) {
                        model.update { try $0.restore(backup) }; if model.error == nil { dismiss() }
                    }
                }
            }.navigationTitle("Restore from Backup").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
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
