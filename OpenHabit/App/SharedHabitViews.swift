import SwiftUI
import OpenHabitCore
import UIKit

struct SharedHabitJoinView: View {
    @Environment(AppModel.self) private var model
    let offer: SharedHabitJoinOffer
    @State private var memberName = ""
    @State private var useExisting = false
    @State private var existingHabitID: UUID?
    @State private var joining = false

    private var privateHabits: [Habit] {
        model.data.active.filter { model.sharedHabit(for: $0.id) == nil }
    }

    private var selectedHabit: Habit? { existingHabitID.flatMap(model.data.habit) }
    private var validName: Bool {
        let trimmed = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 40
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invitation") {
                    LabeledContent("Habit") { Text("\(offer.snapshot.definition.emoji) \(offer.snapshot.definition.name)") }
                    if let owner = offer.snapshot.members.first(where: { $0.role == .owner }) {
                        LabeledContent("Owner", value: owner.name)
                    }
                    LabeledContent("Members", value: "\(offer.snapshot.members.count) of 10")
                    LabeledContent("Daily Target", value: "\(offer.snapshot.definition.target)")
                    if let goal = offer.snapshot.definition.streakGoal {
                        LabeledContent("Streak Goal", value: goal.period == .daily ? "Daily" : "\(goal.target) days each week")
                    }
                }

                Section {
                    Label("Every Member sees your Completion counts and progress.", systemImage: "chart.bar")
                    Label("Your Day Notes always remain private.", systemImage: "lock.fill")
                }

                Section("Your Member Name") {
                    TextField("Name shown to Members", text: $memberName)
                        .textContentType(.name)
                        .onChange(of: memberName) { _, value in memberName = String(value.prefix(40)) }
                }

                Section {
                    Picker("Local Habit", selection: $useExisting) {
                        Text("Start New").tag(false)
                        Text("Use Existing").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if useExisting {
                        if privateHabits.isEmpty {
                            ContentUnavailableView("No Private Habits", systemImage: "leaf", description: Text("Start a new Habit instead."))
                        } else {
                            Picker("Habit", selection: $existingHabitID) {
                                Text("Choose a Habit").tag(nil as UUID?)
                                ForEach(privateHabits) { habit in Text("\(habit.emoji) \(habit.name)").tag(habit.id as UUID?) }
                            }
                            if let selectedHabit { definitionChanges(from: selectedHabit) }
                        }
                    }
                } header: {
                    Text("Connect to Your Tracking")
                } footer: {
                    Text(useExisting
                         ? "The selected Habit adopts the shared definition and shares its complete Completion history. Categories, ordering, and Day Notes remain private."
                         : "A new Habit starts today. Nothing from your other Habits is shared.")
                }
            }
            .disabled(joining)
            .navigationTitle("Join Shared Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Decline") {
                        joining = true
                        Task { await model.decline(offer); joining = false }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(joining ? "Joining…" : "Join") {
                        joining = true
                        Task {
                            _ = await model.join(offer, memberName: memberName, existingHabitID: useExisting ? existingHabitID : nil)
                            joining = false
                        }
                    }
                    .disabled(!validName || (useExisting && existingHabitID == nil) || joining)
                }
            }
        }
    }

    @ViewBuilder
    private func definitionChanges(from habit: Habit) -> some View {
        let definition = offer.snapshot.definition
        VStack(alignment: .leading, spacing: 5) {
            Text("Changes before joining").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if habit.name != definition.name { Text("Name: \(habit.name) → \(definition.name)") }
            if habit.emoji != definition.emoji { Text("Emoji: \(habit.emoji) → \(definition.emoji)") }
            if habit.target != definition.target { Text("Daily Target: \(habit.target) → \(definition.target)") }
            if habit.detail != definition.detail { Text("Description will match the Shared Habit") }
            if habit.color != definition.color || habit.customColorRGB != definition.customColorRGB { Text("Color will match the Shared Habit") }
            if habit.streakGoal != definition.streakGoal { Text("Streak Goal will match the Shared Habit") }
            if habit.name == definition.name && habit.emoji == definition.emoji && habit.target == definition.target && habit.detail == definition.detail && habit.color == definition.color && habit.customColorRGB == definition.customColorRGB && habit.streakGoal == definition.streakGoal {
                Text("The definitions already match.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

struct SharedHabitSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    @State private var memberName = ""
    @State private var history = SharedHistoryChoice.fullHistory
    @State private var creating = false
    @State private var shared = false
    @State private var invitation: InvitationLink?
    @FocusState private var memberNameFocused: Bool

    private var validName: Bool {
        let trimmed = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 40
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name shown to Members", text: $memberName)
                        .textContentType(.name)
                        .focused($memberNameFocused)
                        .onChange(of: memberName) { _, value in memberName = String(value.prefix(40)) }
                } header: {
                    Text("Your Member Name")
                } footer: {
                    Text("This name belongs only to this Shared Habit. You can change it later.")
                }

                Section {
                    Picker("History", selection: $history) {
                        Text("Full History").tag(SharedHistoryChoice.fullHistory)
                        Text("Start Fresh").tag(SharedHistoryChoice.startFresh)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Your Shared History")
                } footer: {
                    Text(history == .startFresh
                         ? "Members see your Completion counts from today onward. Your earlier history stays private."
                         : "Current and future Members can see all existing Completion counts for this Habit. Day Notes always stay private.")
                }

                Section {
                    Label("Open Habit uses iCloud Sharing. It does not operate an account or synchronization server.", systemImage: "icloud")
                }
            }
            .disabled(creating)
            .navigationTitle("Share Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(creating) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(creating ? "Sharing…" : "Share") {
                        memberNameFocused = false
                        creating = true
                        Task {
                            if await model.share(habit, memberName: memberName, history: history) {
                                shared = true
                                if #available(iOS 18.0, *) {
                                    if let url = await model.createInvitation(for: habit.id) {
                                        invitation = InvitationLink(url: url)
                                    } else {
                                        dismiss()
                                    }
                                } else {
                                    dismiss()
                                }
                            }
                            creating = false
                        }
                    }
                    .disabled(!validName || creating)
                }
            }
            .onAppear { memberNameFocused = true }
            .sheet(item: $invitation, onDismiss: { if shared { dismiss() } }) { invitation in
                InvitationReadyView(invitation: invitation)
            }
        }
    }
}

