import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var counter = ToothCountingViewModel()
    @State private var isShowingVoiceSettings = false
    @State private var shouldResumeAfterSceneInterruption = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                let gesturesEnabled = !counter.isWarmingUp

                VStack(spacing: 0) {
                    Spacer(minLength: verticalGap(in: proxy.size, ratio: 0.06))

                    Text("\(counter.currentNumber)")
                        .font(.system(size: digitFontSize(in: proxy.size), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(.label))
                        .minimumScaleFactor(0.15)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: digitAreaHeight(in: proxy.size))
                        .contentShape(Rectangle())
                        .accessibilityLabel(counter.currentWords)
                        .onTapGesture {
                            togglePause()
                        }
                        .gesture(swipeGesture)
                        .disabled(!gesturesEnabled)

                    Text(counter.currentWords)
                        .font(.system(size: wordsFontSize(in: proxy.size), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(.label))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.5)
                        .allowsTightening(false)
                        .frame(maxWidth: .infinity)
                        .frame(height: wordsAreaHeight(in: proxy.size))
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                        .onTapGesture {
                            togglePause()
                        }
                        .gesture(swipeGesture)
                        .disabled(!gesturesEnabled)

                    Spacer(minLength: verticalGap(in: proxy.size, ratio: 0.04))

                    Button {
                        startOrStopCounting()
                    } label: {
                        if counter.isWarmingUp {
                            Text("Calentando...")
                                .font(.system(size: buttonFontSize(in: proxy.size), weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: buttonHeight(in: proxy.size))
                        } else {
                            Text(counter.isCounting ? "Alto" : "Vamos")
                                .font(.system(size: buttonFontSize(in: proxy.size), weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: buttonHeight(in: proxy.size))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .tint(counter.isWarmingUp ? .gray : (counter.isCounting ? .red : .teal))
                    .disabled(counter.isWarmingUp)
                    .accessibilityLabel(counter.isWarmingUp ? "Calentando" : (counter.isCounting ? "Alto" : "Vamos"))

                    ZStack(alignment: .top) {
                        if !counter.isCounting && !counter.isWarmingUp {
                            Button("Voz") {
                                isShowingVoiceSettings = true
                            }
                            .font(.system(size: voiceLinkFontSize(in: proxy.size), weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(.secondaryLabel))
                            .padding(.top, 16)
                        }
                    }
                    .frame(height: voiceAreaHeight(in: proxy.size), alignment: .top)
                }
                .padding(.horizontal, horizontalPadding(in: proxy.size))
                .padding(.bottom, max(24, proxy.safeAreaInsets.bottom + 16))
                .padding(.top, max(16, proxy.safeAreaInsets.top))
            }
        }
        .onAppear {
            applyPowerPolicy()
            counter.prepareSpeech()
        }
        .onDisappear {
            shouldResumeAfterSceneInterruption = false
            allowIdleTimer()
            counter.stop()
        }
        .onChange(of: counter.state) { _ in
            applyPowerPolicy()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                if shouldResumeAfterSceneInterruption {
                    counter.resumeAfterInterruption()
                }

                shouldResumeAfterSceneInterruption = false
                applyPowerPolicy()
            case .inactive, .background:
                if counter.isRunning {
                    shouldResumeAfterSceneInterruption = true
                    counter.pauseForInterruption()
                }
                allowIdleTimer()
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $isShowingVoiceSettings) {
            VoiceSettingsView()
        }
    }

    private func startOrStopCounting() {
        shouldResumeAfterSceneInterruption = false
        counter.isCounting ? counter.stop() : counter.start()
        applyPowerPolicy()
    }

    private func togglePause() {
        shouldResumeAfterSceneInterruption = false
        counter.togglePause()
        applyPowerPolicy()
    }

    private func moveCounter(by offset: Int) {
        shouldResumeAfterSceneInterruption = false
        counter.move(by: offset)
        applyPowerPolicy()
    }

    private func applyPowerPolicy() {
        let shouldStayAwake = scenePhase == .active && counter.isRunning
        UIApplication.shared.isIdleTimerDisabled = shouldStayAwake

        debugPower("idleTimerDisabled=\(UIApplication.shared.isIdleTimerDisabled) state=\(counter.state)")
    }

    private func allowIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = false
        debugPower("idleTimerDisabled=false")
    }

    private func debugPower(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("[DientempoPower] %@", message())
        #endif
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                moveCounter(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    private func digitFontSize(in size: CGSize) -> CGFloat {
        min(size.width * 0.5, size.height * 0.28)
    }

    private func wordsFontSize(in size: CGSize) -> CGFloat {
        min(size.width * 0.13, size.height * 0.085)
    }

    private func digitAreaHeight(in size: CGSize) -> CGFloat {
        min(max(digitFontSize(in: size) * 1.08, 132), size.height * 0.28)
    }

    private func wordsAreaHeight(in size: CGSize) -> CGFloat {
        min(max(wordsFontSize(in: size) * 4.6, 168), size.height * 0.34)
    }

    private func buttonFontSize(in size: CGSize) -> CGFloat {
        min(max(size.width * 0.08, 26), 42)
    }

    private func buttonHeight(in size: CGSize) -> CGFloat {
        min(max(size.height * 0.09, 64), 92)
    }

    private func voiceLinkFontSize(in size: CGSize) -> CGFloat {
        min(max(size.width * 0.045, 18), 24)
    }

    private func voiceAreaHeight(in size: CGSize) -> CGFloat {
        min(max(size.height * 0.07, 52), 72)
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
