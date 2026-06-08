# Claude Code Handoff Document
**Last Updated:** 2026-06-08
**Updated By:** Opus 4.7 (Dweezil, Windows)

---

## SESSION — 2026-06-08 (Opus 4.7, Dweezil) — Full rewrite + game loop in place

Pyrrha went from "old codebase with a half-working asteroid manager and lots of stale stealth-game code" to a playable game with stages, scoring, win/loss, and a deep stack of visual flair. ~2,400 LOC of GDScript now. This session covered roughly the entire game.

### Game premise (current)
You're a single ship defending Earth from asteroids. Mine rocks with a laser; auto-turret pellets help. Big rocks fragment. Rocks on collision course are flagged on the minimap. Each successful Earth impact adds to a cumulative **death count** (reverse score — lower is better). 6 stages, each with a quiet period (regular spawns + scripted threats) ending in a boss event. Between stages: dock at the Station to heal, leave its vicinity to start the next stage. Beat stage 6 = win. Hull or shield depletion = death screen + retry.

### Major systems (where to look)

**Asteroid lifecycle** — `Asteroid_Manager.gd` (~700 lines) is the heart.
- Single bounded asteroid pool with high-water-driven adaptive sizing (grows on demand, trims excess slowly). Dust pool same model.
- Per-texture **silhouette polygon cache** built once at startup via `BitMap.opaque_to_polygons`. Whole rocks get accurate silhouettes; fragments get cheap 8-vertex bounding octagons (convex = no decomposition cost).
- **Collision layers**: whole rocks on layer 2 (collide with player + other wholes), fragments on layer 3 (collide with player only). No fragment-vs-fragment pairs. Player on layer 1 with mask 6. Mining rays mask 6.
- **Stage phases**: ACTIVE (regular + scheduled threats + boss at end) → RESPITE (heal at station, leave to advance) → next stage or WON. DEAD halts everything on player death.
- **Boss patterns** in `BOSS_PATTERNS` const: list of `{at, fn, args}` events fired in sequence. Composable from primitives `_spawn_fastball`, `_spawn_clump(count, big)`. Six stages defined; finale is "big_clump(12) + 2× fastball."
- **Threat fate**: when a rock first qualifies as a collision-course threat, a random point along its trajectory's chord through Earth's disk becomes its `impact_point`. The rock travels normally; on reaching `impact_point` it snaps there, triggers Earth explosion (whole rocks only), adds `impact_deaths` to the cumulative score, vanishes (no dust, no fragments).
- **Population/deaths**: sampled from Earth's own texture. Land-color heuristic (`(r+g)/2 - b`) gives land mask; FastNoiseLite gives density variation. Multiplied by `SIZE_DEATH_SCALE` (whole 1.0, large 0.20, medium 0.05, small 0.005).

**Player** — `actors/Player/Player.gd` (~500 lines). Pyrrha convention: forward is `+X`, Sprite2D is rotated `+90°` so the upward-drawn art aligns. Two control schemes (`GlobalSignals.ControlMode`): MOUSE_TURN (mouse aims ship, A/D strafe) and KEYBOARD_TURN (A/D rotate at fixed rate, no strafe).
- **Thrust** is sharply asymmetric: main forward `1500` vs reverse/strafe `200`. Big course changes mean committing to a spin; subtle drift via weak side thrusters.
- **Stop mode** (Ctrl): picks the faster brake each frame — face prograde + retros, or spin retrograde + mains. Compares `rot/turn_rate + speed/thrust` for both and burns whichever's shorter.
- **Mining laser** (LMB): 200° forward cone gate (silent failure outside). Continuous beam; sparks occasionally where it hits.
- **Energy** unified: any drain stops regen for that frame. Mining 120/sec, thrust 20/sec, regen 80/sec when idle.
- **Shield** is a real physical collision shape (`ShieldHull` CollisionShape2D). When `shield > 0` the shield circle is the active collider; when `shield <= 0` the silhouette `CollisionBox` takes over. Toggled deferred each frame so the active collider always matches state. Rings emit on contact via pooled `ShieldRipple`.
- **Collision damage** is kinetic + mass-aware. Below `soft_bounce_speed = 50` → elastic bounce, zero damage. Above → `dmg = (closing/100)² × impactor_mass`. Shield absorbs first; overflow eats hull. Fragments below `plow_through_mass_threshold = 0.3` don't slow you down — `pre_move_vel - velocity` lost to them is restored proportionally. Mass values: whole 1.0, large 0.45, medium 0.22, small 0.07.
- **Visual flair**: pooled `ShockBurst` radial sparks at laser hit points (25% chance per frame per beam) and at ship-rock contact. Pooled `ShieldRipple` on shield hits. Pooled `DustCloud` puffs on asteroid death (lots of randomization across all axes; density-driven alpha so big clouds fade rarefied; ~25% chance per puff to be a "mega" cloud living up to 3 minutes).
- **Thruster choreography**: separate `ForwardThrusterFlame*`, `RetroThrusterFlame*`, and side `ThrusterFlame*/Right2` groups, each fired per the input table at the top of `_update_thrusters`. Rotation thrusters fire as couples (left-forward + right-retro = CW torque). Sub-flames flicker per-frame brightness for life.

