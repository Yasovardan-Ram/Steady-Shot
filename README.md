
# SteadyShot

Desert canyon sniper game. Godot 4.2+ (standard build). The core game has no external dependencies; the optional Presage sensor bridge uses Node.js packages.

## Run
1. Open Godot, **Import**, pick `project.godot`, **Import & Edit**.
2. Wait for the first import to finish (large terrain meshes and the WAV files).
3. Press **F5**. Sign in or continue as guest, complete sensor setup (or skip it), then choose **START MISSION**. Review the commander briefing and choose **DEPLOY** (or press Enter); **Esc** returns to the title screen.

## Controls
| Input | Action |
|---|---|
| WASD | move along the ledge (W steps you toward the cliff edge for a steeper view of the valley floor) |
| Mouse | aim |
| Left click | fire (6 rounds, bolt cycle between shots) |
| R | reload now (also happens automatically when the magazine is empty; takes you out of the scope) |
| Right click | scope on/off |
| Mouse wheel | zoom 4x / 8x / 12x (while scoped) |
| N | night vision on/off (night waves only) |
| Esc | pause menu (audio sliders, session stats, scoreboard) |

## Presage SmartSpectra sensor (optional)
At startup, after the local player account screen, enter a SmartSpectra API key to enable webcam-derived pulse and breathing estimates. The key is passed to the local Node.js bridge through a temporary process environment variable, removed from the parent environment immediately after process creation, and is not saved in the project or settings. Choose **CONTINUE WITHOUT SENSOR** for fallback play.

No manual `npm install` is required. When the player first enables the sensor, the game checks for the bridge dependencies and automatically runs `npm install` in the background if they are missing. This first-time setup requires Node.js/npm and an internet connection; a setup status is shown while it runs. Later launches reuse the installed `node_modules` and do not reinstall. If automatic setup fails or times out, the game continues in fallback mode and can still be played without the sensor. The bridge pins SmartSpectra SDK 3.5.0 and uses `ws` 8.x. Once dependencies are ready, the game starts `node presage_bridge/sensor.js` when sensor mode is selected. The bridge listens only on `127.0.0.1:8765`, authenticates the local game connection with a random per-session token, and streams rate estimates over WebSocket. The API key is never sent over WebSocket; SDK telemetry is disabled. Heart rate and breathing influence the existing scope sway with smoothing, confidence gating, stale-data fade and configurable player exports. Start a mission to see the bottom-right HUD graphs, which show measured heart-rate and breathing-rate history (not raw ECG or respiratory waveforms). The sensor status line surfaces Presage camera/readiness hints such as lighting, face position, and missing-rate diagnostics. The estimates are informational and are not medical measurements.

## Rules
Waves of enemies cross the valley toward your cliff, walking, sprinting and stopping. Anyone who crosses the red-flag
breach line costs a life (5 lives). Headshots score more. Armoured enemies (wave 3+) need two body hits or one headshot.
Bullets take time to arrive, drop, and drift in the wind (shown top right only during active gameplay; dust in the air drifts the same way).
The rifle is zeroed at 150 m. One mil-dot = 1 m per 1000 m.
Settings and the top-8 scoreboard are saved in `user://steadyshot.cfg`.

## Night waves
Every third wave (3, 6, 9, ...) is a night wave. The sky, sun and fog fade to moonlight over a few seconds, stars appear, and the
ambience switches to crickets, owls and distant coyotes. Night vision engages automatically (press **N** to toggle it):
a green amplified view with grain, and enemies show a faint body-heat glow that only the goggles can see. Without the goggles
the valley is very dark. The next day wave switches everything back.

