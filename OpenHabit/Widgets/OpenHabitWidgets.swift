import SwiftUI
import WidgetKit
import AppIntents
import OpenHabitCore

struct SingleHabitConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a Habit"
    static let description = IntentDescription("Track one active Habit from your Home Screen.")
    @Parameter(title: "Habit") var habit: ActiveHabitEntity?
}
struct ThreeHabitConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose three Habits"
    static let description = IntentDescription("Choose the active Habit in each row. Unavailable Habits keep their place until you reconfigure the widget.")
    @Parameter(title: "First Habit") var first: ActiveHabitEntity?
    @Parameter(title: "Second Habit") var second: ActiveHabitEntity?
    @Parameter(title: "Third Habit") var third: ActiveHabitEntity?
}
struct SixHabitConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose six Habits"
    static let description = IntentDescription("Choose the active Habit in each row. Unavailable Habits keep their place until you reconfigure the widget.")
    @Parameter(title: "First Habit") var first: ActiveHabitEntity?
    @Parameter(title: "Second Habit") var second: ActiveHabitEntity?
    @Parameter(title: "Third Habit") var third: ActiveHabitEntity?
    @Parameter(title: "Fourth Habit") var fourth: ActiveHabitEntity?
    @Parameter(title: "Fifth Habit") var fifth: ActiveHabitEntity?
    @Parameter(title: "Sixth Habit") var sixth: ActiveHabitEntity?
}
struct SingleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitEntry { .example }
    func snapshot(for configuration: SingleHabitConfiguration, in context: Context) async -> HabitEntry {
        context.isPreview ? .example : entry(configuration)
    }
    func timeline(for configuration: SingleHabitConfiguration, in context: Context) async -> Timeline<HabitEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(nextRefresh()))
    }
    private func entry(_ configuration: SingleHabitConfiguration) -> HabitEntry {
        HabitEntry(date: Date(), data: (try? sharedStore().read().dataset) ?? Dataset(), ids: [configuration.habit?.id])
    }
}
struct ThreeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitEntry { .example }
    func snapshot(for configuration: ThreeHabitConfiguration, in context: Context) async -> HabitEntry {
        context.isPreview ? .example : entry(configuration)
    }
    func timeline(for configuration: ThreeHabitConfiguration, in context: Context) async -> Timeline<HabitEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(nextRefresh()))
    }
    private func entry(_ configuration: ThreeHabitConfiguration) -> HabitEntry {
        HabitEntry(date: Date(), data: (try? sharedStore().read().dataset) ?? Dataset(), ids: [configuration.first?.id, configuration.second?.id, configuration.third?.id])
    }
}
struct SixProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitEntry { .example }
    func snapshot(for configuration: SixHabitConfiguration, in context: Context) async -> HabitEntry {
        context.isPreview ? .example : entry(configuration)
    }
    func timeline(for configuration: SixHabitConfiguration, in context: Context) async -> Timeline<HabitEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(nextRefresh()))
    }
    private func entry(_ configuration: SixHabitConfiguration) -> HabitEntry {
        HabitEntry(date: Date(), data: (try? sharedStore().read().dataset) ?? Dataset(),
                   ids: [configuration.first?.id, configuration.second?.id, configuration.third?.id,
                         configuration.fourth?.id, configuration.fifth?.id, configuration.sixth?.id])
    }
}
private func nextRefresh() -> Date {
    let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 3600)
    let actualNextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? midnight
    return min(Date().addingTimeInterval(15 * 60), actualNextDay)
}
struct SingleHabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OpenHabitSingle", intent: SingleHabitConfiguration.self, provider: SingleProvider()) { HabitWidgetContent(entry: $0, compactRows: nil) }
            .configurationDisplayName("One Habit").description("One small step, right on your Home Screen.").supportedFamilies([.systemSmall]).contentMarginsDisabled()
    }
}
struct ThreeHabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OpenHabitThree", intent: ThreeHabitConfiguration.self, provider: ThreeProvider()) { HabitWidgetContent(entry: $0, compactRows: 3) }
            .configurationDisplayName("Three Habits").description("Track three Habits across the last ten days.").supportedFamilies([.systemMedium]).contentMarginsDisabled()
    }
}
struct SixHabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OpenHabitSix", intent: SixHabitConfiguration.self, provider: SixProvider()) { HabitWidgetContent(entry: $0, compactRows: 6) }
            .configurationDisplayName("Six Habits").description("Track six Habits across the last ten days.").supportedFamilies([.systemLarge]).contentMarginsDisabled()
    }
}
@main struct OpenHabitWidgets: WidgetBundle {
    var body: some Widget { SingleHabitWidget(); ThreeHabitWidget(); SixHabitWidget() }
}
#Preview(as: .systemSmall) { SingleHabitWidget() } timeline: { HabitEntry.example }
#Preview(as: .systemMedium) { ThreeHabitWidget() } timeline: { HabitEntry.example }
#Preview(as: .systemLarge) { SixHabitWidget() } timeline: { HabitEntry.example }
