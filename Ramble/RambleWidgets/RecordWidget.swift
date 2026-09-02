//
//  RecordWidget.swift
//  RambleWidgets
//

import SwiftUI
import WidgetKit

struct RecordWidgetEntry: TimelineEntry {
    let date: Date
}

struct RecordWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordWidgetEntry {
        RecordWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordWidgetEntry) -> Void) {
        completion(RecordWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordWidgetEntry>) -> Void) {
        completion(Timeline(entries: [RecordWidgetEntry(date: .now)], policy: .never))
    }
}

/// Home screen and lock screen. There is no state to show, so this is a tap
/// target: it opens the app on `ramble://record`, which toggles recording.
struct RecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.goodloop.Ramble.recordWidget", provider: RecordWidgetProvider()) { _ in
            RecordWidgetView()
                .widgetURL(URL(string: "ramble://record"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ramble")
        .description("Start a Ramble from your home screen.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct RecordWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        // Just the word, for the same reason the watch complication is text only:
        // a glyph over AccessoryWidgetBackground renders badly in the round and
        // corner slots. systemSmall gets the same treatment, one size up.
        Text("Ramble")
            .font(family == .systemSmall ? .system(size: 20, weight: .semibold) : .body)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .widgetAccentable()
    }
}
