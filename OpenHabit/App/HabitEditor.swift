import SwiftUI
import OpenHabitCore

struct HabitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit
    let isNew: Bool
    var onDelete: ((Habit) -> Void)?
    @State private var previewCount = 0
    @State private var deleting = false
    @State private var choosingEmoji = false
    private var valid: Bool { (try? habit.validate()) != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Button { choosingEmoji = true } label: {
                            ZStack(alignment: .bottomTrailing) {
                                Text(habit.emoji).font(.largeTitle)
                                Image(systemName: "chevron.down.circle.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 60, height: 52)
                            .contentShape(Rectangle())
                        }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Choose emoji, current selection \(habit.emoji)")
                            .accessibilityIdentifier("habit-emoji")
                        TextField("Habit name", text: $habit.name).onChange(of: habit.name) { _, value in habit.name = String(value.prefix(60)) }
                            .accessibilityIdentifier("habit-name")
                    }.padding(.vertical, 8)
                    TextField("Description", text: $habit.detail)
                        .onChange(of: habit.detail) { _, value in habit.detail = String(value.replacingOccurrences(of: "\n", with: " ").prefix(160)) }
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(HabitColor.allCases, id: \.self) { color in
                            Button { habit.color = color; habit.customColorRGB = nil } label: {
                                Circle().fill(color.tint).frame(width: 40, height: 40)
                                    .overlay { if habit.customColorRGB == nil && habit.color == color { Image(systemName: "checkmark").font(.headline).foregroundStyle(.white) } }
                                    .frame(width: 48, height: 48)
                            }.buttonStyle(.plain).accessibilityLabel(color.rawValue.capitalized)
                                .accessibilityAddTraits(habit.customColorRGB == nil && habit.color == color ? .isSelected : [])
                        }
                        ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 48, height: 48)
                            .accessibilityLabel("Custom color")
                            .accessibilityIdentifier("custom-habit-color")
                            .accessibilityAddTraits(habit.customColorRGB != nil ? .isSelected : [])
                    }.padding(.vertical, 4)
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
                Section {
                    Toggle("Track a streak", isOn: streakEnabled)
                    if habit.streakGoal != nil {
                        Picker("Streak period", selection: streakPeriod) {
                            Text("Daily").tag(StreakPeriod.daily)
                            Text("Weekly").tag(StreakPeriod.weekly)
                        }
                        .pickerStyle(.segmented)
                        if habit.streakGoal?.period == .weekly {
                            Stepper("Weekly Goal: \(habit.streakGoal?.target ?? 3) days", value: weeklyStreakTarget, in: 1...7)
                        }
                    }
                } header: { Text("Streak Goal") } footer: {
                    if habit.streakGoal?.period == .weekly {
                        Text("A week extends the streak when this Habit reaches its Daily Target on the chosen number of days.")
                    } else {
                        Text("A day extends the streak when this Habit reaches its Daily Target.")
                    }
                }
                if !isNew && model.sharedHabit(for: habit.id) == nil {
                    Section {
                        Button(habit.archived ? "Restore Habit" : "Archive Habit", systemImage: habit.archived ? "arrow.uturn.backward" : "archivebox") {
                            model.update { $0.append(.archive(habit.id, !habit.archived)) }; if model.error == nil { dismiss() }
                        }
                        Button("Delete Habit", systemImage: "trash", role: .destructive) { deleting = true }
                    }
                } else if let state = model.sharedHabit(for: habit.id) {
                    Section {
                        Label("This Shared Habit cannot be archived.", systemImage: "person.2")
                    } footer: {
                        Text(state.membership.role == .owner
                             ? "Manage or stop sharing from the Members section in Habit Detail."
                             : "Only the Owner can change the Shared Habit definition.")
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
            .alert("Delete this Habit permanently?", isPresented: $deleting) {
                Button("Delete", role: .destructive) {
                    if let onDelete {
                        onDelete(habit)
                        dismiss()
                    } else {
                        model.delete(habit.id)
                        if model.error == nil { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Its Completions and Day Notes will be removed from all synchronized devices.") }
            .sheet(isPresented: $choosingEmoji) { HabitEmojiPicker(selection: $habit.emoji) }
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { habit.tint },
            set: { color in
                let resolved = color.resolve(in: EnvironmentValues())
                let red = UInt32((min(1, max(0, resolved.red)) * 255).rounded())
                let green = UInt32((min(1, max(0, resolved.green)) * 255).rounded())
                let blue = UInt32((min(1, max(0, resolved.blue)) * 255).rounded())
                habit.customColorRGB = (red << 16) | (green << 8) | blue
            }
        )
    }

    private var streakEnabled: Binding<Bool> {
        Binding(
            get: { habit.streakGoal != nil },
            set: { enabled in habit.streakGoal = enabled ? StreakGoal(period: .daily) : nil }
        )
    }

    private var streakPeriod: Binding<StreakPeriod> {
        Binding(
            get: { habit.streakGoal?.period ?? .daily },
            set: { period in habit.streakGoal = StreakGoal(period: period, target: period == .weekly ? 3 : 1) }
        )
    }

    private var weeklyStreakTarget: Binding<Int> {
        Binding(
            get: { habit.streakGoal?.target ?? 3 },
            set: { habit.streakGoal = StreakGoal(period: .weekly, target: $0) }
        )
    }
}

private struct HabitEmojiPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var choosingCustomEmoji = false
    private let choices = [
        "🌱", "🌿", "🌳", "🌻", "✨", "⭐️", "🔥", "💪",
        "🏃", "🚶", "🚴", "🏊", "🧘", "🏋️", "⚽️", "🏀",
        "💧", "🥤", "🍎", "🥗", "🥕", "🍳", "☕️", "🫖",
        "📖", "✍️", "📝", "🎓", "🧠", "💻", "🎨", "🎸",
        "🎹", "🎧", "📷", "🧹", "🧺", "🛏️", "🚿", "🪥",
        "💊", "🩺", "😴", "⏰", "📵", "💰", "📅", "✅",
        "🙏", "❤️", "😊", "🫶", "👨‍👩‍👧‍👦", "🐕", "🐈", "🌍",
        "☀️", "🌙", "🏠", "🚗", "✈️", "🎯", "🏆", "🔁"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                    ForEach(choices, id: \.self) { emoji in
                        Button {
                            selection = emoji
                            dismiss()
                        } label: {
                            Text(emoji).font(.system(size: 30))
                                .frame(width: 52, height: 52)
                                .background(selection == emoji ? Color.accentColor.opacity(0.18) : Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(selection == emoji ? Color.accentColor : .clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(emoji)")
                        .accessibilityAddTraits(selection == emoji ? .isSelected : [])
                    }
                    Button { choosingCustomEmoji = true } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 24))
                            Text("Custom")
                                .font(.caption2.weight(.medium))
                        }
                        .frame(width: 52, height: 52)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose a custom emoji")
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Choose Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $choosingCustomEmoji) {
            CustomEmojiPicker(selection: $selection) { dismiss() }
        }
    }
}

private struct CustomEmojiPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    let finish: () -> Void
    @State private var emoji = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Choose any emoji from the system keyboard.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                SystemEmojiField(text: $emoji)
                    .frame(height: 76)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Custom emoji")
                    .accessibilityIdentifier("custom-emoji")
                Text(validEmoji ? "One emoji selected" : "Select one emoji")
                    .font(.footnote)
                    .foregroundStyle(validEmoji ? Color.accentColor : .secondary)
                Spacer()
            }
            .padding(20)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Custom Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Emoji") {
                        selection = emoji
                        dismiss()
                        finish()
                    }
                    .disabled(!validEmoji)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var validEmoji: Bool {
        emoji.count == 1 && emoji.unicodeScalars.contains {
            $0.properties.isEmojiPresentation || $0.value == 0xFE0F || ($0.properties.isEmoji && $0.value > 0x238C)
        }
    }
}

private struct SystemEmojiField: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 44)
        field.textAlignment = .center
        field.autocorrectionType = .no
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        if field.text != text { field.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private var parent: SystemEmojiField

        init(_ parent: SystemEmojiField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            let value = field.text ?? ""
            let latestEmoji = value.last.map(String.init) ?? ""
            if field.text != latestEmoji { field.text = latestEmoji }
            parent.text = latestEmoji
        }
    }
}

private final class EmojiTextField: UITextField {
    override var textInputContextIdentifier: String? { "OpenHabit.EmojiPicker" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}