**UI** — `UI/GUI.gd` builds the score label (top center, red, big), status bar (bottom center; the text box describing the current phase), and the HULL/SHIELD/ENERGY bar labels. `UI/PauseMenu.tscn` is the Escape menu (Save / Restart / Main Menu / Settings / Quit; Settings flips `GlobalSignals.control_mode`). `UI/WinScreen.tscn` and `UI/DeathScreen.tscn` are CanvasLayers that pause-and-show on `game_won` / `player_died` signals.

**Minimap** — `actors/Player/Mini_Map.gd` + `MinimapThreatOverlay.gd`. Light backdrop circle + border; border pulses red while any threat is on a collision course. Threat trajectory lines extend in both directions along velocity, clipped to the minimap disk via segment-circle intersection (`_clip_segment_to_circle`). The most-imminent threat (by time-to-impact) blinks its marker ring. Earth's marker pins to the minimap edge when out of range so the player can always navigate home. Asteroid threats are detected independent of detection_radius; markers still gated by it. Earth's collision radius is queried live from its sprite texture + scale (no hardcoded value).

**Earth impact 3D effect** — `EarthExplosionStage.gd/tscn` is a single `SubViewport` containing a `Camera3D` looking down at the origin and a 3D scene that holds all active explosions. 2D impact positions are mapped to 3D points on a unit sphere (`z = sqrt(1 - x² - y²)`). The viewport's texture overlays Earth via a Sprite2D sized to match Earth's pixel diameter. Currently shows `ExplosionPlaceholder.tscn` — a glowing orange sphere that grows + fades. **Replace this scene with the real 3D model + AnimationPlayer when the asset lands**; nothing else changes.

### Architectural decisions worth knowing about

- **No worker thread for asteroid prep**. The original had a threading model around break-subtree pools. The user pushed back. I argued (and they agreed) that the "break subtree" abstraction was unnecessary — a single bounded pool of bare asteroids covers it. Texture loading is the only expensive thing, and it's done once at `_ready()`. No mutexes, no semaphores, no worker. Pools grow on demand, trim slowly when oversized.
- **Adaptive pool with high-water + decay** rather than fixed cap. The user explicitly called out fixed caps as lazy. High-water mark of concurrent in-use entries with slow exponential decay (5%/sec). Excess idle entries past `high_water × slack` are queue_freed one per second.
- **Per-frame spawn cap (`MAX_SPAWNS_PER_FRAME = 6`)** to spread post-fragmentation tree mutations across frames. A 40-fragment break drains over ~7 frames instead of one.
- **Convex hulls for fragments, silhouettes for wholes**. Convex decomposition is the physics-server hitch when many fragments spawn at once. Fragments get cheap regular octagons. Whole rocks (few in number, high visibility) get accurate silhouettes.
- **Asteroid `reset()` runs on pool members not yet in tree** — that's why `_ensure_node_refs()` resolves `@onready` vars via direct `$NodeName` (which works pre-tree). Timer start is deferred via `start_grace_period()` called by the manager AFTER `add_child` because Timer.start() requires being in the tree.
- **Earth-impact "no dust, no fragments"**: `Asteroid.died_to_earth` flag, set by `_on_earth_impact` before death. `_on_asteroid_died` checks it and skips dust + fragmentation. Only the explosion plays.
- **Trajectory chord random** for impact point, not random-anywhere-on-disk. Rock follows its straight line; the random pick is where along the chord it dies. Looks like a real atmospheric burn-up.
- **No max speed** on the player. High speed is risk/reward — the kinetic damage formula makes a graze at >1500 m/s lethal.
- **Earth and ship are on inconsistent scales** (Earth = ~4800 world units / ~4.8 km if you assume ship is 30m). This is intentional gameplay scale; real solar-system scale would mean Earth is microscopic next to the ship. Asteroids are reasonable (whole rock ~Tunguska-scale).
- **Mining laser texture removed**. Line2D with `texture_mode = LINE_TEXTURE_TILE` and the old `LaserOnePixelWide.png` rendered nothing in Godot 4.6 (texture import was broken, killed the entire line). Beam now uses `default_color` only.

