# Fantasy Gaterunner

A portrait, one-thumb fantasy gate runner for Android (iOS-ready), built in **Godot 4.7** with GDScript.
The hero auto-runs, you drag to steer, gates rewrite your build, and every level ends in a boss.
Levels are procedurally generated from data. Level N is the same for every player.

> Status: **Milestone 1: core loop** (running, steering, auto-attack, one enemy, stat gates, hand-made test level).

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
  hero/            Hero node + HeroStats (pure stats, reused by the simulator)
  enemy/           Pooled Enemy node
  gates/           GateSet (visual + crossing), GateInfo (text/colors/scoring)
  combat/          ProjectileSystem: all projectiles as packed data in one MultiMesh
  fx/              CameraRig (trauma shake), DamageNumbers, BurstPool
  visuals/         Placeholders: code-built low-poly models with shared meshes/materials
  shaders/         Ground, gate, and checker shaders
  util/            JsonUtil, NodePool
gen/               Generator logic (pure, no nodes): formations now; segments/pacing in M3
data/              All content and tuning as JSON
  balance.json     The one balance/tuning file
  classes.json     Hero classes (one in v1; add more here)
  enemies.json     Enemy archetypes
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

Formations: `line` (count), `block` (rows, cols), `wedge` (rows), `column` (count). Optional `spacing`, `x`.
Gate stats: `damage`, `fire_rate`, `projectiles`. Ops: `add`, `mul`. Negative/below-1 values are harmful gates (red).

## Performance notes

- GL Compatibility renderer (widest Android support), no real-time shadows (blob shadows instead).
- Projectiles: one MultiMesh draw call, packed arrays, swap-remove pooling.
- Enemies and damage numbers are pooled. Trees are MultiMesh. Meshes/materials are shared via caches.
- Units are driven from `Run._process`, not per-node `_process`.

More sections (generator, adding content, tuning curves, building/exporting) are added as the milestones land.
