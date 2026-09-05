# Plan: Convert Dientempo to Free + 1-run/day + IAP unlock ($4.99)

> **Revision note (implementation pass):** this plan was reviewed before coding and split
> into smaller, independently buildable steps. A few bugs in the original draft were fixed
> along the way -- see "Corrections made vs. the original draft" below. Track live progress
> in `STATUS.md`, not here -- this file describes the *design*, `STATUS.md` describes *state*.

## Goal

1. Make the app **free** on the App Store (currently paid \$4.99).
2. Free users can run the app **once per calendar day**.
3. If they run more than once in a day, show a lock screen with a **countdown** (HH:MM:SS) to
   midnight and a **\$4.99 "Unlimited Access"** button.
4. The \$4.99 **Non-Consumable In-App Purchase** permanently lifts the daily limit.
5. After purchase, `canRun` is always true (unlimited).

## Quick summary of the state machine

- `canRun` = `isPremiumUnlocked || lastRunDate is not today` (calendar day, `Calendar.current`).
- On the FIRST run of the day: `recordRun()` is called, counter starts normally.
- On any subsequent run that day: show lock screen.
- Lock screen content: countdown to **midnight** (not "24h from last run" -- see corrections
  below) + "Unlimited Access -- \$4.99" button + "Restore Purchase" link.
- `recordRun()` fires from a single choke point -- a callback the view model invokes whenever
  a *new* session actually begins -- so it can't be bypassed by starting a session via tap or
  swipe instead of the "Vamos" button.

---

## Corrections made vs. the original draft

These were caught during implementation review, before writing code. Documenting them here
so the reasoning isn't lost:

1. **`[weak self]` in a `Timer` closure inside `ContentView`.** `ContentView` is a `struct`,
   and Swift does not allow `weak` capture of non-class types -- this would not compile.
   Fixed by dropping the capture list entirely (no reference cycle risk in a struct).
2. **`.onChange(of:) { _, phase in }` two-parameter closure.** This form needs iOS 17+, but
   `IPHONEOS_DEPLOYMENT_TARGET` is 16.0. Fixed by keeping the original single-parameter
   `.onChange(of: scenePhase) { phase in }` form already used in the file.
3. **Dropped `.onChange(of: counter.state)` hook.** The original `ContentView` re-applies the
   screen-idle-timer policy whenever `counter.state` changes (e.g. when a session finishes on
   its own at number 200, with no button tap). The draft's replacement `ContentView` silently
   removed this. Restored it.
4. **Daily-limit bypass via tap/swipe.** `recordRun()` was only wired into the "Vamos" button
   handler, but the digit/words area can also start a fresh session (tap-to-resume-from-ready,
   or swipe-to-start), which never calls it -- so a user could dodge the daily limit completely.
   Fixed by moving `recordRun()` into a single choke point: `ToothCountingViewModel` calls an
   `onSessionWillStart` closure whenever a session transitions from `.ready`/`.finished` into
   `.running` (a genuinely new run), regardless of which gesture triggered it. Resuming after
   backgrounding, or nudging the number mid-session, do not count as new runs.
5. **Countdown/lock inconsistency.** `canRun` resets at **calendar midnight**
   (`Calendar.isDate(_:inSameDayAs:)`), but the draft's `timeRemaining()` counted a rolling
   **24 hours from `lastRunDate`**. These disagree whenever the last run wasn't near midnight
   (e.g. run at 11pm -> unlocked again ~1h later by the `canRun` check, but the countdown would
   still show ~23h remaining). Fixed `timeRemaining()` to count down to the next midnight,
   matching `canRun`'s semantics exactly.
6. **Stale lock screen at day rollover.** Nothing `@Published` changes when the calendar day
   turns over, so even with the countdown fixed, the view would not automatically flip from
   the lock screen back to the main UI. Fixed by having the countdown timer call
   `premiumManager.objectWillChange.send()` on every tick while locked, forcing `body` to
   re-evaluate `canRun` each second.

---

## Phase 0 -- App Store Connect setup (manual, do this FIRST, outside the code)

