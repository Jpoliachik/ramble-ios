//
//  MainView.swift
//  Ramble

import SwiftUI

struct MainView: View {
    @StateObject private var viewModel = RecordingViewModel()
    @State private var showSettings = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showOnboardingToast = false

    @AppStorage("shouldShowOnboardingToast") private var shouldShowOnboardingToast: Bool = false

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
                    isRecording: viewModel.isRecording,
                    scrollOffset: $scrollOffset
                )
                .contentMargins(.top, 48, for: .scrollContent)
                .contentMargins(.bottom, 120, for: .scrollContent)

                // Top bar — floats over list, slides apart and fades on scroll
                VStack {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.brandRed)
                                .frame(width: 12, height: 12)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            Text("Ramble")
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .italic()
                        }
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

                // Transient post-onboarding toast — fades after 2.4s, taps fall through
                if showOnboardingToast {
                    OnboardingCompletionToast()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -16)),
                            removal: .opacity.combined(with: .offset(y: -16))
                        ))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 64)
                        .allowsHitTesting(false)
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
        .onAppear {
            triggerOnboardingToastIfNeeded()
        }
        .onChange(of: shouldShowOnboardingToast) { _, newValue in
            // Catches the in-session case: MainView is already mounted when the
            // onboarding sheet dismisses, so .onAppear doesn't fire again. The
            // flag flipping to true triggers the toast here instead.
            if newValue {
                triggerOnboardingToastIfNeeded()
            }
        }
    }

    private func triggerOnboardingToastIfNeeded() {
        guard shouldShowOnboardingToast else { return }
        shouldShowOnboardingToast = false
        withAnimation(.easeOut(duration: 0.38)) {
            showOnboardingToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeIn(duration: 0.38)) {
                showOnboardingToast = false
            }
        }
    }
}

private struct OnboardingCompletionToast: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.brandRed)
                    .frame(width: 22, height: 22)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 0) {
                Text("You're ")
                Text("all set")
                    .font(.system(size: 14, design: .serif).italic().weight(.semibold))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(red: 0.078, green: 0.071, blue: 0.063).opacity(0.95))
        )
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 2)
    }
}

#Preview {
    MainView()
}
