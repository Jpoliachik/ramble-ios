//
//  RambleWidgetBundle.swift
//  RambleWidgets
//

import SwiftUI
import WidgetKit

@main
struct RambleWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordWidget()
        RecordingLiveActivity()
        RecordControl()
    }
}