## Latest changes
* Presage diagnostics now relay live validation hints and metric-packet status to the in-game HUD; rate histories are positioned bottom-right and hidden outside active gameplay.
* Wind gauge is hidden on title/auth/setup/pause/game-over screens and appears only during active gameplay.
* Added EXIT GAME buttons to the account, sensor setup, title, pause, and game-over screens; exiting stops the sensor bridge first.
* Final pass: shot-consistency scoring is calculated at firing time from real sensor freshness, physiological load, breathing phase and player movement; shots without fresh sensor data are marked unrated.
* Wind drift remains active but has been reduced so heart rate and breathing remain the dominant accuracy influences.
* Added a skippable pre-deployment commander voice briefing, more deliberate reload presentation, and restrained nearby enemy hesitation on occasional gunfire.
* Night waves with night vision (see above).
* Realistic scope sounds: rifle shouldered with a short breath in, a lighter sound coming off the scope, and a knurled-ring turn with detent clicks when changing zoom.
* Boxed HUD (score, enemies, life pips) and a LEVEL badge under the minimap that goes up after every cleared wave.
* The minimap shows the breach line as a red dashed line; enemies within 35 m of it pulse yellow.
* Heavier recoil: the view snaps up and sideways, shakes, and settles back over about a second (a bit gentler when scoped).
* More rifle animation: raise-on-start, breathing, walking bob, lag behind mouse movement, kick, ejected brass, scope raise, chambering at the end of a reload.
* R reloads.

## Earlier changes
* **Enemies stay shootable.** The old low-wall problem: the stone parapet sat 5 m in front of you and hid everything steeper than ~7 degrees
  below the horizon. The parapet is now a low wall right at the lip, the walls moved to the lip, and you start closer to it.
  Enemies follow 10 baked lanes (`scripts/lane_data.gd`) that were computed from the terrain and rock positions so every lane stays in
  view of the nest. They still weave and sprint, they just never walk behind a butte.
* **Gun**: new detailed rifle (tapered barrel, muzzle brake, scope with turrets, bipod, chassis stock, gloved hands). Bolt animation and
  a magazine drop/insert in the reload.
* **Enemies**: slightly easier to read (dark teal shirt, cream head wrap, backpack) and a faint dust trail while they run.
* **Map**: breach line with flags and wire, scattered pebbles and dry grass, cacti, sandbags / crates / camo net at the nest, slow clouds,
  warmer light.
* **Sound**: everything re-synthesized. Three rifle shot variants (supersonic crack, muzzle blast, canyon echoes), a mechanical bolt cycle
  with ringing brass, a full magazine-swap reload, dirt / rock impacts with the delay of sound, ricochets, alarm bell and horn.
  Ambience is a gusting wind bed that follows the wave's wind, quiet crickets and random wren / raven / hawk / rockfall / gust events.
* **Menu**: one styled screen for title, pause and game over, with Master / Effects / Ambience sliders, run stats and a saved scoreboard.

## Structure
```
scenes/main.tscn          environment + player + enemies/bullets/effects + Ambience + Scenery + HUD + GameManager
scenes/player.tscn        CharacterBody3D, camera, rifle
scenes/weapon.tscn        rifle model + sounds
scenes/bullet.tscn        ballistic bullet
scenes/enemy.tscn         infantry with body and head hitboxes
scenes/hud.tscn           ammo, scope reticle, radar, banners, menu
scenes/environment/       desert canyon (terrain, rocks, sky, sniper nest barriers)
scripts/player_controller.gd  movement limits, look, scope/zoom, sensor-driven sway, recoil
scripts/weapon.gd             ammo, bolt cycle, auto-reload, shot sound variants, spawns bullets
scripts/bullet.gd             ballistics + hit detection (dirt / rock / enemy)
scripts/enemy.gd              lane-following advance AI, hit reactions
scripts/lane_data.gd          baked enemy lanes
scripts/terrain_sampler.gd    ground height from the terrain collision data
scripts/game_manager.gd       waves, score, lives, wind, menus, saved settings and scores
scripts/menu_panel.gd         title / pause / game-over screen
scripts/ambience.gd           wind bed, crickets, random natural sounds
scripts/scenery.gd            runtime decoration, clouds, dust
scripts/audio_buses.gd        SFX / Ambient buses and volume helper
scripts/hud.gd, scope_reticle.gd, radar.gd   display
scripts/sensor_bridge.gd       local Node.js process + WebSocket lifecycle
presage_bridge/sensor.js      SmartSpectra SDK process and metrics forwarding
presage_bridge/package.json  pinned bridge dependencies
scripts/sensor_setup.gd       masked session-only API key prompt
scripts/sensor_history.gd     measured rate-history HUD graphs
audio/                        synthesized sound effects
```

