# Dientempo

Dientempo is a small native iOS app for brushing teeth while learning Spanish number pronunciation.

The name is a coined word from Spanish **diente** (tooth) and **tiempo** (time): roughly "tooth time."

The default session counts from 0 through 200, inclusive, so the full run lasts 201 seconds. Each second shows the digit, shows the Spanish words, and speaks the number in Spanish. The app is meant for English speakers who want to practice Spanish numbers during an existing daily habit.

The start button says **Vamos**, which is a natural Spanish equivalent of "let's go" for this use. During a run, the button changes to **Alto**. You can also say commands such as "go", "vamos", "stop", "alto", "para", or "detente".

The **Voz** link appears only before and after counting. It opens an in-app voice picker for installed Spanish system voices. To add higher-quality voices, use iOS Settings > Accessibility > Spoken Content > Voices > Spanish, then relaunch or reopen Voz.

Counting is offline-first:

- Spanish number words are generated locally.
- Speech uses `AVSpeechSynthesizer`, warms the selected Spanish voice on launch, and picks the highest-quality installed Spanish voice.
- Voice commands request on-device speech recognition with `requiresOnDeviceRecognition`.
- Timer progression is based on elapsed monotonic time, not on speech completion, so the 0...200 session lasts exactly 201 seconds.
- If the app is interrupted or sent to the background while counting, it pauses and resumes from the same number when active again.

Minimum deployment target: iOS 16.0.

Open `Dientempo.xcodeproj` in Xcode and run the `Dientempo` scheme on an iPhone simulator or device.
