# SteadyShot v8.7 – Thermal Visibility & HUD Readability

## Changes
- Increased the sandstorm thermal silhouette visibility and added a restrained red emissive heat treatment to enemy head and torso meshes.
- Disabled depth writing on the storm heat overlay meshes so the translucent heat treatment remains consistently visible.
- Added a dark translucent, warm-outlined backing plate behind the bottom-left ammunition/reload HUD for contrast over bright or busy scenery.
- Preserved the v8.6 commander briefing text and supplied MP3 audio.

## Validation
- ZIP archive integrity and static source checks passed.
- Godot runtime validation was not available in this environment; test the thermal optic in a sandstorm wave and confirm the HUD layout in-game.
