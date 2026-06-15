import SwiftUI

struct ContentView: View {
    @StateObject private var counter = ToothCountingViewModel()
    @StateObject private var commands = SpeechCommandCenter()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: verticalGap(in: proxy.size, ratio: 0.06))

                    Text("\(counter.currentNumber)")
                        .font(.system(size: digitFontSize(in: proxy.size), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(.label))
                        .minimumScaleFactor(0.15)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(counter.currentWords)

                    Spacer()
                        .frame(height: verticalGap(in: proxy.size, ratio: 0.08))

                    Text(counter.currentWords)
                        .font(.system(size: wordsFontSize(in: proxy.size), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(.label))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.5)
                        .allowsTightening(false)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    Spacer(minLength: verticalGap(in: proxy.size, ratio: 0.08))

                    Button {
                        counter.isRunning ? counter.stop() : counter.start()
                    } label: {
                        Text(counter.isRunning ? "Alto" : "Vamos")
                            .font(.system(size: buttonFontSize(in: proxy.size), weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: buttonHeight(in: proxy.size))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .tint(counter.isRunning ? .red : .teal)
                    .accessibilityLabel(counter.isRunning ? "Alto" : "Vamos")
                }
                .padding(.horizontal, horizontalPadding(in: proxy.size))
                .padding(.bottom, max(24, proxy.safeAreaInsets.bottom + 16))
                .padding(.top, max(16, proxy.safeAreaInsets.top))
            }
        }
        .onAppear {
            counter.prepareSpeech()
            commands.start { command in
                switch command {
                case .start:
                    counter.start()
                case .stop:
                    counter.stop()
                }
            }
        }
        .onDisappear {
            commands.stop()
            counter.stop()
        }
    }

    private func digitFontSize(in size: CGSize) -> CGFloat {
        min(size.width * 0.5, size.height * 0.28)
    }

    private func wordsFontSize(in size: CGSize) -> CGFloat {
        min(size.width * 0.13, size.height * 0.085)
    }

    private func buttonFontSize(in size: CGSize) -> CGFloat {
        min(max(size.width * 0.08, 26), 42)
    }

    private func buttonHeight(in size: CGSize) -> CGFloat {
        min(max(size.height * 0.09, 64), 92)
    }

    private func horizontalPadding(in size: CGSize) -> CGFloat {
        min(max(size.width * 0.08, 24), 64)
    }

    private func verticalGap(in size: CGSize, ratio: CGFloat) -> CGFloat {
        max(24, size.height * ratio)
    }
}

#Preview {
    ContentView()
}
