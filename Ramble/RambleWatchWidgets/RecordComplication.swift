//
//  RecordComplication.swift
//  RambleWatchWidgets
//

import SwiftUI
import WidgetKit

/// A complication that jumps straight into recording. There is nothing to show
/// over time, so the timeline is a single entry with `.never` — the point is the
/// tap target on the watch face, not the content.
struct RecordEntry: TimelineEntry {
    let date: Date
}

struct RecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry {
        RecordEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(RecordEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        completion(Timeline(entries: [RecordEntry(date: .now)], policy: .never))
    }
}

struct RecordComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.goodloop.Ramble.record", provider: RecordProvider()) { _ in
            RecordComplicationView()
                // Fill the slot before attaching the URL: widgetURL only covers the
                // view it's applied to, and the glyph on its own leaves dead space
                // around it where taps did nothing.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // A widgetURL makes the whole complication one launch target, which
                // the system handles on the first tap. Wrapping the content in a
                // Button(intent:) instead meant the first tap went to the face to
                // focus the complication and only a later one reached the button.
                //
                // The app opens and stops there: `ramble://open` carries no record
                // request, unlike `ramble://record`.
                .widgetURL(URL(string: "ramble://open"))
                // Required since watchOS 10: without it the face shows
                // "Please adopt containerBackground API" instead of the complication.
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Ramble")
        .description("Start a Ramble from your watch face.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

struct RecordComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            // A single line of text on the face; no room for artwork.
            Label("Ramble", systemImage: "waveform")

        case .accessoryRectangular:
            // The only family with room for more than a glyph.
            HStack(spacing: 8) {
                glyph
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ramble")
                        .font(.headline)
                        .widgetAccentable()
                    Text("Tap to record")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

        case .accessoryCorner:
            // One glyph, with the name on the curve. Corner scales its content into
            // a small curved area, so anything with two elements side by side (the
            // record dot next to the bars) collapses into two unreadable shapes,
            // which is what the Nike face showed.
            glyph
                .widgetLabel("Ramble")

        default:
            // Circular: the Voice Memos treatment, a glyph inside the system's
            // accessory background so it reads as a button on any face.
            ZStack {
                AccessoryWidgetBackground()
                glyph
            }
        }
    }

    /// A single symbol, deliberately, and sized by the system rather than by a
    /// point value. Faces render complications monochrome or tinted and give the
    /// same family very different amounts of room (a 40mm corner against an Ultra
    /// rectangular), so the icon has to survive on its own and scale itself.
    private var glyph: some View {
        Image(systemName: "waveform")
            .imageScale(.large)
            .widgetAccentable()
    }
}
