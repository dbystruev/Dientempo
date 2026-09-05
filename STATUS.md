# Implementation Status: Free + 1-run/day + IAP unlock

Tracks live progress against `PLAN.md`. Update this file as steps complete -- `PLAN.md`
describes the design and stays stable; this file describes state and changes every step.

Legend: `[ ]` not started -- `[~]` in progress -- `[x]` done -- `[!]` blocked / needs a human

## Phase 0 -- App Store Connect setup (manual)
- [!] 0.1 Change pricing Paid -> Free -- **cannot be done from this environment (web UI only)**
- [!] 0.2 Create Non-Consumable IAP `com.bystruev.dientempo.premium` -- **manual, web UI**
- [!] 0.3 Create sandbox tester account -- **manual, web UI**
- [!] 0.4 Update "What's New" text -- **manual, web UI**

## Phase 1 -- PremiumManager.swift
- [x] 1.1 Create `Dientempo/PremiumManager.swift`
- [x] 1.2 Create `DientempoTests/PremiumManagerTests.swift` (5 tests, all pass)
- [x] 1.3 `xcodebuild build` + `xcodebuild test` pass

## Phase 2 -- PurchaseManager.swift
- [x] 2.1 Create `Dientempo/PurchaseManager.swift` (StoreKit 1, delegate methods `nonisolated` + hop to `@MainActor` -- needed since PurchaseManager is `@MainActor` but StoreKit's ObjC-era delegate protocols aren't actor-isolated)
- [x] 2.2 `xcodebuild build` passes

## Phase 3 -- Wire into counting flow
- [x] 3.1 `ToothCountingViewModel.swift`: add `onSessionWillStart` choke point
- [x] 3.2 `ContentView.swift`: lock screen + StateObjects + countdown timer wiring
- [x] 3.3 `xcodebuild build` passes (zero warnings from new code)

## Phase 4 -- Info.plist
- [x] No changes needed (confirmed no plist keys required for StoreKit 1 non-consumable)

## Phase 5 -- Xcode "In-App Purchase" capability
- [!] Manual step in Xcode GUI (Signing & Capabilities) -- not done yet, needs Denis

## Phase 6 -- Testing
- [x] Unit tests (Phase 1.2) pass via `xcodebuild test`
- [x] App builds clean via `xcodebuild build`
- [x] Manual smoke test on `iPhone 17e` simulator: main UI renders unchanged (screenshot-verified)
- [x] Manual smoke test: forced `dientempo.lastRunDate` to "today" via the app's container
      plist, relaunched, confirmed the lock screen renders with the correct copy, a
      midnight-anchored countdown (verified ticking live: 09:19:55 -> 09:19:36 over ~19s,
      matching wall-clock time), and the purchase button correctly disabled (no product
      loaded -- expected without an approved App Store Connect IAP + signed-in sandbox
      tester). Cleaned up the injected state afterward.
- [!] 6.3 Real purchase flow, 6.4 Restore flow -- needs Phase 0 (App Store Connect IAP +
      sandbox tester account) done first; cannot be tested from this environment
- [!] 6.5 Edge cases (time zone travel, DST, app killed mid-run) -- needs a human/device
- [!] 6.6 TestFlight distribution -- needs a human

## Phase 7 -- Git
- [x] Changes committed (see suggested commit messages in `PLAN.md` Phase 7)
- [x] PLAN.md and STATUS.md committed alongside code

---

## Log

- 2026-09-05 -- Phase 3 done: added `onSessionWillStart` to `ToothCountingViewModel` (fires
  only on a true `.ready`/`.finished` -> `.running` transition, closing the tap/swipe bypass
  of the daily limit) and rewired `ContentView` with the lock screen, `PremiumManager`/
  `PurchaseManager` StateObjects, and a self-correcting countdown timer. Fixed one more
  concurrency warning during this pass: the `Timer.scheduledTimer` closure isn't MainActor-
  isolated by default, so calls to `@MainActor`-isolated `PremiumManager` members from inside
  it produced warnings; wrapped the closure body in `Task { @MainActor in ... }`. Final build
  has zero warnings from new code.

  Manually smoke-tested on the `iPhone 17e` simulator: booted, installed, launched -- main UI
  renders identically to the pre-change baseline (screenshot-verified). Forced the free-tier
  lock by editing `dientempo.lastRunDate` directly in the app's sandboxed
  `Library/Preferences/com.bystruev.dientempo.plist`; hit (and worked around) a simulator
  `cfprefsd` caching quirk where on-disk edits get clobbered by the daemon's in-memory cache
  on the app's next write -- fixed by `launchctl kickstart -k` on
  `com.apple.cfprefsd.xpc.daemon` inside the simulator between edits. Confirmed the lock
  screen renders correctly, the countdown is anchored to midnight (correcting the original
  draft's rolling-24h bug) and ticks live in real time, and the purchase button is safely
  disabled when no product is loaded (expected without Phase 0's App Store Connect setup).
  Cleaned up the injected preference key and screenshots afterward so the simulator/repo are
  left in a clean state.

- 2026-09-05 -- Phase 1 + 2 done. Added `PremiumManager.swift`, `PurchaseManager.swift`,
  `PremiumManagerTests.swift` to the Xcode project by hand-editing `project.pbxproj`
  (PBXBuildFile/PBXFileReference/PBXGroup/PBXSourcesBuildPhase entries) since the project
  uses classic explicit file references, not synchronized groups. Verified with
  `xcodebuild -list` after editing. One real compile error caught: `SKPaymentTransactionState`
  has no `.pending` case in StoreKit 1 (that's a StoreKit 2 concept) -- fixed. All 5 new unit
  tests pass via `xcodebuild test -only-testing:DientempoTests`, plus the pre-existing
  `SpanishNumberFormatterTests`. Confirmed system frameworks (StoreKit here, same as
  AVFoundation/Speech elsewhere in the project) link automatically without needing explicit
  `PBXFrameworksBuildPhase` entries -- consistent with how the rest of the project already
  works.

- 2026-09-05 -- Reviewed original `PLAN.md` draft before coding. Found and documented 6
  issues (2 of which would not compile as originally written; see PLAN.md "Corrections made
  vs. the original draft"). Rewrote `PLAN.md` with granular steps and the fixes baked in.
  Created this `STATUS.md`. Confirmed baseline: `xcodebuild build` succeeds on `main` before
  any changes (bundle id `com.bystruev.dientempo`, deployment target iOS 16.0, Swift 5.0,
  team `8J39KF9DMS`, simulator available: `iPhone 17e`).
