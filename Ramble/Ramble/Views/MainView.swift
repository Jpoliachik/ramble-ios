//
//  MainView.swift
//  Ramble

import SwiftUI

struct MainView: View {
    @StateObject private var viewModel = RecordingViewModel()
    @State private var showSettings = false
    @State private var scrollOffset: CGFloat = 0

    /// How far the user scrolls before the header is fully collapsed (in points)
    private let scrollThreshold: CGFloat = 60

    /// 0 = at top (fully expanded), 1 = scrolled past threshold (fully collapsed)
    private var scrollProgress: CGFloat {
        min(max(scrollOffset / scrollThreshold, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Recording list — full height, scrolls under header and controls
                RecordingListView(
                    recordingsByDay: viewModel.recordingsByDay,
                    onDelete: viewModel.deleteRecording,
                    scrollOffset: $scrollOffset
                )
                .contentMargins(.top, 48, for: .scrollContent)
                .contentMargins(.bottom, 120, for: .scrollContent)

                // Top bar — floats over list, slides apart and fades on scroll
                VStack {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Ramble")
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .italic()
                            .offset(x: -80 * scrollProgress)
                            .opacity(1 - scrollProgress)
                        Spacer()
                        SettingsButtonView {
                            HapticService.buttonTap()
                            showSettings = true
                        }
                        .offset(x: 80 * scrollProgress)
                        .opacity(1 - scrollProgress)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .allowsHitTesting(scrollProgress < 0.5)
                    .animation(.easeOut(duration: 0.15), value: scrollProgress)
                    Spacer()
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
                .padding(.top, 80)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                Color(.systemBackground).opacity(0),
                                Color(.systemBackground)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 56)
                        Color(.systemBackground)
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
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
