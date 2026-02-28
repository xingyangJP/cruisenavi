import SwiftUI

struct OnboardingWalkthroughStep: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let description: String
    let primaryActionTitle: String
    let secondaryActionTitle: String?
    let highlights: [String]
}

struct OnboardingWalkthroughView: View {
    let steps: [OnboardingWalkthroughStep]
    let index: Int
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?
    let onSkip: () -> Void

    private var step: OnboardingWalkthroughStep { steps[index] }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Text("はじめてガイド")
                        .font(.headline)
                        .foregroundStyle(Color.citrusPrimaryText)
                    Spacer()
                    Text("\(index + 1)/\(steps.count)")
                        .font(.caption.bold())
                        .foregroundStyle(Color.citrusSecondaryText)
                }

                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { dot in
                        Capsule()
                            .fill(dot <= index ? Color.citrusAmber : Color.citrusBorder)
                            .frame(width: dot == index ? 24 : 10, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: step.icon)
                            .font(.title3.bold())
                            .foregroundStyle(Color.citrusPrimaryText)
                            .frame(width: 36, height: 36)
                            .background(Color.citrusAmber.opacity(0.35), in: Circle())
                        Text(step.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.citrusPrimaryText)
                    }
                    Text(step.description)
                        .font(.subheadline)
                        .foregroundStyle(Color.citrusSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(step.highlights, id: \.self) { highlight in
                            Label(highlight, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.citrusPrimaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    if let secondary = step.secondaryActionTitle {
                        Button(secondary) {
                            onSecondaryAction?()
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.citrusSecondaryText)
                    }

                    Button(step.primaryActionTitle) {
                        onPrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.citrusAmber)
                    .foregroundStyle(Color(red: 0.36, green: 0.26, blue: 0))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                Button("スキップ") {
                    onSkip()
                }
                .font(.caption)
                .foregroundStyle(Color.citrusSecondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.citrusBorder)
            )
            .padding(.horizontal, 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
