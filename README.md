# Dientempo

Dientempo is a small native iOS app for brushing teeth while learning Spanish number pronunciation.

The name is a coined word from Spanish **diente** (tooth) and **tiempo** (time): roughly "tooth time."

## Links

- **TestFlight**: https://testflight.apple.com/join/jtC3rKeZ
- **Website**: https://dientempo.bystruev.com
- **Support**: dientempo@bystruev.com

## How It Works

The default session counts from 0 through 200, inclusive, so the full run lasts about 201 seconds. Each second shows the digit, shows the Spanish words, and speaks the number in Spanish. The app is meant for English speakers who want to practice Spanish numbers during an existing daily habit.

The start button says **Vamos**, which is a natural Spanish equivalent of "let's go" for this use. During a run, the button changes to **Alto**.

## Features

- Clear Spanish pronunciation using high-quality system voices
- Large, easy-to-read display with digits and Spanish words
- Tap to pause/resume, swipe to skip forward or backward
- Accelerating swipe for quick navigation (1 → 2 → 3 → 5 → 8 → 12 → 16)
- Automatic dark and light mode support
- Voice selection for installed Spanish voices
- Works completely offline — no internet required
- Precise timing: each word finishes before the next begins

## Voice Selection

The **Voz** link appears only before and after counting. It opens an in-app voice picker for installed Spanish system voices. To add higher-quality voices, use iOS Settings > Accessibility > Spoken Content > Voices > Spanish, then relaunch or reopen Voz.

## Timing

- Each number finishes speaking before the next starts (no cutting words)
- Speech rate adjusts based on word length (long words start faster)
- Pause duration is excluded from session timing
- Timer resets completely after pause or swipe

## Offline Support

- Spanish number words are generated locally
- Speech uses `AVSpeechSynthesizer` with offline voice processing
- No API or internet usage during counting

## Requirements

- iOS 16.0+
- Xcode 26.5+ (for building from source)

## Building

Open `Dientempo.xcodeproj` in Xcode and run the `Dientempo` scheme on an iPhone simulator or device.

## App Store Submission

App Store materials are in `app-store/1.0/`, including promotional text, description, and keywords.

## Taking Screenshots

Screenshots are taken using `scripts/take-screenshots.sh`. They are saved to `screenshots/` (gitignored).

The script automatically finds available iPhone and iPad simulators (iPhone 17 Pro Max and iPad Pro 13-inch M5). Different machines may have different simulators available.

```
./scripts/take-screenshots.sh           # Take all screenshots
./scripts/take-screenshots.sh 1 2       # Take specific screenshots
./scripts/take-screenshots.sh --help    # Show all options
./scripts/take-screenshots.sh --list    # List available screenshots
```

Available screenshots:
1. Warm-up screen (Calentando... button)
2. Ready to count (0 / cero, Vamos button)
3. Counting: number 42 / cuarenta y dos (Alto button)
4. Voice settings (Voz picker)