### Known follow-ups Dweezil should look at

- **Real explosion 3D model**. Replace `ExplosionPlaceholder.tscn`'s sphere with the real animated model. Adjust `start_scale`/`end_scale` to its natural units. Everything else (camera, viewport, position math) is already in place.
- **Population texture**. Currently the death count is sampled from Earth's own texture (land/ocean heuristic + noise). User said estimates are fine; a real population-density texture would make "this rock is heading for Kuala Lumpur" land properly. Drop in `assets/population_density.png` and swap `_sample_deaths` to read that instead.
- **Mining beam offsets `(134, ±98)`** are placeholder; the user fine-tuned MiningRayLeft and the rest were mirrored. If the new ship sprite's gun ports move, re-mirror.
- **Thruster scale/positions** were last placed by the user in the editor (see ThrusterFlame at (-227.5, 0), etc.) Player scale is `(1, 1)` now (halved from the original 2). Everything proportional.
- **`Stage_Timer` node** in Main.tscn is vestigial — old timer-driven stage logic is gone, replaced by `_advance_phase`. The connection still exists but routes to a no-op `_on_Stage_Timer_timeout`. Safe to remove the node + connection in the editor.
- **PauseScreen.tscn** (old) and `PauseScreen.gd` (old) are vestigial. Replaced by `PauseMenu.tscn` / `PauseMenu.gd`. Safe to delete.

### Files added this session
```
Asteroid_Manager.gd (rewritten)
actors/Player/Player.gd (rewritten)
actors/Player/Asteroid.gd (rewritten)
actors/Player/Asteroid.tscn (rewritten)
actors/Player/MassDriverTurret.gd / .tscn
actors/Player/Pellet.gd / .tscn
actors/Player/ShieldRipple.gd / .tscn
actors/Player/ShockBurst.gd / .tscn
actors/Player/DustCloud.gd / .tscn
actors/Player/Mini_Map.gd (rewritten)
actors/Player/MinimapThreatOverlay.gd
EarthExplosionStage.gd / .tscn
ExplosionPlaceholder.gd / .tscn
Pack_Six.tscn / Pack_Twelve.tscn
UI/PauseMenu.gd / .tscn
UI/WinScreen.gd / .tscn
UI/DeathScreen.gd / .tscn
UI/GUI.gd (rewritten)
globals/GlobalSignals.gd (expanded)
project.godot (4.6 bump, control bindings, AA, resizable window)
Main.tscn (rebuilt — Earth/Moon/Station/PauseMenu/WinScreen/DeathScreen/EarthExplosionStage)
```

### Files deleted (cleanup of the stealth-cat-game artifacts)
Darkfuzz/, PlayerHearing, CapturableBase*, CutScene*, BulletManager, Pathfinding, AI/Ally/Enemy, WeaponManager, SightZone, Guns_Ray_Cast, Break*, furniture/, eyebeams/, LAZEREYEZ.jpeg, animations/player/, Dark_River_logo, VisibilityArea, White-circle, semicircle, WoodStove, "new assets/" (assets relocated).

---
