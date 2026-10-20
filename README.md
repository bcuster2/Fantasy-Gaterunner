# Fantasy Gaterunner

A portrait, one-thumb fantasy gate runner for Android (iOS-ready), built in **Godot 4.7** with GDScript.
The hero auto-runs, you drag to steer, gates rewrite your build, and every level ends in a boss.
Levels are procedurally generated from data. Level N is the same for every player.

> Status: **Milestone 2: gates and enemies** (elemental, summoning, and cursed gates; six enemy types; allies). Milestone 1 core loop is done.

## Running

1. Install Godot **4.7.x stable** (standard build, not .NET).
2. Open `project.godot` in the editor and press **F5**. The desktop window is 540×960 (portrait).
3. Steer by **dragging with the mouse** (it's emulated as touch) or with **A/D / ←/→**.

Command-line runs (useful for smoke tests):

```bash
# headless, full level, simple bot steering toward the best gate; prints a [run] summary line
godot --headless --path . --fixed-fps 60 --quit-after 3700 -- --autopilot
```

## Project structure

```
autoload/        Global singletons (registered in project.godot)
  balance.gd       Balance: every tunable number, loaded from data/balance.json
  content.gd       Content: data-driven registry (classes, enemies, levels...)
  game_state.gd    GameState: current mode/level, dev toggles (god mode, autopilot)
  audio_manager.gd AudioManager: pooled SFX players, mute buses (SFX synthesized until M8)
  level_generator.gd LevelGenerator: produces LevelPlans (M1: serves the test level)
core/
  run/             Run scene: owns world, pools, and the per-frame update order
  hero/            Hero node + HeroStats (pure build state: stats, element, ally counts)
  enemy/           Pooled Enemy node (behaviors: walker, charger, ranged, weaver, static)
  ally/            Ally node + Squad (formation, pooling, attack decisions)
  gates/           GateSet (visual + crossing), GateInfo (text/colors/classification)
  combat/          CombatMath (pure element/power rules), ProjectileSystem (friendly shots,
                   one MultiMesh), EnemyShots (hostile shots to dodge)
  fx/              CameraRig (trauma shake), DamageNumbers, BurstPool
  visuals/         Placeholders: code-built low-poly models with shared meshes/materials
  shaders/         Ground, gate, and checker shaders
  util/            JsonUtil, NodePool
gen/               Generator logic (pure, no nodes): formations now; segments/pacing in M3
data/              All content and tuning as JSON
  balance.json     The one balance/tuning file
  classes.json     Hero classes (one in v1; add more here)
  enemies.json     Enemy archetypes
  allies.json      Summonable allies
  elements.json    Elements: color, icon, weakness triangle, on-hit effect
  levels/          Hand-made levels (M1 test level)
ui/                HUD and shared theme (built in code)
tools/             Headless tools (simulator arrives in M4)
```

### LevelPlan format

The Run scene consumes a plan of events sorted by distance `d` (meters). The M3 generator emits this exact schema.

```json
{ "length": 430, "events": [
  { "d": 30, "type": "enemies", "enemy": "grunt", "formation": "block", "rows": 2, "cols": 3, "x": 0, "hp_mult": 1.5 },
  { "d": 50, "type": "gates", "gates": [ { "stat": "damage", "op": "add", "value": 3 },
                                         { "stat": "fire_rate", "op": "mul", "value": 1.5 } ] }
] }
```

Formations: `line` (count), `block` (rows, cols), `wedge` (rows), `column` (count). Optional `spacing`, `x`, `element`, `hp_mult`.

### Gate kinds

| kind | schema | color |
|---|---|---|
| `stat` (default) | `{stat, op, value}`. stat: `damage`, `fire_rate`, `projectiles`, `hp` (heal), `max_hp` | blue if good, red if harmful |
| `element` | `{kind, element}`. Sets the hero's (and allies') attack element | element color + icon |
| `summon` | `{kind, ally, count}`. Adds allies, capped at `combat.max_allies` | green |
| `curse` | `{kind, effects:[{stat, op, value}...]}`. Risk/reward; extra stats `hp_pct`, `allies_pct` | purple, "CURSED" header |

### Elements

An enemy's element sets its **weakness** (2× damage, the icon floating over its head) and its **resistance**
(0.5× from its own element). The triangle in `elements.json`: fire enemies are weak to ice, ice to lightning,
lightning to fire. Wards (`immune_unless_weak`) take damage **only** from their weakness, so they act as
element-locked walls. Each element also adds an on-hit effect: fire burns, ice slows, lightning chains.

### Enemies

| id | behavior | role |
|---|---|---|
| `grunt` | walker | baseline goblin crowd |
| `runner` | charger | fast wolves, punish late reactions |
| `brute` | walker | slow, tanky, hits hard |
| `archer` | ranged | stands still, winds up (glows), fires dodgeable bolts |
| `imp` | weaver | flies in a sine path across lanes |
| `ward` | static | element-locked wall piece |

### Adding content

- **Enemy:** add an entry to `data/enemies.json` (`behavior` picks an existing AI; `model` picks a placeholder
  builder in `core/visuals/placeholders.gd`). It's usable from any level event immediately.
- **Ally:** add an entry to `data/allies.json` (`kind` melee/ranged, `row` front/back), then use it in a summon gate.
- **Element:** add an entry to `data/elements.json` with an icon SVG in `assets/icons/`, and keep the weakness
  triangle closed.

## Performance notes

- GL Compatibility renderer (widest Android support), no real-time shadows (blob shadows instead).
- Projectiles: one MultiMesh draw call, packed arrays, swap-remove pooling.
- Enemies and damage numbers are pooled. Trees are MultiMesh. Meshes/materials are shared via caches.
- Units are driven from `Run._process`, not per-node `_process`.

More sections (generator, adding content, tuning curves, building/exporting) are added as the milestones land.
