# Fantasy Gaterunner

A portrait, one-thumb fantasy gate runner for Android (iOS-ready), built in **Godot 4.7** with GDScript.
The hero auto-runs, you drag to steer, gates rewrite your build, and every level ends in a boss.
Levels are procedurally generated from data. Level N is the same for every player.

> Status: **Milestone 4: simulator and first balance pass** (levels 1-500 validated; see [docs/BALANCE.md](docs/BALANCE.md)). Milestones 1-3 are done.

## Running

1. Install Godot **4.7.x stable** (standard build, not .NET).
2. Open `project.godot` in the editor and press **F5**. The desktop window is 540×960 (portrait).
3. Steer by **dragging with the mouse** (it's emulated as touch) or with **A/D / ←/→**.
4. In dev builds a purple **DBG** button opens the dev menu: jump to any level, play any seed, god mode,
   grant coins, generator overlay, and stats for the current plan. Level 0 is the hand-made test level.

Command-line flags go after `--`: `--level=N`, `--seed=S`, `--autopilot`, `--overlay`, `--god`, `--open-debug`.

```bash
# play generated level 57 headless with the bot; prints a [run] summary line
godot --headless --path . --fixed-fps 60 --quit-after 9000 -- --autopilot --level=57
```

```bash
# generator check: determinism, fairness rules, and timing for levels 1-500 (writes reports/gen_check.csv)
godot --headless --path . res://tools/gen_check.tscn -- --levels=500
```

```bash
# estimator walkthrough of one level: gate picks and HP after each enemy group
godot --headless --path . res://tools/gen_check.tscn -- --trace=57
```

```bash
# level simulator: best / median / casual gate paths for levels 1-500 -> reports/sim_levels.csv + sim_report.md
godot --headless --path . res://tools/simulate.tscn -- --from=1 --to=500 --samples=25
```

```bash
# calibration: real autopilot playthroughs vs the estimator -> reports/calibration.csv
godot --headless --path . --fixed-fps 60 res://tools/calibrate.tscn -- --levels=1,10,50,100,250,500
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
gen/               Procedural generator (pure functions, no nodes or autoloads)
  level_builder.gd   Seeded assembly: template -> segments -> events -> fairness -> winnability
  gate_factory.gd    Turns gate patterns into concrete, level-scaled gates
  fairness.gd        Fairness repairs and validation
  estimator.gd       Analytic run model (winnability check; basis of the M4 simulator)
  curves.gd          Difficulty curves and spike/reward/boss rhythm
  level_seed.gd      Stable FNV-1a seeds (level N is identical for every player)
  content_db.gd      Loads all content tables (shared by game and tools)
  formations.gd      Formation layouts
data/              All content and tuning as JSON
  balance.json     The one balance/tuning file
  classes.json     Hero classes (one in v1; add more here)
  enemies.json     Enemy archetypes
  allies.json      Summonable allies
  elements.json    Elements: color, icon, weakness triangle, on-hit effect
  gates.json       Gate templates (good/bad/heal/strong/curse/summon) and pattern weights
  pacing.json      Pacing templates (ordered slot roles)
  segments/        Segment library; every JSON file here joins the pool
  levels/          Hand-made levels (test level = level 0)
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

## How the generator works

`LevelGenerator.get_plan(level)` calls `LevelBuilder.build(level, LevelSeed.for_level(level), ...)`:

1. **Seed.** `fnv1a("gaterunner/level/N")` feeds a `RandomNumberGenerator` (PCG32). Our own hash means
   level N never changes across engine versions or devices. Content pools are sorted by id so file
   order can't change results either. A debug seed can replace the canonical one while keeping
   level N's difficulty.
2. **Rhythm.** `Curves.level_kind`: every 10th level is a **boss** level, every 5th a **spike** (harder,
   breather becomes pressure), and levels where `N % 7 == 3` are **reward** levels (easier, extra coins).
3. **Fixed gate cadence.** Every level: a 40 m intro, 6 gates exactly 58 m apart, a pre-boss gate,
   and the finish (`generator.cadence`). Each gate rolls random contents (pattern `any`), so builds
   can't be planned; players adapt to what turns up.
4. **Pacing template.** A weighted pick from `pacing.json` (unlocked by level) decides only what you
   fight between gates: one role per stretch, e.g. `buildup, pressure, breather, pressure, pressure, climax`.
5. **Segments.** Each stretch draws a weighted segment whose `roles` include it and that fits the
   stretch (with fallbacks, no back-to-back repeats). Segments may be mirrored. Count fields given as
   `[min,max]` grow with the density curve. Element tokens resolve from the level's 2-element palette:
   `$A`, `$B`, `$mix`, `$wall`.
6. **Scaling.** Enemy `hp_mult`/`dmg_mult` come from the `enemy_hp`/`enemy_damage` curves × rhythm. Gate
   values come from templates, with additive values scaled by `player_power`/`player_hp`.
7. **Fairness** (`gen/fairness.gd`):
   - every gate set has a safe option (never two harmful gates as the only choice);
   - every element-locked wall's preceding gate set offers its weakness (or one is inserted);
   - enemy density per 25 m window stays under the `max_density` curve.
8. **In-level ramp.** Early segments use part of the level's density and HP (every run starts weak).
9. **Difficulty targeting.** The estimator's median-gate-path score is steered into a band per level kind
   (`generator.target_median_score`, raised for the first 15 levels) by nudging enemy HP/damage.
10. **Winnability.** An expected-upgrade hero (`player_power`/`player_hp` curves) on the best gate path
   must survive with an HP margin. Otherwise enemies are scaled down, and crowds are thinned too from
   the third repair on. The plan records `debug.difficulty_scale`.

The plan also carries `zone`, `boss`, and `modifiers` for Milestone 5.
Generation takes about 2 ms per level (budget 50 ms).

### Adding a segment

Drop it into any file in `data/segments/` (or a new file there):

```json
{ "id": "goblin_block", "roles": ["buildup", "pressure"], "min_level": 1, "weight": 3, "length": 32,
  "events": [ { "d": 6, "type": "enemies", "enemy": "grunt", "formation": "block",
                "rows": [2, 3], "cols": [3, 4], "element": "$A", "hp": 1.0 } ] }
```

Segments hold enemies only; gates come from the cadence. A segment's `length` must fit a stretch
(intro: 34 m, between gates: 40 m, +4 m tolerance); events past the stretch are dropped. Set
`"mirror": false` for asymmetric segments that must not flip. Run `tools/gen_check.tscn` afterwards
to confirm fairness and determinism.

### Adding a gate or pacing template

- **Gate:** add a template to the right pool in `data/gates.json` (`value` is a number or `[min,max]`;
  `scale: "power"` makes it grow with level; `min_level` controls when it unlocks).
- **Pacing:** add an entry to `data/pacing.json` with `intro`, `intervals` (one role per gate), `weight`, `min_level`.
- **Gate rhythm:** `balance.json -> generator.cadence` (intro length, interval, gate count).
- **Modifiers:** arrive in Milestone 5 (`plan.modifiers`).

### Tuning curves

All curves live in `balance.json -> curves`, as `value = base * (1 + linear * (N-1)^exponent)` with an
optional `cap`. The `rhythm` section sets the spike/reward/boss cadence. The `generator` section holds
fairness margins and repair strength, and `estimator` holds the analytic model's assumptions. After
changing anything:

1. Run `tools/simulate.tscn` and read `reports/sim_report.md`: casual win rate per 50-level band, spike
   and reward rhythm, coins, and flagged levels (BROKEN / HARD / EASY / REPAIRED / SHORT / LONG).
2. An average `repair scale` near 1.0 means the curves fit the expected player; well below 1.0 means
   enemies outpace upgrades.
3. Run `tools/calibrate.tscn` occasionally to confirm the estimator still matches real playthroughs.

See [docs/BALANCE.md](docs/BALANCE.md) for the targets and the pass-1 results.

## Performance notes

- GL Compatibility renderer (widest Android support), no real-time shadows (blob shadows instead).
- Projectiles: one MultiMesh draw call, packed arrays, swap-remove pooling.
- Enemies and damage numbers are pooled. Trees are MultiMesh. Meshes/materials are shared via caches.
- Units are driven from `Run._process`, not per-node `_process`.

More sections (generator, adding content, tuning curves, building/exporting) are added as the milestones land.
