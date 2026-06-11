# Claude Code Handoff Document
**Last Updated:** 2026-06-11
**Updated By:** Sonnet 4.6

---

## SESSION — 2026-06-11 (Sonnet 4.6) — 30-stage ramp, formation randomization, polish

### Formations randomized
`_spawn_random_clump(count)` rolls between tight cluster / line / semicircle each spawn. All clump-class boss patterns (`clump_4`, `clump_4_plus_fastball`, `clump_6`, `finale`) call it — formation type rotates per spawn so no two playthroughs feel identical. Individual `_spawn_clump`, `_spawn_line`, `_spawn_semicircle` remain as primitives.

### 30-stage difficulty ramp
Replaced the 6-stage definition with 30. Primary levers (`threats`, `max_threats`) grow slowly across the full arc. Flavor mechanics introduced one per stage:
- S4 off-radar; S7 clump boss; S8 blocker; S11 Type-1 sleeper; S15 split-volley; S16 Type-2 sleeper; S18 clump-6 boss; S20 finale boss
- After S20 all mechanics are in play; S21–30 cycle the harder patterns while pushing `threats` (→14) and `max_threats` (→9)
- `threats > max_threats` is intentional — overflow creates follow-up volleys after the first clears

### Polish fixes
- **Death jitter**: `_sample_deaths` rolls `randf_range(0.65, 1.45)` on the computed result. Same rock, same continent, different numbers every time. Floor still respected.
- **Station departure velocity zeroed**: `StationShop._on_depart` sets `player.velocity = Vector2.ZERO` before emitting the departed signal. Ship is stationary when control returns.
- **Mining laser distance falloff**: damage scales `clamp(1.0 - dist/2000.0, 0.3, 1.0)` from ray origin to hit point. Full at contact, 30% floor at 2000+ units. Tunable in `Player._fire_beam`.

---

## DESIGN BACKLOG — Difficulty mechanics

Implemented:
- **Threat rock volley system** — capped concurrent threats per stage (2→9), holds until field clear then fires full volley at once
- **Asteroid type differentiation** — C (fragile, many frags), S (baseline), M (tough, dense, lethal, few frags)
- **Sleeper rocks (Type 1 dive)** — proximity/random/attack-triggered, homes on player, not counted against threat cap
- **Sleeper rocks (Type 2 fuse)** — `sleeper_target_earth=true`, counts down a fuse then steals a threat cap slot and aims at Earth
- **Blocker rock** — PD controller positions itself between player and nearest threat; obstruction not aggression
- **Off-radar rock** — invisible to minimap; player has to visually spot it
- **Split volley** — simultaneous volleys from opposite sides of Earth
- **Formation variants** — tight cluster, straight line (wall of rocks), semicircle (arc bowing toward Earth); randomized per spawn
- **Boss patterns** — fastball, double_fastball, clump_4, clump_4_plus_fastball, clump_6, split_volley, finale; clump bosses random-formation each spawn
- **30-stage difficulty ramp** — primary levers scale slowly; one new mechanic per stage; all in play by S20

---

## SESSION — 2026-06-09 (Opus 4.7, Dweezil) — Diagnostics, sleepers, stage-end gating, polish

Built on top of HK's heavy additions (economy / station shop / settings autoload / sleeper scaffolding / volley rhythm).

### Stage-end "magical message" bug — three causes fixed
The "Respite" message kept firing while collision-course rocks were still inbound. All three contributing causes addressed:
- `_any_rocks_threatening_earth()` now counts every rock with `has_impact_fate`, not just `is_threat` rocks. Random nuisance spawns that happen to be aimed at Earth now block respite the same as deliberate threats.
- Regular `_on_Asteroid_Spawn_Timer_timeout` halts the moment `_boss_started == true`. Was leaking new collision-course rocks during the boss + clear-wait window.
- `WHOLE_CLEAR_TIMEOUT` fallback (25s) removed entirely. Respite now waits strictly until the field is clear — the player is responsible for shooting down nuisance threats too.

