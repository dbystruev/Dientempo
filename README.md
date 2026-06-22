# Dientempo

Dientempo is a small native iOS app for brushing teeth while learning Spanish number pronunciation.

The name is a coined word from Spanish **diente** (tooth) and **tiempo** (time): roughly "tooth time."

The default session counts from 0 through 200, inclusive, so the full run lasts 201 seconds. Each second shows the digit, shows the Spanish words, and speaks the number in Spanish. The app is meant for English speakers who want to practice Spanish numbers during an existing daily habit.

The start button says **Vamos**, which is a natural Spanish equivalent of "let's go" for this use. During a run, the button changes to **Alto**.

The **Voz** link appears only before and after counting. It opens an in-app voice picker for installed Spanish system voices. To add higher-quality voices, use iOS Settings > Accessibility > Spoken Content > Voices > Spanish, then relaunch or reopen Voz.

During counting, tap the digit or Spanish words to pause or resume. Swipe left on the digit or words to move to the next number, or swipe right to move to the previous number; the count stays within 0...200. Swipe quickly multiple times to accelerate the jump (1 → 2 → 3 → 5 → 8 → 12 → 16).

Counting is offline-first:

- Spanish number words are generated locally.
- Speech uses `AVSpeechSynthesizer`, warms the selected Spanish voice before counting starts, and picks the highest-quality installed Spanish voice.
- Timer progression is based on elapsed monotonic time, not on speech completion, so the 0...200 session lasts exactly 201 seconds.
- If the app is interrupted or sent to the background while counting, it pauses and resumes from the same number when active again.

Minimum deployment target: iOS 16.0.

Open `Dientempo.xcodeproj` in Xcode and run the `Dientempo` scheme on an iPhone simulator or device.
