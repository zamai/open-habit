import SwiftUI
import OpenHabitCore

struct HabitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit
    let isNew: Bool
    @State private var previewCount = 0
    @State private var deleting = false
    private var valid: Bool { (try? habit.validate()) != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        TextField("Emoji", text: $habit.emoji).font(.largeTitle).frame(width: 60).multilineTextAlignment(.center)
                            .onChange(of: habit.emoji) { _, value in habit.emoji = String(value.prefix(1)) }
                            .accessibilityIdentifier("habit-emoji")
                        TextField("Habit name", text: $habit.name).onChange(of: habit.name) { _, value in habit.name = String(value.prefix(60)) }
                            .accessibilityIdentifier("habit-name")
                    }.padding(.vertical, 8)
                    TextField("One-sentence description (optional)", text: $habit.detail)
                        .onChange(of: habit.detail) { _, value in habit.detail = String(value.replacingOccurrences(of: "\n", with: " ").prefix(160)) }
                } header: { Text("Make it yours") } footer: { Text("One emoji. A small, positive action to practise every day.") }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 14) {
                        ForEach(HabitColor.allCases, id: \.self) { color in
                            Button { habit.color = color; habit.customColorRGB = nil } label: {
                                Circle().fill(color.tint).frame(width: 40, height: 40)
                                    .overlay { if habit.customColorRGB == nil && habit.color == color { Image(systemName: "checkmark").font(.headline).foregroundStyle(.white) } }
                                    .frame(width: 48, height: 48)
                            }.buttonStyle(.plain).accessibilityLabel(color.rawValue.capitalized)
                                .accessibilityAddTraits(habit.customColorRGB == nil && habit.color == color ? .isSelected : [])
                        }
                    }.padding(.vertical, 4)
                    ColorPicker("Custom color", selection: Binding(
                        get: { habit.tint },
                        set: { color in
                            let resolved = color.resolve(in: EnvironmentValues())
                            let red = UInt32((min(1, max(0, resolved.red)) * 255).rounded())
                            let green = UInt32((min(1, max(0, resolved.green)) * 255).rounded())
                            let blue = UInt32((min(1, max(0, resolved.blue)) * 255).rounded())
                            habit.customColorRGB = (red << 16) | (green << 8) | blue
                        }
                    ), supportsOpacity: false)
                    .accessibilityIdentifier("custom-habit-color")
                }
                Section {
                    Stepper("Daily Target: \(habit.target)", value: $habit.target, in: 1...99)
                        .accessibilityIdentifier("daily-target")
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Try it out").font(.subheadline.weight(.medium))
                            Text("\(previewCount) of \(habit.target) Completions").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        CompletionButton(habit: habit, count: previewCount) { previewCount = previewCount >= habit.target ? 0 : previewCount + 1 }
                    }.padding(.vertical, 8)
                } footer: { Text("Your current Daily Target also applies to all past Habit Days. Changing it may change how your history looks.") }
                if !isNew {
                    Section {
                        Button(habit.archived ? "Restore Habit" : "Archive Habit", systemImage: habit.archived ? "arrow.uturn.backward" : "archivebox") {
                            model.update { $0.append(.archive(habit.id, !habit.archived)) }; if model.error == nil { dismiss() }
                        }
                        Button("Delete Habit", systemImage: "trash", role: .destructive) { deleting = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Habit" : "Edit Habit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save") {
                        habit.name = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.update { try $0.save(habit) }; if model.error == nil { dismiss() }
                    }.disabled(!valid).accessibilityIdentifier("save-habit")
                }
            }
            .confirmationDialog("Delete this Habit permanently?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete Habit and History", role: .destructive) { model.delete(habit.id); if model.error == nil { dismiss() } }
            } message: { Text("Its Completions and Day Notes will be removed from all synchronized devices.") }
        }
    }
}
