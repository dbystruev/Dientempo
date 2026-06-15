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
        "\(voice.language) - \(qualityName(for: voice.quality))"
    }

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

        let lhsLocale = localeRank(for: lhs.language)
        let rhsLocale = localeRank(for: rhs.language)
        if lhsLocale != rhsLocale {
            return lhsLocale > rhsLocale
        }

        return lhs.name < rhs.name
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

    private var voices: [AVSpeechSynthesisVoice] {
        SpanishVoicePreference.sortedInstalledVoices
    }

    var body: some View {
        NavigationStack {
            List {
                voiceRow(title: "Automatic", subtitle: automaticSubtitle, identifier: SpanishVoicePreference.automaticIdentifier)

                ForEach(voices, id: \.identifier) { voice in
                    voiceRow(
                        title: voice.name,
                        subtitle: SpanishVoicePreference.description(for: voice),
                        identifier: voice.identifier
                    )
                }
            }
            .navigationTitle("Voice")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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
