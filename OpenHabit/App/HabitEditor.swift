import SwiftUI
import OpenHabitCore

struct HabitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit
    let isNew: Bool
    var onDelete: ((Habit) -> Void)?
    var onCreated: ((UUID) -> Void)?
    @State private var previewCount = 0
    @State private var deleting = false
    @State private var choosingEmoji = false
    @State private var sharingHabit: Habit?
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 14) {
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
                    Picker("Tracking", selection: counting) {
                        Text("Check off").tag(false)
                        Text("Count").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("tracking-mode")
                    if let counter = habit.counter {
                        StepWheel(step: counterStep, tint: habit.tint)
                        HStack(spacing: 8) {
                            ForEach([1, 5, 10, 25, 100], id: \.self) { value in
                                Button("+\(value)") { counterStep.wrappedValue = value }
                                    .buttonStyle(.bordered).tint(counter.step == value ? habit.tint : .secondary)
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                            }
                        }
                        TextField("Unit, like pushups, glasses, km or min", text: counterUnit)
                            .accessibilityIdentifier("counter-unit")
                    } else {
                        Stepper("Daily Target: \(habit.target)", value: $habit.target, in: 1...99)
                            .accessibilityIdentifier("daily-target")
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Try it out").font(.subheadline.weight(.medium))
                            Text(habit.progressText(previewCount)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if habit.counter != nil && previewCount > 0 {
                            Button("Reset") { previewCount = 0 }.font(.caption).buttonStyle(.borderless)
                        }
                        CompletionButton(habit: habit, count: previewCount) {
                            if habit.counter != nil { previewCount = min(Counter.maximumAmount, previewCount + habit.step) }
                            else { previewCount = previewCount >= habit.target ? 0 : previewCount + 1 }
                        }
                    }.padding(.vertical, 8)
                } header: { Text(habit.counter == nil ? "Daily Target" : "Counting") } footer: {
                    if habit.counter != nil {
                        Text("There’s no target: more is better. Each tap adds the chosen amount, and history tiles get darker on your stronger days. Touch and hold a Habit on the overview to undo a tap or set an exact amount.")
                    } else {
                        Text("Your current Daily Target also applies to all past Habit Days. Changing it may change how your history looks.")
                    }
                }
                Section {
                    Toggle("Track a streak", isOn: streakEnabled)
                    if habit.streakGoal != nil {
                        Picker("Streak period", selection: streakPeriod) {
                            Text("Daily").tag(StreakPeriod.daily)
                            Text("Weekly").tag(StreakPeriod.weekly)
                        }
                        .pickerStyle(.segmented)
                        if let goal = habit.streakGoal, let counter = habit.counter {
                            StreakAmountField(title: goal.period == .daily ? "Daily goal" : "Weekly goal", unit: counter.unit,
                                              value: streakAmount, range: goal.amountRange, step: counter.step)
                        } else if habit.streakGoal?.period == .weekly {
                            Stepper("Weekly Goal: \(habit.streakGoal?.target ?? 3) days", value: weeklyStreakTarget, in: 1...7)
                        }
                    }
                } header: { Text("Streak Goal") } footer: {
                    if let counter = habit.counter, let goal = habit.streakGoal {
                        let amount = "\((goal.amount ?? 1).formatted())\(counter.unit.isEmpty ? "" : " \(counter.unit)")"
                        Text(goal.period == .weekly
                             ? "A week extends the streak when its total reaches \(amount)."
                             : "A day extends the streak when it reaches \(amount).")
                    } else if habit.streakGoal?.period == .weekly {
                        Text("A week extends the streak when this Habit \(habit.counter == nil ? "reaches its Daily Target" : "records any amount") on the chosen number of days.")
                    } else {
                        Text("A day extends the streak when this Habit \(habit.counter == nil ? "reaches its Daily Target" : "records any amount").")
                    }
                }
                if !isNew && model.sharedHabit(for: habit.id) == nil {
                    Section {
                        if #available(iOS 18.0, *), !habit.archived {
                            Button {
                                sharingHabit = model.data.habit(habit.id)
                            } label: {
                                HStack {
                                    Label {
                                        Text("Share Habit").foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "square.and.arrow.up").foregroundStyle(.green)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(habit != model.data.habit(habit.id))
                        }
                        Button(habit.archived ? "Restore Habit" : "Archive Habit", systemImage: habit.archived ? "arrow.uturn.backward" : "archivebox") {
                            model.update { $0.append(.archive(habit.id, !habit.archived)) }; if model.error == nil { dismiss() }
                        }
                        Button(role: .destructive) { deleting = true } label: {
                            Label {
                                Text("Delete Habit")
                            } icon: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text("Actions")
                    } footer: {
                        if !habit.archived && habit != model.data.habit(habit.id) {
                            Text("Save changes before sharing this Habit.")
                        }
                    }
                } else if let state = model.sharedHabit(for: habit.id) {
                    Section {
                        Label("This Shared Habit cannot be archived.", systemImage: "person.2")
                    } footer: {
                        Text(state.membership.role == .owner
                             ? "The Owner can manage sharing here."
                             : "Only the Owner can change the Shared Habit definition.")
                    }
                    Section("Sharing") {
                        SharedHabitSharingControls(state: state)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle(isNew ? "New Habit" : "Edit Habit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save") {
                        habit.name = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.update { try $0.save(habit) }
                        if model.error == nil {
                            if isNew { onCreated?(habit.id) }
                            dismiss()
                        }
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
            .sheet(item: $sharingHabit) { SharedHabitSetupView(habit: $0) }
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

    private var counting: Binding<Bool> {
        Binding(
            get: { habit.counter != nil },
            set: { enabled in
                previewCount = 0
                if enabled {
                    habit.counter = habit.counter ?? Counter()
                    habit.target = 1
                    if habit.streakGoal != nil { habit.streakGoal?.amount = habit.streakGoal?.amount ?? habit.step }
                } else {
                    habit.counter = nil
                    habit.streakGoal?.amount = nil
                }
            }
        )
    }

    private var counterStep: Binding<Int> {
        Binding(get: { habit.step }, set: { habit.counter?.step = $0 })
    }

    private var counterUnit: Binding<String> {
        Binding(
            get: { habit.counter?.unit ?? "" },
            set: { habit.counter?.unit = String($0.replacingOccurrences(of: "\n", with: " ").prefix(12)) }
        )
    }

    private var streakEnabled: Binding<Bool> {
        Binding(
            get: { habit.streakGoal != nil },
            // A Counter Habit's goal starts at one tap's amount; the person can raise it.
            set: { enabled in habit.streakGoal = enabled ? StreakGoal(period: .daily, amount: habit.counter.map(\.step)) : nil }
        )
    }

    private var streakPeriod: Binding<StreakPeriod> {
        Binding(
            get: { habit.streakGoal?.period ?? .daily },
            set: { period in
                habit.streakGoal = StreakGoal(period: period, target: period == .weekly ? 3 : 1, amount: habit.counter.map(\.step))
            }
        )
    }

    private var streakAmount: Binding<Int> {
        Binding(get: { habit.streakGoal?.amount ?? habit.step }, set: { habit.streakGoal?.amount = $0 })
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
        // Everyday health
        "💧", "🏃", "📖", "🧘", "😴",
        // Movement and nutrition
        "🥗", "💪", "🚶", "🏋️", "🚴",
        "🏊", "🪥", "💊", "☀️", "📵",
        // Focus and consistency
        "✍️", "🧠", "✅", "🎯", "🔥",
        // Home, money, and wellbeing
        "🧹", "💰", "❤️", "🙏", "😊",
        // Growth and creativity
        "🌱", "🎨", "🎸", "☕️"
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
        .fullScreenCover(isPresented: $choosingCustomEmoji) {
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

/// "Each tap adds" row that expands into a wheel, like the date rows in Calendar.
private struct StepWheel: View {
    @Binding var step: Int
    let tint: Color
    @State private var expanded = false

    /// Fine steps where amounts are small, coarser ones above, so the wheel stays short.
    private static let choices = Array(1...50) + Array(stride(from: 55, through: 200, by: 5))
        + Array(stride(from: 250, through: 1_000, by: 50)) + Array(stride(from: 1_100, through: 5_000, by: 100))
        + Array(stride(from: 6_000, through: Counter.maximumStep, by: 1_000))

    var body: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            LabeledContent("Each tap adds") {
                Text("+\(step.formatted())")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(expanded ? tint : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("counter-step")
        if expanded {
            // Keep an amount typed elsewhere, such as an imported Habit's, selectable.
            let values = Self.choices.contains(step) ? Self.choices : (Self.choices + [step]).sorted()
            Picker("Each tap adds", selection: $step) {
                ForEach(values, id: \.self) { Text("+\($0.formatted())").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
        }
    }
}

/// A free amount for a Counter Habit's Streak Goal: type any number, or step by one tap's amount.
private struct StreakAmountField: View {
    let title: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        // One line at every width: the footer names the unit, so the row carries only the number.
        HStack(spacing: 10) {
            Text(title).lineLimit(1).layoutPriority(1)
            TextField(title, value: clamped, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .accessibilityLabel(unit.isEmpty ? title : "\(title), \(unit)")
                .accessibilityIdentifier("streak-amount")
            Stepper(title, value: clamped, in: range, step: step).labelsHidden().fixedSize()
        }
    }

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(range.upperBound, max(range.lowerBound, $0)) })
    }
}