### Casualty Report (Pause menu)
Every Earth impact appends to `Asteroid_Manager._casualty_log` (capped 500): `{time_ms, size, pos, deaths, is_threat, is_sleeper, species, stage}`. Pause menu has a new **Casualty Report** button → panel with:
- Summary line: total impacts, total deaths, per-size breakdown with hit counts
- Detailed BBCode table (newest first): Time-ago / Size / Type / Stage / Location / Deaths
- Type tags: `threat` / `nuisance` / `debris` / `sleeper`
- Deaths colored by severity (≥1M red, ≥100k orange, ≥10k yellow, 0 gray)

Built specifically to debug "magical deaths" — the user wanted forensic visibility into what's contributing to the score.

### Killer report (DeathScreen)
On lethal collision, `Player._resolve_slide_collisions` builds a multi-line dump of the killer rock: species, size, mass, is_threat, root + sprite visibility, texture path, modulate, z_index, scale, position, velocity, layer/mask, impact-fate state, closing speed, raw damage. Stored on `GlobalSignals.last_killer_info`, printed to console, appended to the DeathScreen report. Diagnoses "invisible asteroid killed me" bugs.

### Sleeper rocks (Type 1 dive) — actually implemented
HK had `sleeper_chance` in STAGES but no implementation. Now:
- `Asteroid.is_sleeper` / `sleeper_active`. Inactive sleepers are stationary with `SLEEPER_TINT = Color(0.55, 0.18, 0.18)` (dark red). Activate when player closes within `SLEEPER_ACTIVATE_RADIUS = 2200`, then accelerate at `SLEEPER_CHASE_ACCEL = 600 u/s²` toward player (no max speed).
- `_spawn_sleeper()` in Asteroid_Manager: places one ~2800u from player (just outside wake radius so player can see it).
- Stage 1 is hard-coded to spawn one at t=5s so the user actually encounters them. Later stages still use `sleeper_chance` to roll random spawns mid-stage.
- Sleepers don't have `is_threat`, don't count against `max_threats`, don't appear on the minimap as Earth threats (they target the player).

