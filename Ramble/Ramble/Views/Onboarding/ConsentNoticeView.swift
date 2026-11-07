//
//  ConsentNoticeView.swift
//  Ramble
//
//  Shown once to people who finished onboarding in an earlier build, which
//  transcribed on the device and so never showed the consent line. Tapping
//  "Continue" is the consent, like "Get started" (specs/phone.md). Until
//  then nothing uploads and the watch isn't connected.
//

import SwiftUI

struct ConsentNoticeView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                OnboardingWordmark(size: 20)
                    .padding(.horizontal, 24)
                    .padding(.top, 30)

                Spacer(minLength: 24)

                OnboardingHeadline(size: 34, alignment: .leading) {
                    Text("Transcripts now come ") + Text("from the cloud.").italic().foregroundColor(Color.obInkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Spacer(minLength: 24)

                OnboardingPrimaryButton(title: "Continue") {
                    Consent.give()
                }
                .padding(.horizontal, 16)

                // Same words as under "Get started" (specs/phone.md).
                (Text("Ramble sends your recordings to a cloud service to turn them into text, then sends the text to your agent. ")
                    + Text("[Privacy](https://ramble.watch/privacy)").foregroundColor(Color.brandAmber))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.obInkFaint)
                    .tint(Color.brandAmber)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
            }
        }
    }
}

#Preview {
    ConsentNoticeView()
}