Unchanged from the original draft -- these steps are in the App Store Connect web UI, not in
code, and must be done before submission. Not scriptable from this environment.

### Step 0.1 -- Make the app free
1. Go to https://appstoreconnect.apple.com -> Apps -> Dientempo.
2. **Pricing and Availability** -> change `Paid` -> `Free`. Save.

### Step 0.2 -- Create the In-App Purchase
1. Dientempo app -> **In-App Purchases** -> **+** -> **Non-Consumable**.
2. Reference name: `Unlimited Access` * Product ID: **`com.bystruev.dientempo.premium`**
   (must match `PurchaseManager.productID` exactly) * Price: **\$4.99** * Title:
   `Unlimited Access` * Description: `Buy once, use Dientempo without limits. No
   subscriptions, no ads.` * Upload at least one screenshot (required to submit).
3. **Prepare for Submission** -> **Submit for Review**. Apple reviews every IAP once; it
   cannot be tested live until approved.

### Step 0.3 -- Sandbox testing account
1. **Users and Access** -> **Sandbox Testers** -> **+** -> create a tester email.
2. On the test device/simulator: Settings -> App Store -> sign out of the real Apple ID, sign
   in with the sandbox tester.

### Step 0.4 -- (Optional) "What's New" note
> `Dientempo is now free with one free session per day. Unlimited access is available as a
> one-time \$4.99 in-app purchase.`

---

## Phase 1 -- `PremiumManager.swift`

**Step 1.1.** Create `Dientempo/PremiumManager.swift`: an `@MainActor` `ObservableObject`
singleton tracking `isPremiumUnlocked` (persisted in `UserDefaults`) and `lastRunDate`
(persisted in `UserDefaults`). Exposes:
- `canRun: Bool` -- `isPremiumUnlocked || !ranToday()`.
- `timeRemaining() -> TimeInterval` -- seconds until the next midnight, `0` if `canRun`.
- `countdownString() -> String` -- `"HH:MM:SS"`.
- `recordRun()` -- stamps `lastRunDate = Date()`.
- `unlockPremium()` -- sets `isPremiumUnlocked = true` and persists it.
- `resetForTesting()` -- clears both, for debugger/test use.

**Step 1.2.** Add `DientempoTests/PremiumManagerTests.swift` covering: default `canRun` is
true; `recordRun()` makes `canRun` false the same day; `resetForTesting()` restores `canRun`
to true; `unlockPremium()` makes `canRun` true regardless of `lastRunDate`; `timeRemaining()`
is `0` when unlocked and within `(0, 86400]` when locked.

**Step 1.3.** Build (`xcodebuild build`) and run tests (`xcodebuild test`) before moving on.

## Phase 2 -- `PurchaseManager.swift`

**Step 2.1.** Create `Dientempo/PurchaseManager.swift`: an `@MainActor` `NSObject` +
`ObservableObject` singleton wrapping StoreKit 1 (`SKPaymentQueue`/`SKProductsRequest`) since
the deployment target is iOS 16.0 and this needs no new capability beyond what every app
already has. Loads `com.bystruev.dientempo.premium`, exposes `purchase()` and `restore()`,
and calls `PremiumManager.shared.unlockPremium()` on a successful purchase or restore.

**Step 2.2.** Build (`xcodebuild build`) -- this alone doesn't need a device/sandbox account,
just needs to compile and link against StoreKit.

## Phase 3 -- Wire it into the counting flow

**Step 3.1 -- `ToothCountingViewModel.swift`.** Add `var onSessionWillStart: (() -> Void)?`.
In `startCounting(from:)`, capture `state == .ready || state == .finished` *before* setting
`state = .running`, and invoke the closure only when that was true. This is the single choke
point for "a brand-new run started" regardless of entry gesture (button, tap, or swipe); see
correction #4 above.

**Step 3.2 -- `ContentView.swift`.** Additive changes only, original layout untouched:
- Add `@StateObject private var premiumManager = PremiumManager.shared` and
  `@StateObject private var purchaseManager = PurchaseManager.shared`.
- Add `@State private var remainingTime: TimeInterval = 0` and
  `@State private var countdownTimer: Timer? = nil`.