### Defense turret toggle + indicator
- New `turret_toggle` input bound to **R**.
- `DefenseLaserTurret.enabled` flag; `toggle()` flips it. When disabled: no targeting, no firing, beam cleared.
- Persistent **triangle indicator** rendered at the turret position on the ship — green when ON, red when OFF. Always visible (separate from the firing-beam flash).
- New `turret_state_changed(enabled: bool)` signal.
- Independent **TURRET: ON/OFF** label in the GUI, top-right corner, color-tracked. Does NOT use `status_message` (that channel belongs to stage text only — user explicitly didn't want them mixed).

### Polish
- **Beam brightness**: width 8, modulate 2.4× white on top of HK's additive blend material.
- **Flame brightness**: warm modulate boost (1.9R 1.5G 1.0B) on additive.
- **Dust starts tiny universally**: `start_scale_max` 0.20 → 0.08. "Mega" clouds are mega only because of long lifetime + fast expansion, not because they spawn big. The user explicitly called out that big-from-spawn defeated the point of the system.

### Behavioral note: rock dies at the impact point
`_on_earth_impact` snaps `asteroid.global_position = asteroid.impact_point` before triggering the explosion and integrity = -1. The rock no longer overshoots; explosion + disappearance occur at the precomputed impact point.

### Known follow-ups still open
- **Real 3D explosion model** for `ExplosionPlaceholder.tscn` (placeholder is still a glowing sphere).
- **Population-density texture** to replace the Earth-texture land/ocean heuristic if precision is wanted.
- **Code review punch list** from previous session (cull double-return-to-pool, name-collision damage signal, SaveSystem field mismatch) — still standing.
- **Type 2 sleeper** (long-fuse timer activation that aims at Earth, counts against `max_threats`) — not built; only Type 1 dive is in.

---

## SESSION — 2026-06-08 (Opus 4.7, Dweezil) — Code review findings (no code changes)

Read-only review pass over the live codebase. No fixes applied — just a punch list for the next session. Prioritized.

### Bugs (will break things)

1. **`Asteroid_Manager.gd:692-701` — Double-return-to-pool on cull.** `_cull_distant_and_report` has no `_dying` guard. A rock culled by distance can also have a death signal pending; both paths call `remove_child` + `_return_to_pool`, corrupting `_asteroids_in_use` and producing duplicate-child errors on next reuse. Fix: skip if `c._dying` (and/or set `_dying = true` before pool return). Same hole exists if anything mutates a rock between pool entry and `reset()`.
2. **`Asteroid.gd:163-165` — Cross-pool name collision on damage signal.** `_on_player_hit_asteroid` filters the broadcast `player_hit_asteroid` signal by `name`, but Godot reuses `@Asteroid@NNN` names across pool members. A delayed shot resolution can decrement integrity on whatever rock currently holds the recycled name. Fix: pass node reference or `instance_id` through the signal instead of a string name.
3. **`SaveSystem.gd:47-54` — Save/load is broken.** `Player.save()` writes `current_health`; Player's field is `health`. The loader's `node.set(i, ...)` silently no-ops. Save button on the pause menu does nothing useful. Fix or hide it.
4. **`Mini_Map.gd:175` — Most-imminent sort comment contradicts code.** Sort runs descending by time; `_threats[-1]` ends up smallest only by accident. Pick a direction and align comment + index.
5. **`Player.gd:147` — `find_child("DefenseLaserTurret", false, false)`.** `recursive=false` silently returns null if the turret isn't a direct child. Verify against `Player.tscn`; prefer `$DefenseLaserTurret` with null check.

### Risks (likely-but-not-certain)

6. **`Asteroid.gd:171-175` — 2s grace period on every spawn** including small fragments. Slow fragments can drift through the player invisible-to-collision for 2 full seconds. Shorten for fragments (0.3-0.5s) or gate by distance from spawn point.
7. **`Asteroid_Manager.gd` — 5+ full child-iterations every physics frame.** `_count_active_asteroids`, `_cull_distant_and_report`, `_count_earth_threats`, `_any_rocks_threatening_earth`, `_check_earth_impacts` each walk `get_children()`. With pools at 200+, this is real CPU. Maintain a single `_active_asteroids: Array` updated on add/remove and compute all counts in one pass.
8. **`Player.gd:153-156` — `_update_collision_shapes` defers the disabled flag every physics frame** regardless of whether shield state changed. Cache `_was_shield_up`, only defer on transition.
9. **`Player.gd:599-600` — `die()` queue_frees Player while `_defense_turret` (and possibly others) hold refs.** Autoload signal disconnects handle most cases, but null `_defense_turret` before free or have the turret survive the player explicitly.

### Cleanups (delete code)

10. `Asteroid_Manager.gd:633-635` — identical `if free_node:` branches; collapse to single `excess.queue_free()`.
11. `Asteroid_Manager.gd:206, 921-922` — `_boss_queue_empty_at` written, never read.
12. `Main.tscn` `Stage_Timer` node + no-op handler — vestigial (already flagged in prior handoff).
13. `Player.gd` — `died` signal has zero listeners; only `GlobalSignals.player_died` is used. Drop one.
14. `UI/GUI.gd:419-425` — `_set_panel_passthrough` ignores its `_passthrough` arg.
15. `Mini_Map.gd:75-76` — typo `top_levewwl` + dead comment.
16. `PauseScreen.tscn` / `PauseScreen.gd`, possibly `GameOverScreen.gd` / `MainMenuScreen.gd` — vestigial; verify no imports, delete.

### Recommended first-pass order
#1, #2, #3, then #7 (perf), then #6 (fragment grace).

---

## SESSION — 2026-06-08 (Sonnet 4.6) — Difficulty ramp, HUD edit mode, fragment bounce, misc

### Threat ramp system (Asteroid_Manager.gd + Asteroid.gd)
Core design: Earth-aimed threat rocks are tightly capped per stage and fire as full volleys. Nuisance rocks are just obstacles — they do not count against the cap.

- **`max_threats` per stage** (2→3→4→5→6→7): the maximum number of `is_threat`-tagged rocks that may be in flight simultaneously. Live in `STAGES` alongside duration/boss/credits.
- **`sleeper_chance` per stage** (0→0→0→0.05→0.15→0.25): placeholder for future Type 1 sleeper rock spawn probability. Scales independently of the Earth-threat cap; sleepers are harassment, not threats.
- **`is_threat` flag on `Asteroid`**: set by `_spawn_threat_rock`, cleared on `reset()`. Only rocks with this flag count toward `max_threats`. Nuisance rocks that drift toward Earth are ignored by the cap — they still impact Earth and kill people, they just don't gate the volley timing.
- **Volley rhythm**: all threat rocks (scheduled + boss pattern) now go into `_threat_backlog` instead of spawning directly. `_drain_threat_backlog()` holds until `_count_earth_threats() == 0`, then fires up to `max_threats` at once. Creates a clear wave rhythm: player clears the field → pause → volley → repeat.
- **Boss patterns resized**: clump counts shrunk to match stage caps (`clump_6→clump_4` for stage 3, etc.). A clump larger than the cap would just spill into a second volley automatically.
- **`_count_earth_threats()`** is now a simple `is_threat` tag scan — no proximity math. Fast, accurate, immune to nuisance rock drift.
- **Respite gate** waits for both `_threat_backlog` AND `_spawn_queue` to drain before starting the clear timer. Prevents race condition where boss rocks queued but not yet spawned would let the stage end immediately.

### HUD edit mode (UI/GUI.gd, UI/GUI.tscn, UI/PauseMenu.gd/.tscn, globals/Settings.gd)
Full Farwend-style drag/resize system for HUD panels.
- StatsPanel (health/shield/energy bars) and MinimapPanel are free-floating CanvasLayer children at absolute positions, registered as editable panels.
- Edit mode pauses the game (`get_tree().paused = true`); exiting unpauses. GUI has `PROCESS_MODE_ALWAYS` so it keeps running while paused.
- Corner handles, dimension labels, snap-to-grid, show-grid toggle, reset-to-default — all ported from Farwend.
- Layout saved/restored via `Settings.hud_layout` (normalized `v:3` format).
- Minimap syncs `display_radius_px` and `_conversion` to its panel size every frame so it scales with the panel.
- PauseMenu Settings panel gained: Edit HUD Layout button, Snap to Grid toggle, Show Grid toggle, Reset HUD Layout button.
- `Settings.gd` gained: `ui_edit_mode`, `ui_snap_enabled`, `ui_snap_size`, `ui_show_grid`, `hud_layout` — saved under `[hud]` config section.

### Fragment shield bounce (actors/Player/Player.gd)
Size-1 rocks hitting an active shield have a 60% chance to bounce off instead of being pulverized. Applies between the soft-bounce and hard-impact paths in `_resolve_slide_collisions`.

### Pending: Sleeper rocks
Two types designed but not yet implemented:
- **Type 1 (Dive)**: looks like a normal rock; activates on player proximity, beam near-miss, attack, or random chance. Tries to physically collide with the player. Does NOT count against `max_threats`. Spawn probability governed by `sleeper_chance` in STAGES.
- **Type 2 (Sleeper threat)**: activates after a random timer; aims for Earth. DOES count against `max_threats`. Both types require a PID controller for Newtonian navigation once activated.

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
