import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var counter = ToothCountingViewModel()
    @StateObject private var premiumManager = PremiumManager.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var isShowingVoiceSettings = false
    @State private var shouldResumeAfterSceneInterruption = false
    @State private var remainingTime: TimeInterval = 0
    @State private var countdownTimer: Timer? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if premiumManager.canRun {
                    mainContent(proxy: proxy)
                } else {
                    lockScreenView(proxy: proxy)
                }
            }
        }
        .onAppear {
            applyPowerPolicy()
            wireSessionStartRecording()

            // Check for screenshot mode
            if let screenshotArg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--screenshot=") }) {
                let parts = screenshotArg.components(separatedBy: "=")
                if parts.last == "warmup" {
                    // Keep warm-up state active for screenshot without starting actual warm-up
                    counter.setForScreenshotWarmup()
                } else {
                    counter.prepareSpeech()
                    if let numberStr = parts.last, let number = Int(numberStr) {
                        let running = ProcessInfo.processInfo.arguments.contains("--screenshot-running")
                        counter.setForScreenshot(number: number, running: running)
                    } else if parts.last == "voice" {
                        // Show voice settings
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isShowingVoiceSettings = true
                        }
                    }
                }
            } else {
                counter.prepareSpeech()
            }

            startCountdownTimer()
        }
        .onDisappear {
            shouldResumeAfterSceneInterruption = false
            allowIdleTimer()
            counter.stop()
            stopCountdownTimer()
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
                startCountdownTimer()
            case .inactive, .background:
                if counter.isRunning {
                    shouldResumeAfterSceneInterruption = true
                    counter.pauseForInterruption()
                }
                allowIdleTimer()
                stopCountdownTimer()
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $isShowingVoiceSettings) {
            VoiceSettingsView()
        }
    }

    // MARK: - Main content (the original UI, unchanged)

    @ViewBuilder
    private func mainContent(proxy: GeometryProxy) -> some View {
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

    // MARK: - Lock screen (shown once the free daily run is used up)

    @ViewBuilder
    private func lockScreenView(proxy: GeometryProxy) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Dientempo")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Color(.label))

            Text("Brush your teeth")
                .font(.title2)
                .foregroundStyle(Color(.secondaryLabel))

            Text("Available again in")
                .font(.headline)
                .foregroundStyle(Color(.secondaryLabel))

            Text(premiumManager.countdownString())
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(.label))
                .padding(.vertical, 8)
                .accessibilityLabel("Available again in \(premiumManager.countdownString())")

            Spacer(minLength: 24)

            Button {
                purchaseManager.purchase()
            } label: {
                HStack(spacing: 8) {
                    if purchaseManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Unlimited Access — $4.99")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight(in: proxy.size))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(.teal)
            .disabled(purchaseManager.premiumProduct == nil)

            Button("Restore Purchase") {
                purchaseManager.restore()
            }
            .font(.callout)
            .foregroundStyle(Color(.systemBlue))
            .padding(.top, 4)

            if let error = purchaseManager.lastError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(Color(.red))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if purchaseManager.restoreCompleted {
                Text("Purchase restored.")
                    .font(.caption)
                    .foregroundStyle(Color(.green))
            }

            Spacer()
        }
        .padding(.horizontal, horizontalPadding(in: proxy.size))
        .padding(.bottom, max(24, proxy.safeAreaInsets.bottom + 16))
        .padding(.top, max(16, proxy.safeAreaInsets.top))
    }

    // MARK: - Daily-limit wiring

    /// Single choke point that records a free-tier run. Wired once here rather
    /// than in `startOrStopCounting()` so that starting a session via tap or
    /// swipe (not just the "Vamos" button) still counts against the daily
    /// limit — see `ToothCountingViewModel.onSessionWillStart`.
    private func wireSessionStartRecording() {
        counter.onSessionWillStart = {
            PremiumManager.shared.recordRun()
        }
    }

    // MARK: - Countdown timer

    private func startCountdownTimer() {
        stopCountdownTimer()
        guard !premiumManager.canRun else { return }

        remainingTime = premiumManager.timeRemaining()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                // Force `body` to re-evaluate `premiumManager.canRun` every tick.
                // `canRun` depends on the wall clock, not just `@Published`
                // storage, so without this the lock screen would not flip back
                // to the main UI on its own once midnight passes.
                premiumManager.objectWillChange.send()
                remainingTime = premiumManager.timeRemaining()

                if premiumManager.canRun {
                    stopCountdownTimer()
                }
            }
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Start / stop counting

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

    private var gesturesEnabled: Bool {
        !counter.isWarmingUp
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
