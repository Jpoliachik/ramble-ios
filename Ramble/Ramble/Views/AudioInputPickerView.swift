//
//  AudioInputPickerView.swift
//  Ramble
//
//  A compact picker for selecting audio input device
//

import AVFoundation
import SwiftUI

struct AudioInputPickerView: View {
    @ObservedObject var inputService: AudioInputService
    let isRecording: Bool
    let onSelect: (AudioInput) -> Void

    @State private var showPicker = false

    var body: some View {
        Button {
            inputService.refreshAvailableInputs()
            showPicker = true
        } label: {
            HStack(spacing: 4) {
                if let current = inputService.currentInput {
                    Image(systemName: current.iconName)
                        .font(.caption)
                    Text(current.displayName)
                        .font(.caption)
                } else {
                    Image(systemName: "mic")
                        .font(.caption)
                    Text("Select Input")
                        .font(.caption)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .sheet(isPresented: $showPicker) {
            AudioInputListView(
                inputService: inputService,
                isRecording: isRecording,
                onSelect: { input in
                    onSelect(input)
                    showPicker = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

struct AudioInputListView: View {
    @ObservedObject var inputService: AudioInputService
    let isRecording: Bool
    let onSelect: (AudioInput) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if inputService.availableInputs.isEmpty {
                    Text("No audio inputs available")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(inputService.availableInputs) { input in
                        Button {
                            onSelect(input)
                        } label: {
                            HStack {
                                Image(systemName: input.iconName)
                                    .frame(width: 24)
                                    .foregroundColor(.primary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(input.displayName)
                                        .foregroundColor(.primary)
                                    Text(portTypeDescription(input.portType))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if inputService.currentInput?.id == input.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                if isRecording {
                    Section {
                        Label {
                            Text("Switching input while recording may cause a brief audio glitch")
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Audio Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            inputService.refreshAvailableInputs()
        }
    }

    private func portTypeDescription(_ portType: AVAudioSession.Port) -> String {
        switch portType {
        case .bluetoothHFP:
            return "Bluetooth Hands-Free"
        case .bluetoothA2DP:
            return "Bluetooth Audio"
        case .builtInMic:
            return "Built-in"
        case .headsetMic:
            return "Wired"
        case .usbAudio:
            return "USB"
        default:
            return "External"
        }
    }
}

#Preview {
    VStack {
        AudioInputPickerView(
            inputService: AudioInputService.shared,
            isRecording: false,
            onSelect: { _ in }
        )
    }
    .padding()
}
