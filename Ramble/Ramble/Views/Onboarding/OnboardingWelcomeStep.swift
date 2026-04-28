//
//  OnboardingWelcomeStep.swift
//  Ramble
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 0) {
                RambleBarsMark(size: 96, tint: Color.obHair)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onboardingAppear(delay: 0)

                Spacer()

                OnboardingWordmark(size: 32)
                    .padding(.bottom, 18)
                    .onboardingAppear(delay: 0.05)

                OnboardingHeadline(size: 40, alignment: .leading) {
                    Text("Voice notes ")
                    + Text("that").italic().foregroundColor(Color.obInkSoft)
                    + Text(" go somewhere.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onboardingAppear(delay: 0.2)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        } bottomBar: {
            OnboardingPrimaryButton(title: "Get started", action: onContinue)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .onboardingAppear(delay: 0.5)
        }
    }
}

#Preview {
    OnboardingView()
}
