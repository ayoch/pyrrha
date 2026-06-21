# Dialog System
## Design + Implementation — Pyrrha

**Status:** Built 2026-06-21. Framework complete and wired end-to-end; content is placeholder and meant to be rewritten.

---

## What it is

In-game dialog driven by two cooperating systems:

- **Reactive** — automatic responses to game situations (a rock locks onto Earth, the shield drops, an impact lands, a boss begins). Each situation has several hand-written variants; the system plays a random one and won't repeat a variant until the whole set has been used. Low priority.
- **Story** — scripted campaign beats that must be said on specific missions. Keyed by stage and a cue (start / boss / respite), played in order, never dropped. High priority. Replays on a fresh run.

The two coexist through **priority**: a story line always shows before reactive chatter and will preempt a reactive line that is currently on screen. Reactive lines that can't get screen time before they go stale are dropped, so the player never gets a combat callout five seconds too late, while story lines wait their turn and are guaranteed to play.

---

## File map

| File | Role |
|---|---|
| `globals/DialogContent.gd` | **The content. Edit this.** All reactive variants and story beats as plain data (`class_name DialogContent`, const dictionaries). |
| `globals/DialogDirector.gd` | Autoload. Listens to game signals, decides what to say (shuffle-bag for reactive, cue release for story), emits `dialog_message`. The brain. |
| `UI/DialogBox.gd` | Autoload-free view (instanced in `Main.tscn`). A priority queue + timed display. Knows nothing about the game — just shows what it's told. |
| `globals/GlobalSignals.gd` | Declares `dialog_message` and the game-event signals the Director listens to. |

Flow: **game event → GlobalSignals signal → DialogDirector → `dialog_message` → DialogBox**.

---

## Authoring content (the common task)

### Add or edit a reactive line
In `DialogContent.REACTIVE`, each situation looks like:

```gdscript
"shield_down": {
    "speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 10.0,
    "variants": [
        "Shield's gone. You're bare metal now.",
        "No more shield — every hit is hull from here.",
    ],
},
```

- `cooldown` (seconds) throttles how often the situation may fire — anti-spam for things that can trigger rapidly (e.g. `inbound_earth`).
- Add as many `variants` as you like. The shuffle bag guarantees all are used before any repeats, and avoids repeating the last one shown.

Current situations: `inbound_earth`, `impact_minor`, `impact_catastrophic`, `shield_down`, `low_hull`, `boss_incoming`, `respite`, `victory`, `defeat`.

### Add or edit a story beat
In `DialogContent.STORY`, keyed by **stage index (0-based — stage 1 is `0`)**:

```gdscript
19: [  # stage 20, the finale
    { "id": "finale_open", "cue": "start", "speaker": "Kaowitz", "icon": "kaowitz",
      "text": "This is the one we've been counting down to." },
    { "id": "finale_boss", "cue": "boss", "speaker": "Kaowitz", "icon": "kaowitz",
      "text": "Everything it has, all at once." },
],
```

- `cue` is when in the stage it fires: `"start"`, `"boss"`, or `"respite"`.
- `id` must be unique within its stage+cue; it's how the system remembers a beat was already played.
- Multiple beats with the same cue play in listed order.

---

## How triggering works

The Director connects to these signals in `_ready()` and maps them to dialog:

| Signal (GlobalSignals) | Emitted from | Drives |
|---|---|---|
| `stage_started(idx)` | `Asteroid_Manager._start_stage` | story `start` cue; resets run state when `idx == 0` |
| `boss_started(idx, pattern)` | `Asteroid_Manager._tick_threats` | story `boss` cue + reactive `boss_incoming` |
| `respite_started(idx)` | `Asteroid_Manager._begin_respite` | story `respite` cue + reactive `respite` |
| `earth_impact(deaths, size, idx, was_threat)` | `Asteroid_Manager._on_earth_impact` | reactive `impact_minor` / `impact_catastrophic` |
| `threat_inbound(size)` | `Asteroid_Manager` (when a rock acquires Earth-impact fate) | reactive `inbound_earth` |
| `player_health_changed` / `player_shield_changed` | `Player` (damage paths) | reactive `low_hull` / `shield_down` (latched with hysteresis) |
| `player_exists` | `Player._ready` | seeds true `max_health` for the low-hull fraction |
| `game_won` / `player_died` | `Asteroid_Manager` / `Player` | reactive `victory` / `defeat` |

### Adding a new trigger
1. Declare a signal in `GlobalSignals.gd` (if no existing one fits).
2. `emit` it from the relevant game code.
3. Connect it in `DialogDirector._ready()` and call `_fire_reactive("your_situation")` or `_release_story(idx, "your_cue")` in the handler.
4. Add the matching content in `DialogContent.gd`.

---

## The priority model (how the two systems interact)

- `PRIORITY_STORY = 10`, `PRIORITY_REACTIVE = 0` (in `DialogDirector`); `DialogBox.STORY_PRIORITY_MIN = 10`.
- DialogBox keeps a priority-sorted queue (priority desc, then FIFO). The front is always the most important, oldest line.
- A higher-priority arrival **preempts** the current line (drops it, shows the new one). In practice: story interrupts reactive; reactive never interrupts story.
- Each message carries a **ttl**. Reactive lines use `REACTIVE_TTL = 5s`; if they can't be shown in that window (because story is hogging the box), they're dropped as stale. Story lines pass `ttl = -1` (never expire) so they always eventually play.
- The player's **enable toggle** (`GlobalSignals.dialog_enabled`, set in the pause menu) silences reactive chatter but never story — disabling dialog won't make you miss the campaign.
- DialogBox runs with `PROCESS_MODE_ALWAYS`, so dialog keeps advancing during respite / station (when the tree is paused).

Display duration is `GlobalSignals.dialog_dismiss_sec` (pause-menu fast/normal/slow = 4/7/12s).

---

## Portraits

Drop PNGs in `UI/portraits/` and register them in `DialogBox.PORTRAITS` keyed by `icon_key` (e.g. `"kaowitz"`). A missing key just hides the portrait and shows text only — safe. (Use the existing commented `preload` line as the template; a `preload` of a missing path is a hard error, so only add a key once the file exists.)

---

## Known limitations / follow-ups

- **No click-to-advance / skip.** Auto-advance only. Fine for an action game; a skip key could be added to `DialogBox._process` (advance on input).
- **Dialog settings aren't persisted.** `dialog_enabled` / `dialog_dismiss_sec` live on `GlobalSignals` and reset each launch. Wire into the `Settings` autoload if persistence is wanted.
- **Pause-menu vs. respite.** `PROCESS_MODE_ALWAYS` means the dismiss timer also ticks while the Escape pause menu is open. Acceptable; refine if it bothers.
- **Content is placeholder.** Every line in `DialogContent.gd` is a stand-in. The cast is currently just "Kaowitz" with no portrait.