struct SharedHabitMembersSection: View {
    @Environment(AppModel.self) private var model
    let state: SharedHabitState
    @State private var invitation: InvitationLink?
    @State private var inviting = false
    @State private var editingIdentity = false
    @State private var removing: SharedMember?
    @State private var stoppingShare = false
    @State private var leaving = false

    private var invitations: [SharedInvitation] {
        state.snapshot.invitations.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    private var membershipSummary: String {
        let memberCount = state.snapshot.members.count
        let members = memberCount == 1 ? "Member" : "Members"
        guard !invitations.isEmpty else { return "\(memberCount) \(members)" }
        return "\(memberCount) \(members) · \(invitations.count) Pending"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Members").font(.title2.bold())
                Spacer()
                Text(membershipSummary).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(state.snapshot.orderedMembers(currentMemberID: state.membership.memberID).enumerated()), id: \.element.id) { index, member in
                    NavigationLink {
                        SharedMemberDetailView(member: member, definition: state.snapshot.definition)
                    } label: {
                        SharedMemberRow(member: member, definition: state.snapshot.definition)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if state.membership.role == .owner && member.role != .owner {
                            Button("Remove Member", systemImage: "person.badge.minus", role: .destructive) { removing = member }
                        }
                    }
                    if index < state.snapshot.members.count - 1 { Divider().padding(.leading, 54) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

            if !invitations.isEmpty {
                Text("Invitations")
                    .font(.headline)
                    .padding(.top, 4)
                VStack(spacing: 0) {
                    ForEach(Array(invitations.enumerated()), id: \.element.id) { index, invitation in
                        if index > 0 { Divider().padding(.leading, 54) }
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.badge")
                                .frame(width: 30)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pending Invitation \(index + 1)")
                                Text(invitation.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Cancel Invitation", systemImage: "xmark", role: .destructive) {
                                Task { await model.cancelInvitation(invitation.id, habitID: state.membership.localHabitID) }
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Cancel Pending Invitation \(index + 1)")
                        }
                        .padding(14)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }

            if state.membership.role == .owner {
                if #available(iOS 18.0, *) {
                    Button(inviting ? "Creating Invitation…" : "Invite a Member", systemImage: "person.badge.plus") {
                        inviting = true
                        Task {
                            if let url = await model.createInvitation(for: state.membership.localHabitID) { invitation = InvitationLink(url: url) }
                            inviting = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(inviting || state.snapshot.members.count + state.snapshot.invitations.count >= 10)
                } else {
                    Text("Invitations require iOS 18 or later.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button("Edit My Member Identity", systemImage: "person.crop.circle") { editingIdentity = true }
                .buttonStyle(.bordered)
            if state.membership.role == .owner {
                Button("Stop Sharing", systemImage: "person.2.slash", role: .destructive) { stoppingShare = true }
                    .buttonStyle(.bordered)
            } else {
                Button("Leave Shared Habit", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { leaving = true }
                    .buttonStyle(.bordered)
            }
        }
        .sheet(item: $invitation) { invitation in
            InvitationReadyView(invitation: invitation)
        }
        .sheet(isPresented: $editingIdentity) {
            if let member = state.snapshot.members.first(where: { $0.id == state.membership.memberID }) {
                MemberIdentityEditor(habitID: state.membership.localHabitID, member: member)
            }
        }
        .confirmationDialog("Remove \(removing?.name ?? "Member")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove Member", role: .destructive) {
                if let member = removing { Task { await model.removeMember(member, habitID: state.membership.localHabitID) } }
                removing = nil
            }
        } message: {
            Text("They will stop seeing shared progress. Their Habit and personal history will remain private on their devices.")
        }
        .alert("Stop sharing this Habit?", isPresented: $stoppingShare) {
            Button("Stop Sharing", role: .destructive) { Task { _ = await model.stopSharing(state.membership.localHabitID) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shared visibility will end for everyone. Your Habit, Completions, and Day Notes remain local, and other Members keep their Habits and personal history.")
        }
        .alert("Leave this Shared Habit?", isPresented: $leaving) {
            Button("Leave Shared Habit", role: .destructive) { Task { _ = await model.leaveSharedHabit(state.membership.localHabitID) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Habit, Completions, and Day Notes remain on this device as a Private Habit. Shared visibility ends.")
        }
    }
}

private struct MemberIdentityEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let habitID: UUID
    @State private var member: SharedMember

    init(habitID: UUID, member: SharedMember) {
        self.habitID = habitID
        _member = State(initialValue: member)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Member Name") {
                    TextField("Name", text: $member.name)
                        .textContentType(.name)
                        .onChange(of: member.name) { _, value in member.name = String(value.prefix(40)) }
                }
                Section("Member Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(SharedMember.palette.indices, id: \.self) { index in
                            Button {
                                member.colorIndex = index
                            } label: {
                                Circle().fill(memberColor(index)).frame(width: 42, height: 42)
                                    .overlay { if member.colorIndex == index { Image(systemName: "checkmark").bold().foregroundStyle(.white) } }
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Member Color \(index + 1)")
                            .accessibilityAddTraits(member.colorIndex == index ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Member Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.updateMember(habitID: habitID, name: member.name, colorIndex: member.colorIndex)
                        if model.error == nil { dismiss() }
                    }
                    .disabled(member.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func memberColor(_ index: Int) -> Color {
        let rgb = SharedMember.palette[index]
        return Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

private struct InvitationLink: Identifiable {
    let id = UUID()
    let url: URL
}

private struct InvitationReadyView: View {
    @Environment(\.dismiss) private var dismiss
    let invitation: InvitationLink
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "person.2.badge.plus").font(.system(size: 56)).foregroundStyle(.green)
                Text("Invitation Ready").font(.title.bold())
                Text("Send this private, single-use Invitation directly to one person. It does not expire automatically.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                ShareLink(item: invitation.url, subject: Text("Join my Shared Habit")) {
                    Label("Send Invitation", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(copied ? "Invitation Link Copied" : "Copy Invitation Link", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.url = invitation.url
                    copied = true
                }
                .buttonStyle(.bordered)
            }
            .padding(28)
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct SharedMemberRow: View {
    let member: SharedMember
    let definition: SharedHabitDefinition

    private var dataset: Dataset { Dataset().dataset(for: member, definition: definition) }
    private var habit: Habit { dataset.habits[0] }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(member.tint).frame(width: 30, height: 30)
                .overlay { Text(String(member.name.prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(.white) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name).font(.headline).lineLimit(1).layoutPriority(1)
                SevenDayProgress(member: member, definition: definition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                let today = member.counts[LocalDay.string()] ?? 0
                Text("\(today) / \(definition.target)").font(.subheadline.monospacedDigit().weight(.semibold))
                if definition.streakGoal != nil {
                    Label("\(dataset.currentStreak(for: habit))", systemImage: "flame.fill")
                        .labelStyle(.titleAndIcon).font(.caption2).foregroundStyle(member.tint)
                }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct SevenDayProgress: View {
    let member: SharedMember
    let definition: SharedHabitDefinition

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let count = member.counts[day] ?? 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(member.tint.opacity(count == 0 ? 0.10 : 0.25 + 0.75 * min(1, Double(count) / Double(definition.target))))
                    .frame(width: 13, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var days: [String] {
        (0..<7).reversed().compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: Date()).map { LocalDay.string($0) }
        }
    }
}

struct SharedMemberDetailView: View {
    let member: SharedMember
    let definition: SharedHabitDefinition

    private var dataset: Dataset { Dataset().dataset(for: member, definition: definition) }
    private var habit: Habit { dataset.habits[0] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Circle().fill(member.tint).frame(width: 48, height: 48)
                        .overlay { Text(String(member.name.prefix(1)).uppercased()).font(.headline).foregroundStyle(.white) }
                    VStack(alignment: .leading) {
                        Text(member.name).font(.title.bold())
                        if member.role == .owner { Label("Owner", systemImage: "crown.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                HStack(spacing: 10) {
                    SharedMetric(value: "\(member.counts[LocalDay.string()] ?? 0) / \(definition.target)", label: "Today", color: member.tint)
                    if habit.streakGoal != nil {
                        SharedMetric(value: "\(dataset.currentStreak(for: habit))", label: "Current Streak", color: member.tint)
                    }
                }
                ScrollView(.horizontal) {
                    HistoryGrid(habit: habit, data: dataset, weeks: 53)
                        .frame(width: 1_035)
                }
                .defaultScrollAnchor(.trailing)
                Text("Only Completion counts are shared. Day Notes remain private.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Member Progress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SharedMetric: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title2.monospacedDigit().bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension SharedMember {
    var tint: Color {
        Color(
            red: Double((colorRGB >> 16) & 0xFF) / 255,
            green: Double((colorRGB >> 8) & 0xFF) / 255,
            blue: Double(colorRGB & 0xFF) / 255
        )
    }
}