## Tuning
Weapon: `bolt_time`, `reload_time`, `muzzle_velocity`, `zero_range`. Player: `sway_degrees`, `zoom_levels`, `bounds_x/z`.
Enemy: `walk_speed`, `run_speed`, `wander_width`. GameManager: `breach_z`, `start_lives`; wave size/speed/wind in `_start_wave` and `_spawn_enemy`.


## v8 changes
- **Night vision** only works through the scope. Every 3rd wave is night; press **N** and the circle you are looking through turns into green night vision (enemies show up as body heat). Nothing changes on the rest of the screen. A small "Press N for night vision" hint appears at night instead of the old status text under the wind.
- **Sandstorm** every 5th wave (5, 10, 15 ...), day or night: thick sandy fog (about 150 m of clear sight), dimmer sky and light, blown sand across the screen, a roaring wind, stronger wind drift on your bullets, and the minimap flickers.
- **HUD text** cleaned up: a wind gauge with a scale and marker instead of plain text, lighter regular-weight type with a faint shadow instead of heavy outlines, tidier bolt / breath / zoom lines.
- **New reload sound** (`audio/reload.wav`), timed to the animation: mag release, mag out, pouch velcro, mag seat, tug, bolt unlock / rack / feed / lock.
- **Accounts**: log in, sign up, or play as guest. Accounts live on this computer only (`user://accounts.cfg`): salted, repeatedly hashed passwords, never the password itself. Each account has its own scoreboard. "Keep me signed in" opens your account directly next time; "Switch account" is on the title and game-over screens. Five wrong passwords lock that account for 30 seconds.

- **Hitboxes** slightly larger (about 25%): body 0.74 m wide (was 0.6), head 0.44 m (was 0.34). The models are unchanged, so enemies are just as hard to spot.

## v8.2.1 parser compatibility fix

The sensor-history graph now explicitly types the minimum, maximum, sample, and
coordinate values as `float`. This avoids Godot treating `Array.min()` and
`Array.max()` results as inferred `Variant` values when warnings are configured
to be errors.


## Sandstorm and night difficulty tuning (v8.2.4)

- Every fifth wave remains a sandstorm. Enemy body hitboxes are widened by 16% and their head hitboxes by 12% on those waves only; visible enemy models are unchanged.
- Press **N** during a sandstorm to enable a restrained amber thermal hint, visible only through the scoped optic. It is intentionally weaker than night vision and does not reveal enemies across the full screen.
- On night waves, the ambient light, sky, and moonlight have been reduced for darker nights.
- The existing full night-vision mode remains available on night waves.


## v8.2.5 gameplay and sensor HUD adjustments

- Enemy body/head hit areas receive a subtle permanent increase on every level; sandstorm levels retain their additional hit-area bonus.
- Heart-rate and breathing-rate panels are grouped at the bottom-right beside the wind gauge.
- During startup only, the panels show clearly labelled visual reference placeholders (72 BPM and 14 breaths/min). These are display-only and are never sent to the player controller or used for aiming.
- The first valid Presage sample replaces its corresponding placeholder. If samples later pause, the most recent actual sample remains displayed and its rate continues to drive the subtle rhythm animation while the extra sensor-driven difficulty fades toward neutral; the startup placeholder is never restored during that session.
- Sensor status diagnostics are printed once per distinct status in the Godot output, not repeatedly displayed on the gameplay HUD.


## v8.2.6 gameplay and sensor HUD polish

- Slightly increased the default enemy body/head collision volumes on every level. Sandstorm-specific hitbox scaling remains an additional, temporary bonus.
- Repositioned heart-rate and breathing-rate history panels into a single horizontal row beside the wind gauge at the bottom-right of the gameplay HUD.
- Refined the rate-panel typography and spacing.
- Startup reference animation (72 BPM and 14 breaths/min) is display-only, clearly labelled as reference-only, and expires after three minutes if no real sample arrives. It is never passed to player stability or recorded as Presage data.
- The first valid real sample from either metric permanently ends both startup reference animations for the session; each panel then shows only its own actual measurements. Later intermittent readings retain the real sample history; gaps longer than 20 seconds are shown as gaps rather than connected as if continuous. The display never falls back to the startup reference after real data has arrived.
=======
# Steady-Shot

