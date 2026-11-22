# SteadyShot v8.12 — Thermal Contrast, Briefing Skip & Music

## Thermal vision
- Replaced the flat red thermal material with a dedicated HDR emissive spatial shader.
- Added a hot-core palette that transitions from deep orange/red edges to yellow-white centres.
- Raised environment bloom response so emissive heat regions read as illuminated sources.
- Expanded thermal visibility to the head, helmet, torso and armour plate while retaining depth testing and scope-only camera-layer activation.
- Reduced the thermal optic's neutral post-process strength so it does not crush the heat signature or turn the scope orange.
- Preserved readable daytime sandstorm lighting by reducing the storm sun-energy penalty and modestly increasing ambient fill.

## Mission briefing
- Replaced the briefing-only Play Again button with a bottom-positioned SKIP button.
- SKIP starts deployment and the briefing panel (including the button) is hidden on transition.
- The normal pause menu still retains its Restart button; other menus retain their existing actions.

## Audio
- Added `nastelbom-dark-trailer-638572.mp3` as the mission briefing music under the commander speech, with a quiet mix and fade-out after speech completion or skip.
- Added `the_mountain-nostalgic-610152.mp3` as a rare ambient cue: at most once on every second wave, delayed into the wave, limited to approximately 20 seconds, and faded in/out.
- Rare ambient music is stopped/faded on wave clear, pause, game over, and return to title.

## Validation
- Verified the ZIP contents and referenced project asset paths with static checks.
- Godot runtime/editor validation was not available in this environment; please open the project in Godot 4 and test the thermal optic in a daytime sandstorm, briefing Skip, and audio transitions.
