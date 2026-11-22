# SteadyShot v8.10 — Developer Testing + Thermal Visibility

## Thermal rendering
- Reworked sandstorm thermal body materials to use intense, unshaded red/orange emission.
- Applies the thermal silhouette to every visible enemy mesh/body part, not only the torso/head.
- Increased silhouette expansion and emission strength so the complete enemy outline is easy to acquire through the scope.
- Thermal layer remains scoped and only appears while the sensor is enabled; standard rendering is unchanged otherwise.

## Developer login
- Login username: `-dev`
- Login password: `-mode`
- This special login bypasses account creation and enables local developer controls.
- `F6`: jump forward one wave immediately.
- `F5`: jump backward one wave immediately (minimum wave 1).
- `K`: instantly eliminate all currently spawned enemies.
- Regular accounts and guest gameplay retain the original wave progression and enemy health.

## Testing note
- Source changes were packaged; a Godot runtime was not available in this environment, so in-engine visual/gameplay verification remains to be done.
