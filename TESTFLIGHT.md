# TestFlight Notes

Test Dientempo as a simple brushing timer for learning Spanish numbers.

What to test in this build:

- Start with **Vamos** or by tapping the number area. Confirm it counts 0 through 200, showing digits, Spanish words, and spoken Spanish.
- Listen especially to the first few numbers and report any clipping, silence, or unnatural pronunciation.
- While counting, tap the digit or words to pause; tap again to resume from the same number.
- Swipe left/right on the digit or words to move one number higher/lower. It should stay within 0...200 and continue counting.
- Stop with **Alto** before the end, then start again and confirm it restarts from 0.
- Open **Voz** before or after counting, select another installed Spanish voice, and confirm the next run uses it.
- Send the app to the background while counting, then return. It should resume from the interrupted number.
- Pause first, then background and return. It should stay paused.
- Confirm auto-lock works while stopped or paused, and the screen stays awake only while actively counting. Test this without Xcode attached.
- Try light and dark mode.
- If comfortable, try stop voice commands while counting, such as "stop", "alto", "para", or "detente".

Please report any mismatch between digit, Spanish text, and speech; timing that feels wrong; voice or permission issues; auto-lock problems; background resume issues; or layout problems.
