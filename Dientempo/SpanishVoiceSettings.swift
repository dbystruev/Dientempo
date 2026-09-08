import AVFoundation
import SwiftUI

enum SpanishVoicePreference {
    static let automaticIdentifier = "automatic"
    static let selectedVoiceIdentifierKey = "selectedSpanishVoiceIdentifier"

    static var sortedInstalledVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("es") }
            .sorted { isVoice($0, higherPriorityThan: $1) }
    }

    static func selectedVoice() -> AVSpeechSynthesisVoice? {
        let selectedIdentifier = UserDefaults.standard.string(forKey: selectedVoiceIdentifierKey)

        if let selectedIdentifier,
           selectedIdentifier != automaticIdentifier,
           let selectedVoice = AVSpeechSynthesisVoice(identifier: selectedIdentifier) {
            return selectedVoice
        }

        return bestInstalledSpanishVoice()
    }

    static func bestInstalledSpanishVoice() -> AVSpeechSynthesisVoice? {
        sortedInstalledVoices.first
            ?? AVSpeechSynthesisVoice(language: "es-ES")
            ?? AVSpeechSynthesisVoice(language: "es-MX")
            ?? AVSpeechSynthesisVoice(language: "es-US")
    }

    static func description(for voice: AVSpeechSynthesisVoice) -> String {
        [
            voice.language,
            qualityName(for: voice.quality),
            compactnessName(for: voice.identifier)
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }

    #if DEBUG
    static func debugSelectionSummary() -> String {
        let selectedIdentifier = UserDefaults.standard.string(forKey: selectedVoiceIdentifierKey) ?? automaticIdentifier
        let selectedVoiceDescription = selectedVoice().map(debugDescription) ?? "none"
        let installedVoiceDescriptions = sortedInstalledVoices.map(debugDescription).joined(separator: " | ")

        return "Voice preference=\(selectedIdentifier) selected=\(selectedVoiceDescription) installedSpanishVoices=\(installedVoiceDescriptions.isEmpty ? "none" : installedVoiceDescriptions)"
    }

    private static func debugDescription(for voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) \(description(for: voice)) id=\(voice.identifier)"
    }
    #endif

    private static func qualityName(for quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium:
            return "Premium"
        case .enhanced:
            return "Enhanced"
        default:
            return "Default"
        }
    }

    private static func isVoice(_ lhs: AVSpeechSynthesisVoice, higherPriorityThan rhs: AVSpeechSynthesisVoice) -> Bool {
        let lhsQuality = lhs.quality.rawValue
        let rhsQuality = rhs.quality.rawValue
        if lhsQuality != rhsQuality {
            return lhsQuality > rhsQuality
        }

        let lhsCompactness = compactnessRank(for: lhs.identifier)
        let rhsCompactness = compactnessRank(for: rhs.identifier)
        if lhsCompactness != rhsCompactness {
            return lhsCompactness > rhsCompactness
        }

        let lhsLocale = localeRank(for: lhs.language)
        let rhsLocale = localeRank(for: rhs.language)
        if lhsLocale != rhsLocale {
            return lhsLocale > rhsLocale
        }

        return lhs.name < rhs.name
    }

    private static func compactnessRank(for identifier: String) -> Int {
        let lowercasedIdentifier = identifier.lowercased()

        if lowercasedIdentifier.contains("super-compact") {
            return 0
        }

        if lowercasedIdentifier.contains("compact") {
            return 1
        }

        return 2
    }

    private static func compactnessName(for identifier: String) -> String? {
        let lowercasedIdentifier = identifier.lowercased()

        if lowercasedIdentifier.contains("super-compact") {
            return "Super Compact"
        }

        if lowercasedIdentifier.contains("compact") {
            return "Compact"
        }

        return nil
    }

    private static func localeRank(for language: String) -> Int {
        switch language {
        case "es-ES":
            return 3
        case "es-MX":
            return 2
        case "es-US":
            return 1
        default:
            return 0
        }
    }
}

struct VoiceSettingsView: View {
    @AppStorage(SpanishVoicePreference.selectedVoiceIdentifierKey) private var selectedVoiceIdentifier = SpanishVoicePreference.automaticIdentifier
    @Environment(\.dismiss) private var dismiss
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var premiumManager = PremiumManager.shared

    private var voices: [AVSpeechSynthesisVoice] {
        SpanishVoicePreference.sortedInstalledVoices
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    voiceRow(title: "Automatic", subtitle: automaticSubtitle, identifier: SpanishVoicePreference.automaticIdentifier)

                    ForEach(voices, id: \.identifier) { voice in
                        voiceRow(
                            title: voice.name,
                            subtitle: SpanishVoicePreference.description(for: voice),
                            identifier: voice.identifier
                        )
                    }
                }

                // Version + premium status: always visible here, not
                // just inferred from behavior, so a person can actually
                // confirm a purchase or restore took effect instead of
                // guessing from whether the lock screen shows up again.
                Section {
                    LabeledContent("Version", value: appVersionString)
                    LabeledContent("Premium") {
                        if premiumManager.isPremiumUnlocked {
                            Label("Active", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.teal)
                        } else {
                            Text("Not active")
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                }

                // Always reachable here, not just on the daily-limit lock
                // screen -- someone who already bought Unlimited Access on
                // another device (or reinstalled) gets their first free run
                // of the day before ever seeing the lock screen, so this is
                // the only place they could otherwise restore right away.
                if !premiumManager.isPremiumUnlocked {
                    Section {
                        Button("Restore Purchase") {
                            purchaseManager.restore()
                        }
                        .foregroundStyle(Color(.systemBlue))

                        if let error = purchaseManager.lastError {
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(Color(.red))
                        }

                        if purchaseManager.restoreCompleted {
                            Text("Purchase restored.")
                                .font(.caption)
                                .foregroundStyle(Color(.green))
                        }
                    }
                }
            }
            .navigationTitle("Voz")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// e.g. "1.4.3 (2026.9.5)" -- CFBundleShortVersionString (MARKETING_VERSION)
    /// and CFBundleVersion (CURRENT_PROJECT_VERSION) read straight from the
    /// running app's own Info.plist, so this always matches exactly what
    /// was actually built and shipped, no matter how versioning evolves.
    private var appVersionString: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(shortVersion) (\(buildVersion))"
    }

    private var automaticSubtitle: String {
        guard let voice = SpanishVoicePreference.bestInstalledSpanishVoice() else {
            return "Best installed Spanish voice"
        }

        return "\(voice.name) - \(SpanishVoicePreference.description(for: voice))"
    }

    private func voiceRow(title: String, subtitle: String, identifier: String) -> some View {
        Button {
            selectedVoiceIdentifier = identifier
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(Color(.label))

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }

                Spacer()

                if selectedVoiceIdentifier == identifier {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
