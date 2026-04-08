//
//  MainView.swift
//  Ramble

import SwiftUI

struct MainView: View {
    @StateObject private var viewModel = RecordingViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Top bar
                    HStack(alignment: .firstTextBaseline) {
                        Text("Ramble")
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .italic()
                        Spacer()
                        SettingsButtonView {
                            HapticService.buttonTap()
                            showSettings = true
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Recording list — full height, scrolls under the controls
                    RecordingListView(
                        recordingsByDay: viewModel.recordingsByDay,
                        onDelete: viewModel.deleteRecording
                    )
                    .contentMargins(.top, 8, for: .scrollContent)
                    .contentMargins(.bottom, 120, for: .scrollContent)
                }

                // Floating bottom controls
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
                    onCancel: {
                        viewModel.cancelRecording()
                    }
                )
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .colorScheme(.dark)
                .background {
                    Rectangle()
                        .fill(Color.black)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .navigationDestination(for: Recording.self) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    MainView()
}
