# SteadyShot v8.4 — Final Completion Pass

## Changes
- Added a skippable pre-deployment commander briefing with a short radio-style voice line.
- Added shot-time consistency scoring based on physiological load, breathing phase, and player movement. Wind is deliberately excluded from this score.
- Added steady / moderate / unstable shot counts and average consistency to the mission results.
- Reduced the magnitude of wind affecting projectiles while keeping the wind gauge synchronized with the actual ballistic wind. Heart rate and breathing remain the dominant accuracy influences.
- Added very small, occasional hesitation reactions from nearby enemies when a shot is fired; no alert/chase AI was added.
- Improved signup persistence error feedback. Existing sensor dropout handling, account storage format, weapon controls, and no-focus/no-hold-breath design are retained.

## Verification
- Static resource-reference and script checks are performed as part of packaging.
- Godot engine parsing and runtime testing must be completed in Godot 4.2+; no Godot executable is available in this build environment.
