import SwiftUI
import OpenHabitCore
import UIKit

struct SharedHabitJoinView: View {
    private enum Step: Int, Hashable {
        case name, review, tracking

        var title: String {
            switch self {
            case .name: "Your Name"
            case .review: "Review Habit"
            case .tracking: "Choose Your Habit"
            }
        }
    }

    private enum Action { case join, decline }

    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let offer: SharedHabitJoinOffer
    @State private var path: [Step] = []
    @State private var memberName = ""
    @State private var useExisting = false
    @State private var existingHabitID: UUID?
    @State private var action: Action?
    @FocusState private var memberNameFocused: Bool

    private var privateHabits: [Habit] {
        model.data.active.filter { model.sharedHabit(for: $0.id) == nil }
    }

    private var selectedHabit: Habit? { privateHabits.first { $0.id == existingHabitID } }
    private var trimmedName: String { memberName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validName: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 40
    }

    var body: some View {
        NavigationStack(path: $path) {
            page(.name)
                .navigationDestination(for: Step.self) { page($0) }
        }
    }

    private func page(_ step: Step) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Step \(step.rawValue + 1) of 3")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    ProgressView(value: Double(step.rawValue + 1), total: 3)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            switch step {
            case .name: nameStep
            case .review: reviewStep
            case .tracking: trackingStep
            }
        }
        .disabled(action != nil)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(step.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(action != nil)
        .safeAreaInset(edge: .bottom, spacing: 0) { primaryAction(for: step) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    memberNameFocused = false
                    action = .decline
                    Task { await model.decline(offer); action = nil }
                } label: {
                    if action == .decline {
                        ProgressView().accessibilityLabel("Declining invitation")
                    } else {
                        Text("Decline")
                    }
                }
                .disabled(action != nil)
            }
        }
        .onAppear { if step == .name { memberNameFocused = true } }
    }

    private var nameStep: some View {
        Section {
            TextField("Your Member Name", text: $memberName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($memberNameFocused)
                .submitLabel(.continue)
                .onSubmit { advance(from: .name) }
                .onChange(of: memberName) { _, value in memberName = String(value.prefix(40)) }
                .accessibilityIdentifier("join-member-name")
        } header: {
            Text("What should Members call you?")
        } footer: {
            Text("This name is only for this Shared Habit. You can change it later.")
        }
    }

    @ViewBuilder private var reviewStep: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(offer.snapshot.definition.emoji)
                    .font(.largeTitle).accessibilityHidden(true)
                Text(offer.snapshot.definition.name).font(.title2.bold())
                if !offer.snapshot.definition.detail.isEmpty {
                    Text(offer.snapshot.definition.detail).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            if let owner = offer.snapshot.members.first(where: { $0.role == .owner }) {
                LabeledContent("Invited by", value: owner.name)
            }
            LabeledContent("Members", value: "\(offer.snapshot.members.count) of 10")
            LabeledContent("Daily Target", value: "\(offer.snapshot.definition.target)")
            if let goal = offer.snapshot.definition.streakGoal {
                LabeledContent("Streak Goal", value: goal.period == .daily ? "Daily" : "\(goal.target) days each week")
            }
        }

        Section("What you share") {
            Label("Members see your Completion counts and progress.", systemImage: "person.2")
            Label("Your Day Notes always stay private.", systemImage: "lock.fill")
        }
    }

    @ViewBuilder private var trackingStep: some View {
        Section {
            trackingOption(existing: false, title: "Start New", detail: "Create a new Habit. Your Shared History starts today.", symbol: "plus.circle")
            trackingOption(existing: true, title: "Use Existing Habit", detail: "Connect a Private Habit and share its full Completion history.", symbol: "link")
                .disabled(privateHabits.isEmpty)
        } header: {
            Text("How would you like to track this Habit?")
        } footer: {
            if privateHabits.isEmpty {
                Text("You have no Private Habits to connect. Start a new Habit to join.")
            }
        }

        if useExisting {
            Section {
                Picker("Habit", selection: $existingHabitID) {
                    Text("Choose a Habit").tag(nil as UUID?)
                    ForEach(privateHabits) { habit in
                        Text("\(habit.emoji) \(habit.name)").tag(habit.id as UUID?)
                    }
                }
                .accessibilityIdentifier("join-existing-habit")
                if let selectedHabit { definitionChanges(from: selectedHabit) }
            } header: {
                Text("Connect a Private Habit")
            } footer: {
                Text("Its definition will match the Shared Habit. Its full Completion history will be visible to all Members. Day Notes, Categories, and ordering stay private.")
            }
        }
    }

    private func trackingOption(existing: Bool, title: String, detail: String, symbol: String) -> some View {
        Button { useExisting = existing } label: {
            VStack(alignment: .leading, spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    HStack {
                        Image(systemName: symbol).foregroundStyle(.tint).accessibilityHidden(true)
                        Spacer()
                        selectionMark(existing: existing)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: symbol).font(.title3).foregroundStyle(.tint)
                            .frame(width: 28).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.headline).foregroundStyle(.primary)
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                        selectionMark(existing: existing)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(useExisting == existing ? .isSelected : [])
        .accessibilityIdentifier(existing ? "join-use-existing" : "join-start-new")
    }

    private func selectionMark(existing: Bool) -> some View {
        Image(systemName: useExisting == existing ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(useExisting == existing ? Color.accentColor : Color.secondary)
            .accessibilityHidden(true)
    }

    private func primaryAction(for step: Step) -> some View {
        VStack {
            Button { advance(from: step) } label: {
                HStack(spacing: 8) {
                    if action == .join { ProgressView().tint(.white) }
                    if action == .join {
                        Text("Joining…")
                    } else if step == .tracking {
                        ViewThatFits(in: .horizontal) {
                            Text("Join Shared Habit").fixedSize()
                            Text("Join")
                        }
                    } else {
                        Text("Continue")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(action != nil || !validName || (step == .tracking && useExisting && selectedHabit == nil))
            .accessibilityLabel(action == .join ? "Joining Shared Habit" : step == .tracking ? "Join Shared Habit" : "Continue")
            .accessibilityIdentifier(step == .tracking ? "join-confirm" : "join-continue")
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
        .background(.bar)
    }

    private func advance(from step: Step) {
        guard action == nil, validName else { return }
        memberNameFocused = false
        switch step {
        case .name: path.append(.review)
        case .review: path.append(.tracking)
        case .tracking:
            guard !useExisting || selectedHabit != nil else { return }
            action = .join
            Task {
                _ = await model.join(offer, memberName: trimmedName, existingHabitID: useExisting ? existingHabitID : nil)
                action = nil
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
    @State private var removing: SharedMember?

    private var membershipSummary: String {
        let memberCount = state.snapshot.members.count
        let members = memberCount == 1 ? "Member" : "Members"
        guard !state.snapshot.invitations.isEmpty else { return "\(memberCount) \(members)" }
        return "\(memberCount) \(members) · \(state.snapshot.invitations.count) Pending"
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
                        SharedMemberDetailView(
                            member: member,
                            definition: state.snapshot.definition,
                            editableHabitID: member.id == state.membership.memberID ? state.membership.localHabitID : nil
                        )
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
            SharedHabitSharingControls(state: state)
        }
        .confirmationDialog("Remove \(removing?.name ?? "Member")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove Member", role: .destructive) {
                if let member = removing { Task { await model.removeMember(member, habitID: state.membership.localHabitID) } }
                removing = nil
            }
        } message: {
            Text("They will stop seeing shared progress. Their Habit and personal history will remain private on their devices.")
        }
    }
}

struct SharedHabitSharingControls: View {
    @Environment(AppModel.self) private var model
    let state: SharedHabitState
    @State private var invitation: InvitationLink?
    @State private var inviting = false
    @State private var stoppingShare = false
    @State private var leaving = false

    private var invitations: [SharedInvitation] {
        state.snapshot.invitations.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
    @Environment(AppModel.self) private var model
    let member: SharedMember
    let definition: SharedHabitDefinition
    let editableHabitID: UUID?
    @State private var editingIdentity = false

    private var displayedMember: SharedMember {
        guard let editableHabitID,
              let updatedMember = model.sharedHabit(for: editableHabitID)?.snapshot.members.first(where: { $0.id == member.id }) else {
            return member
        }
        return updatedMember
    }
    private var dataset: Dataset { Dataset().dataset(for: displayedMember, definition: definition) }
    private var habit: Habit { dataset.habits[0] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Circle().fill(displayedMember.tint).frame(width: 48, height: 48)
                        .overlay { Text(String(displayedMember.name.prefix(1)).uppercased()).font(.headline).foregroundStyle(.white) }
                    VStack(alignment: .leading) {
                        HStack(spacing: 4) {
                            Text(displayedMember.name).font(.title.bold())
                            if editableHabitID != nil {
                                Button {
                                    editingIdentity = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Edit My Member Identity")
                                .accessibilityHint("Edit your Member Name and Member Color")
                            }
                        }
                        if displayedMember.role == .owner { Label("Owner", systemImage: "crown.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                HStack(spacing: 10) {
                    SharedMetric(value: "\(displayedMember.counts[LocalDay.string()] ?? 0) / \(definition.target)", label: "Today", color: displayedMember.tint)
                    if habit.streakGoal != nil {
                        SharedMetric(value: "\(dataset.currentStreak(for: habit))", label: "Current Streak", color: displayedMember.tint)
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
        .sheet(isPresented: $editingIdentity) {
            if let editableHabitID {
                MemberIdentityEditor(habitID: editableHabitID, member: displayedMember)
            }
        }
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

#if DEBUG && targetEnvironment(simulator)
@MainActor
enum SharedHabitJoinPreview {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--preview-join") }

    static func makeModel(withPrivateHabit: Bool = true) -> AppModel {
        let model = AppModel()
        if withPrivateHabit {
            model.data.habits = [Habit(name: "Reading", emoji: "📖", target: 1)]
        }
        let habit = Habit(name: "Read together", emoji: "📖", detail: "Make a little room for a good book each day.", target: 2)
        let definition = SharedHabitDefinition(habit: habit, weekStart: .monday)
        let owner = SharedMember(name: "Sam", colorIndex: 0, role: .owner)
        model.pendingJoin = SharedHabitJoinOffer(
            snapshot: SharedHabitSnapshot(definition: definition, members: [owner]),
            zoneName: "preview", zoneOwnerName: "preview", shareRecordName: "preview"
        )
        return model
    }
}

#Preview("Join invitation") {
    let model = SharedHabitJoinPreview.makeModel()
    SharedHabitJoinView(offer: model.pendingJoin!).environment(model).tint(.green)
}

#Preview("Join without Private Habits") {
    let model = SharedHabitJoinPreview.makeModel(withPrivateHabit: false)
    SharedHabitJoinView(offer: model.pendingJoin!).environment(model).tint(.green)
}

#Preview("Join in Dark Mode") {
    let model = SharedHabitJoinPreview.makeModel()
    SharedHabitJoinView(offer: model.pendingJoin!).environment(model).tint(.green)
        .preferredColorScheme(.dark)
}
#endif