- Split the existing body into `mainContent(proxy:)` (unchanged original UI) and a new
  `lockScreenView(proxy:)`, switched on `premiumManager.canRun`.
- In `onAppear`, set `counter.onSessionWillStart = { PremiumManager.shared.recordRun() }` and
  start the countdown timer.
- Keep the existing single-parameter `.onChange(of: scenePhase)` and `.onChange(of:
  counter.state)` hooks; extend the scenePhase handler to also start/stop the countdown timer.
- Countdown timer ticks every second while locked, updates `remainingTime`, calls
  `premiumManager.objectWillChange.send()` (see correction #6), and self-invalidates once
  `canRun` flips true.

**Step 3.3.** Build (`xcodebuild build`).

## Phase 4 -- `Info.plist`

No changes. StoreKit 1 non-consumable purchases need no plist keys.

## Phase 5 -- Xcode project: "In-App Purchase" capability (manual)

Modern Xcode/App IDs generally have In-App Purchase available by default, and StoreKit 1
purchases will function in the simulator/sandbox without any extra entitlement. Still,
before submitting to App Review:

1. Open `Dientempo.xcodeproj` in Xcode -> **Dientempo** target -> **Signing & Capabilities**.
2. Confirm (or add via **+ Capability**) **In-App Purchase**.
3. Build (Cmd-B) -- no new warnings expected.

This step is manual -- it edits `project.pbxproj`/entitlements in ways that aren't reliable to
script by hand. Tracked as a manual checklist item in `STATUS.md`.

## Phase 6 -- Testing checklist

Automatable pieces (via `xcodebuild build` / `xcodebuild test` on the `iPhone 17e` simulator):
- Unit tests from Phase 1.2 pass.
- App builds and launches without crashing (`xcodebuild build`, then boot + install via
  `xcrun simctl` if a manual smoke check is wanted).

Needs a human + sandbox tester account (cannot be scripted from here):
- 6.1 First run of the day -> main UI, "Vamos" works, `recordRun()` fires.
- 6.2 Second run same day -> lock screen, countdown ticks, flips back at midnight.
- 6.3 Purchase flow -> sandbox payment sheet -> `isPremiumUnlocked` persists across relaunch.
- 6.4 Restore flow.
- 6.5 Edge cases: time zone travel, DST, app killed mid-run, purchase failure message.
- 6.6 TestFlight distribution.

## Phase 7 -- Files changed (summary)

| File | Action | Description |
|---|---|---|
| `Dientempo/PremiumManager.swift` | **Create** | Tracks premium state, last run, daily limit, midnight countdown. |
| `Dientempo/PurchaseManager.swift` | **Create** | Loads the IAP product, handles purchase and restore. |
| `Dientempo/ToothCountingViewModel.swift` | **Modify** | Adds `onSessionWillStart` choke point so the daily limit can't be bypassed by tap/swipe. |
| `Dientempo/ContentView.swift` | **Modify** | Wraps the main UI in a conditional, adds the lock screen, wires `recordRun()`, adds a self-correcting countdown timer. |
| `DientempoTests/PremiumManagerTests.swift` | **Create** | Unit tests for the daily-limit state machine. |
| `Dientempo.xcodeproj` | **Modify (manual)** | Confirm/enable "In-App Purchase" capability in Xcode. |
| `Dientempo/Info.plist` | **None** | No changes required. |

### Git commit message (suggested, split into logical commits)

```
Add PremiumManager: track premium state and daily run limit (resets at midnight)
Add PurchaseManager: StoreKit 1 non-consumable IAP (com.bystruev.dientempo.premium)
Add onSessionWillStart choke point to ToothCountingViewModel to close daily-limit bypass
Wire lock screen + IAP into ContentView; fix countdown/canRun consistency
```

### App Store Connect changes to remember (outside code)

- Change pricing from **Paid \$4.99** -> **Free**.
- Create IAP **Non-Consumable**, Product ID `com.bystruev.dientempo.premium`, price \$4.99.
- Submit the IAP for Apple review.
- Set up a **Sandbox Tester** account for testing.
- Update the "What's New" / release notes.
