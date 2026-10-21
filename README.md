# Fantasy Gaterunner

A portrait, one-thumb fantasy gate runner for Android (iOS-ready), built in **Godot 4.7** with GDScript.
The hero auto-runs, you drag to steer, gates rewrite your build, and every level ends in a boss.
Levels are procedurally generated from data. Level N is the same for every player.

> Status: **Milestone 6: economy, shop, saves, UI, tutorial** (coins, five upgrades with soft caps, milestone rewards, versioned saves, all menus, endless level map, first-run tutorial). Milestones 1-5 are done.

## Running

1. Install Godot **4.7.x stable** (standard build, not .NET).
2. Open `project.godot` in the editor and press **F5**. The game starts at the main menu; the
   desktop window is 540×960 (portrait). PLAY opens the level map.
3. Steer by **dragging with the mouse** (it's emulated as touch) or with **A/D / ←/→**.
4. In dev builds a purple **DBG** button opens the dev menu: jump to any level, play any seed, god mode,
   grant coins, generator overlay, and stats for the current plan. Level 0 is the hand-made test level.

Command-line flags go after `--`: `--level=N`, `--seed=S`, `--start=M` (start M meters in; `-1` = just before
the boss), `--autopilot`, `--overlay`, `--god`, `--open-debug`, `--save-dir=user://somewhere` (use a separate
save, e.g. for screenshots). The dev menu also has **SKIP TO BOSS**. To jump straight into a level, run the
run scene directly: `godot --path . res://core/run/run.tscn -- --level=57`. Autopilot and tool runs never
write to the player's save.

```bash
# play generated level 57 headless with the bot; prints a [run] summary line
godot --headless --path . res://core/run/run.tscn --fixed-fps 60 --quit-after 9000 -- --autopilot --level=57
```

```bash
# save system tests (isolated folder): fresh start, round trip, corrupt -> backup -> defaults, merge, migration
godot --headless --path . res://tools/save_test.tscn
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
  level_generator.gd LevelGenerator: produces LevelPlans
  save_manager.gd  SaveManager: versioned, atomic, corruption-safe save (coins, progress, upgrades...)
core/
  run/             Run scene (world, pools, update order, boss arena flow), TrackBuilder, ZoneTheme
  hero/            Hero node + HeroStats (pure build state: stats, element, ally counts)
  enemy/           Pooled Enemy node (behaviors: walker, charger, ranged, weaver, static)
  ally/            Ally node + Squad (formation, pooling, attack decisions)
  gates/           GateSet (visual + crossing), GateInfo (text/colors/classification)
  meta/            Economy: upgrade effects/costs, perks, milestone rewards, run payouts (pure)
  boss/            Boss (phases, attack choice), BossArena (lane telegraphs, waves, hit resolution)
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
  bosses.json      Bosses: tier, model, element, fight length, phases and attacks
  zones.json       Zone themes (colors, props, major boss) and remix settings
  modifiers.json   Level modifiers (fog, elites, double gates, boss enrage, cursed-only)
  upgrades.json    Shop upgrades (effects, soft caps, cost curves)
  milestones.json  Rewards every 10 levels (allies, perks, skins, coin chests) and perk effects
  skins.json       Hero cosmetics
  gates.json       Gate templates (good/bad/heal/strong/curse/summon) and pattern weights
  pacing.json      Pacing templates (ordered slot roles)
  segments/        Segment library; every JSON file here joins the pool
  levels/          Hand-made levels (test level = level 0)
ui/                HUD, shared theme, dev menu
  screens/         Main menu, mode select, endless level map, shop, settings (built in code)
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
   then a final climax-tier enemy wave before the finish, so levels always end on a fight
   (`generator.cadence`). Each gate rolls random contents (pattern `any`), so builds
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
   - enemy density per 25 m window stays under the `max_density` curve;
   - every level ends with an enemy wave before the boss arena.
8. **In-level ramp.** Early segments use part of the level's density and HP (every run starts weak).
9. **Difficulty targeting.** The estimator's median-gate-path score is steered into a band per level kind
   (`generator.target_median_score`, raised for the first 15 levels) by nudging enemy HP/damage.
10. **Winnability.** An expected-upgrade hero (`player_power`/`player_hp` curves) on the best gate path
   must keep its lowest HP point above a margin. Otherwise enemies are scaled down, and crowds are thinned too from
   the third repair on. The plan records `debug.difficulty_scale`.

The plan also carries `zone`/`zone_cycle`, `modifiers`, and a final `boss` event (see below).
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

## Bosses

Every level ends in a boss arena after the final wave. The hero stops at the arena line, the boss
fights from a dais 20 m ahead, and the level is won when the boss falls.

- **Scheduling:** a weighted *mini* boss ends every level; every 10th level gets the zone's *major* boss
  (forest: Troll King, crypt: Lich, volcano: Dragon).
- **Attacks** (`data/bosses.json`), on 4 lanes:
  - `slam`: telegraphed lanes, never all of them;
  - `sweep`: lanes hit one after another;
  - `wave`: a wall rolls toward you with a green gap;
  - `volley`: dodgeable shots;
  - `summon`: adds.
- **Phases:** each phase starts below its HP fraction. Phases with `min_level` only appear at higher
  levels; the `boss_enrage` modifier unlocks all of them and speeds attacks up.
- **HP** is derived by the generator from the builds the level hands out: the geometric mean of the
  best- and median-path DPS against the boss's element × `hp_seconds`. Good builds fight a bit under
  `hp_seconds`, and a build that hits the boss's weakness wins much faster.
- **Damage** is a fraction of the expected hero max HP for the level.

### Adding a boss

Add an entry to `data/bosses.json` (`tier`, `model`, `element` or `$A`, `hp_seconds`, `phases` with
attacks). Minis join the weighted pool automatically. For a major boss, set it as a zone's
`major_boss`. Models are code-built in `Placeholders.make_boss` (meshes named `Crystal*` glow in
the boss's element).

## Zones and modifiers

- **Zones** cycle every 10 levels: forest → crypt → volcano. After a full cycle they return remixed:
  all colors hue-shifted by `remix_hue_step` per cycle, with alternate props on odd cycles ("Whispering
  Forest II"). Add a zone to `data/zones.json` and list it in `order`.
- **Modifiers** unlock by level and are rolled per level (`balance.json -> modifiers`, `modifier_chance`
  curve; a second one is possible from level 40). They're shown in the level banner and as chips on the HUD.

| Modifier | Unlocks at | Effect |
|---|---|---|
| ELITES | 12 | Some foes ×1.8 HP, bigger, ×3 coins |
| BOSS ENRAGE | 22 | Faster attacks, every phase |
| DOUBLE GATES | 16 | Every gate effect doubled, good and bad |
| FOG | 8 | Heavy fog |
| CURSED | 30 | Every regular gate is a curse (fairness treats curses as safe there) |

To add a modifier, put an entry in `data/modifiers.json`, then handle its id where it applies:
`GateFactory` for gate changes, `LevelBuilder._instantiate` for enemies, `Run`/`Boss` for presentation
and combat, and `Estimator` if it changes difficulty.

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

## Economy and progression

- **Coins** come from kills and the boss (×`coin_multiplier` curve). A win adds a victory bonus, and
  Treasure Sense/perks multiply the total. Losses keep what you collected (`economy.loss_keep`).
- **Upgrades** (`data/upgrades.json`):
  - Arcane Power (+damage %), Vitality (+max HP %), Necromancy (start with skeletons), Treasure Sense
    (+coins %), Element Mastery (+weakness damage %).
  - Cost to buy level L+1 = `cost_base × (L+1)^cost_exp`. Past `soft_cap` each level gives `after_cap`
    instead of `per_level`.
  - The simulator's economy model checks that a typical player's upgrades track the generator's
    `player_power`/`player_hp` curves (92-98% through level 500, see docs/BALANCE.md).
- **Milestones** every 10 levels (`data/milestones.json`): Skeleton Archers (10) and Stone Golems (20)
  join the summon pool, plus perks (30, 50, 70, 90) and skins (40, 60, 80, 100). Every milestone also
  gives a coin chest, and past the list every milestone is a scaled chest.
- **Classes are data** (`data/classes.json`); skins tint the hero.

## Save system

`SaveManager` keeps everything in `user://save.json`:

- **Versioned:** a `version` field plus `_migrate()`. To change the format, bump `VERSION` and add a step.
- **Atomic:** writes go to a temp file, which is re-read and verified, then swapped in. The previous
  good save is kept as `save.bak.json`.
- **Forgiving:** a missing file starts fresh; a corrupt file falls back to the backup, then to
  defaults. Missing keys are filled and wrong types replaced (`_merge`). Unknown keys from newer
  versions are kept.
- **Contents:** coins, campaign progress, upgrades, perks, skins, settings, high scores, daily
  challenge state, stats, tutorial flag, purchases, and consent.

Covered by `tools/save_test.tscn`.

## Performance notes

- GL Compatibility renderer (widest Android support), no real-time shadows (blob shadows instead).
- Projectiles: one MultiMesh draw call, packed arrays, swap-remove pooling.
- Enemies and damage numbers are pooled. Trees are MultiMesh. Meshes/materials are shared via caches.
- Units are driven from `Run._process`, not per-node `_process`.

More sections (generator, adding content, tuning curves, building/exporting) are added as the milestones land.
