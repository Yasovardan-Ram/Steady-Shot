# SteadyShot v8.3 — Gameplay & Immersion Upgrade

## Included
- Physiology-aware shot discipline: shot spread responds to the real sensor-derived load and the phase of the last real breathing-rate estimate.
- No Focus Mode, hold-breath control, or temporary accuracy boost.
- The initial reference waveform remains display-only and is never used by the aiming or shot-discipline calculations.
- Existing real readings remain the source for the breathing rhythm through short gaps; the game does not switch back to the startup reference.
- Existing all-level hitbox forgiveness and the extra sandstorm hitbox bonus are preserved.
- Sandstorm visibility now has subtle, irregular gust pulses; ballistic wind strength varies gradually during storm waves and remains reflected in the wind gauge.
- Sandstorm thermal silhouettes are less reliable and lower contrast.
- Night lighting is darker, with reduced ambient and moonlight energy.
- Scope receives restrained lens-edge, dust-speck and reflection details.
- Mission results now include average first-shot response time across waves.
- Existing bolt-action, recoil, hit confirmation, weapon audio, and environmental audio systems are retained.

## Repairs and checks
- Checked every literal `res://` resource reference in project scripts/scenes/resources: no missing paths found.
- Checked `presage_bridge/sensor.js` with `node --check`: passed.
- Validated `package.json`: passed.
- Godot editor/parser/runtime validation was not available in this build environment. Open the project in Godot 4.2+ and run it to complete engine-side verification.
