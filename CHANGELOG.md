# Changelog

## 0.2.0 - 2026-08-05

### Changed
- Permission prompts now appear only inside the Setup Assistant, each behind its own Allow button, instead of stacking dialogs at launch.
- The Setup Assistant asks you to record your own shortcut from scratch, and the Input Monitoring permission moved next to it so the whole shortcut setup lives in one step.
- Settings and Setup Assistant windows now stay in front of other apps instead of getting lost behind them.

### Fixed
- The recording shortcut and Esc now start working immediately after Input Monitoring is granted, no relaunch needed.
- Permissions granted once now survive switching between debug, release and downloaded builds (unified code signing identity).
- The app now registers itself reliably in the Input Monitoring pane of System Settings.

## 0.1.0 - 2026-08-05

First release: 100% local dictation for macOS with Whisper and Apple engines, hybrid streaming for long dictations, recordable global shortcut, push to talk, hook mode, onboarding assistant and auto-update.
