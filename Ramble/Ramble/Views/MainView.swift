//
//  MainView.swift
//  Ramble
//

import SwiftUI

struct MainView: View {
    @StateObject private var viewModel = RecordingViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("Ramble")
                        .font(.largeTitle.bold())
                    Spacer()
                    SettingsButtonView {
                        HapticService.buttonTap()
                        showSettings = true
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Recording list
                RecordingListView(
                    recordingsByDay: viewModel.recordingsByDay,
                    onDelete: viewModel.deleteRecording
                )

                Divider()

                // Bottom controls
                RecordingControlsView(
                    isRecording: viewModel.isRecording,
                    duration: viewModel.currentDuration,
                    inputSourceName: viewModel.inputSourceName,
                    audioLevel: viewModel.audioLevel,
                    onToggleRecording: {
                        Task {
                            await viewModel.toggleRecording()
                        }
                    },
                    onSelectInput: { input in
                        viewModel.selectAudioInput(input)
                    }
                )
                .background(Color(uiColor: .systemBackground))
            }
            .navigationDestination(for: Recording.self) { recording in
                RecordingDetailView(recording: recording)
            }
            .overlay(alignment: .top) {
                if viewModel.showSavedConfirmation {
                    savedConfirmationView
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.showSavedConfirmation)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var savedConfirmationView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Saved")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(radius: 4)
        )
        .padding(.top, 60)
    }
}

#Preview {
    MainView()
}
