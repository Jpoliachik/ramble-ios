//
//  widgetsLiveActivity.swift
//  widgets
//
//  Created by Justin Poliachik on 1/21/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct widgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct widgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: widgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension widgetsAttributes {
    fileprivate static var preview: widgetsAttributes {
        widgetsAttributes(name: "World")
    }
}

extension widgetsAttributes.ContentState {
    fileprivate static var smiley: widgetsAttributes.ContentState {
        widgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: widgetsAttributes.ContentState {
         widgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: widgetsAttributes.preview) {
   widgetsLiveActivity()
} contentStates: {
    widgetsAttributes.ContentState.smiley
    widgetsAttributes.ContentState.starEyes
}
