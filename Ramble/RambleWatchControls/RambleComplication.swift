//
//  RambleComplication.swift
//  RambleWatchControls
//
//  The Ramble complication: the record button, small, on the watch face
//  and in the Smart Stack. A tap opens Ramble and starts recording.
//  It shows no state, so its timeline has one entry and never reloads.
//

import SwiftUI
import WidgetKit

/// Opens the watch app and starts a recording. The app handles it in
/// WatchMainView. Keep the scheme in step with the watch app's Info.plist.
enum RambleLink {
    static let record = URL(string: "ramble://record")!
}

struct RambleRecordComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "dev.goodloop.Ramble.watchkitapp.complication.record",
            provider: RambleComplicationProvider()
        ) { _ in
            RambleComplicationView()
        }
        .configurationDisplayName("Ramble")
        .description("Tap to start recording.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

nonisolated struct RambleComplicationEntry: TimelineEntry {
    let date: Date
}

nonisolated struct RambleComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> RambleComplicationEntry {
        RambleComplicationEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (RambleComplicationEntry) -> Void) {
        completion(RambleComplicationEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RambleComplicationEntry>) -> Void) {
        completion(Timeline(entries: [RambleComplicationEntry(date: .now)], policy: .never))
    }
}

/// The extension has no asset catalog, so the brand color lives here.
/// Values from docs/design.md (dark appearance, as on the watch).
private extension Color {
    /// brand-amber, #F59E0B
    static let rambleAmber = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
}

struct RambleComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(RambleLink.record)
            // Black, as on the watch, so amber stays the one accent in the Smart Stack
            .containerBackground(for: .widget) { Color.black }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Record with Ramble")
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            RambleRecordMark()
                .padding(5)
                .widgetLabel("Ramble")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                RambleRecordMark()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ramble")
                        .font(.system(.headline, design: .serif).weight(.bold).italic())
                        .widgetAccentable()
                    Text("Tap to record")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label("Ramble", systemImage: "waveform")
        default:
            RambleRecordMark()
                .padding(3)
        }
    }
}

/// The home screen's record button at rest: an amber ring around a filled
/// amber disc, in the button's proportions (ring 5, disc 100, of 120).
struct RambleRecordMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ring = max(1.5, size * 5 / 120)
            ZStack {
                Circle()
                    .strokeBorder(Color.rambleAmber, lineWidth: ring)
                Circle()
                    .fill(Color.rambleAmber)
                    .padding(size * 10 / 120)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .widgetAccentable()
    }
}

#Preview("Circular", as: .accessoryCircular) {
    RambleRecordComplication()
} timeline: {
    RambleComplicationEntry(date: .now)
}

#Preview("Corner", as: .accessoryCorner) {
    RambleRecordComplication()
} timeline: {
    RambleComplicationEntry(date: .now)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    RambleRecordComplication()
} timeline: {
    RambleComplicationEntry(date: .now)
}

#Preview("Inline", as: .accessoryInline) {
    RambleRecordComplication()
} timeline: {
    RambleComplicationEntry(date: .now)
}
