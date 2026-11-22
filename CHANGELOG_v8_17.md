# SteadyShot v8.17 — Auth HUD cleanup and stronger developer thermal testing

- Hide the LEVEL badge while the shared STEADYSHOT brand title is shown on login, signup, and API-key screens. Restore its previous visibility when leaving those screens.
- Increase developer-only enemy hitbox scale from 1.8x to 2.8x the base dimensions (an additional 100 percentage points over the previous 80% bonus); normal players are unchanged.
- Thermal sensing now overlays the full visible enemy model, including torso, pelvis, head, arms, legs, armor, and carried equipment.
- Increase thermal red/orange HDR emission substantially and slightly enlarge the overlay silhouette for easier detection.
- Keep thermal overlays active on sandstorm waves even when a wave also has night conditions.
