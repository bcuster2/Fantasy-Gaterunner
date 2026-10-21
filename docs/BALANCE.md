# Balance notes

How difficulty is measured, what it is tuned to, and the results of each balance pass.
Every number referenced here lives in `data/balance.json`.

## Tools

| Tool | What it does | Time |
|---|---|---|
| `tools/simulate.tscn` | Generates levels 1-500 and runs the analytic Estimator on best, median, and casual gate paths. Writes `reports/sim_levels.csv` and `reports/sim_report.md`. | ~7 s |
| `tools/calibrate.tscn` | Plays real levels headless with the autopilot (full game simulation) and compares results to the Estimator. Writes `reports/calibration.csv`. | ~25 s for 45 levels |
| `tools/gen_check.tscn` | Checks determinism, fairness rules, and generation time for every level. `--trace=N` prints the estimator walkthrough for one level. | ~10 s |

```bash
godot --headless --path . res://tools/simulate.tscn -- --from=1 --to=500 --samples=25
```

```bash
godot --headless --path . --fixed-fps 60 res://tools/calibrate.tscn -- --levels=1,5,10,50,100
```

## Players being modeled

- **Expected hero.** Class base stats × `player_power` (damage) and `player_hp` (HP) at level N: the
  upgrade level the shop (Milestone 6) is meant to deliver. Until the shop exists, the game applies this
  automatically (`generator.debug_assume_upgrades`, also a dev-menu toggle).
- **Best path.** Always takes the highest-scoring gate (`CombatMath.gate_score`).
- **Median path.** Always takes the median-ranked gate (with 2 options, the weaker one).
- **Casual player.** Takes the best gate 65% of the time (`combat.casual_best_chance`), otherwise a
  random other one. Sampled 25 times per level to get a win rate. This is the headline metric.

## Design rule: fixed gate cadence, unplannable builds

Every level has the same build rhythm: a 40 m intro, then **6 gates exactly 58 m apart**, then a
pre-boss gate, then a **final enemy wave** (climax-tier) and the finish (458 m, ~57 s). Levels always
end on a fight, never on a gate. Players always know when the next choice is coming.
What is offered is never planned: every gate rolls its contents (stat, element, summon, curse, heal,
or harmful) from `gates.json`, so builds come from adapting to the choices that turn up and each
level plays differently. Pacing templates only decide what you fight between gates.
(`balance.json -> generator.cadence`)

## How difficulty is set

1. **Curves** set the baseline per level: `enemy_hp`, `enemy_damage`, `density`, `bad_gate_chance`,
   `coin_multiplier`, `max_density` (readability cap).
2. **In-level ramp.** Every run starts with a fresh hero, so early segments use 20% of the level's
   extra density and 75% of its HP, reaching 100% by 60% of the level
   (`generator.density_ramp_start / hp_ramp_start / ramp_full_at`).
3. **Targeting.** The generator nudges each level's enemy HP/damage (×0.9 down, ×1.1 up, max ×1.6) until
   the median-path score lands in `generator.target_median_score[kind]`. Score = distance fraction
   reached if the median path dies, or 1 + remaining HP fraction if it survives. This evens out
   segment and gate luck and keeps the rhythm readable. Making a level harder (targeting up, or the
   spike multiplier) mostly toughens the back half, where gate-built power lives. The opening gets
   only `factor^0.25` (`upscale_opening_weight`). Onboarding aims higher for the first 20 levels, and
   through level 15 the median path must finish.
4. **Guarantee.** The best path's *lowest* HP point during the run must stay above a margin (15%,
   or 12% on spike/boss levels). Checking only final HP missed runs that recover through max-HP gates.
   Otherwise enemies are scaled down, and crowds are thinned after the second round.

## Pass 4: economy (Milestone 6, current)

The shop now provides the progression the generator assumes, so the expected-player curves were fitted
to an achievable economy. Because difficulty targeting normalizes enemies to whatever player curve is
set, the enemy curves were flattened to match:

- `player_power`: linear 0.05, exponent 1.1 → **0.85** (×10.8 damage at level 500 instead of ×47).
  `player_hp` linear 0.02 → **0.008**.
- `enemy_hp`: base 1.2 → **1.0**, exponent 1.12 → **0.87**. `enemy_damage` linear 0.02 → **0.008**.
- Coins: victory bonus 25 × coin curve; losses keep collected coins.
- Upgrade costs: `cost_base × (L+1)^1.25` for damage/HP (soft cap 60: +10% → +7.5% damage, +5% → +2% HP).

**Economy model** (in the simulator): a typical player retries until each win, banks coins, and buys
upgrades to stay near the curves.

| level | expected power | shop power | ratio | expected HP | shop HP |
|---|---|---|---|---|---|
| 1 | 1.00 | 1.10 | 1.10 | 1.00 | 1.05 |
| 50 | 2.37 | 2.30 | 0.97 | 1.39 | 1.50 |
| 100 | 3.48 | 3.40 | 0.98 | 1.79 | 1.90 |
| 250 | 6.44 | 6.10 | 0.95 | 2.99 | 3.15 |
| 500 | 10.83 | 9.93 | 0.92 | 4.99 | 4.64 |

Win rates after re-tuning: normal 83%, spike 69%, reward 92%, boss 74%; no broken levels.
Calibration: 23/23 live levels won, and the estimator agreed on every outcome.

## Pass 3: bosses, modifiers, zones (Milestone 5)

Every level now ends in a boss fight (mini every level, major every 10th), and modifiers roll from level 8.

- **Boss sizing:** HP = geometric mean of best- and median-path end DPS vs. the boss element × `hp_seconds`
  (mini 8-10 s, major 18-20 s). Difficulty targeting and repairs scale the boss with the rest of the level.
- **Boss model in the estimator:** fight length = HP / DPS (adds cost 15% DPS); damage = telegraphed hits ×
  hit rate (best 20%, median 35%, casual 30%). Dying to the boss scores 0.85 + 0.15 × the fraction of the
  fight survived, so targeting can tell "died at the boss" from "finished".
- **Fixes found by the simulator:** the low-HP danger check is now relative to max HP (30%); shrinking max
  HP keeps the HP fraction instead of subtracting; cursed-only levels get two HP-friendly curses (Iron
  Will, Bone Tithe).
- `target_median_score` normal and boss `[0.70, 1.00]`; `enemy_hp.linear` 0.031.

| Kind | Levels | Mean casual win | Std dev |
|---|---|---|---|
| normal | 344 | 83% | 0.17 |
| spike | 49 | 68% | 0.23 |
| boss (incl. major boss) | 50 | 72% | 0.22 |
| reward | 57 | 93% | 0.12 |

No BROKEN levels (best path always wins). **Calibration:** 54/54 sampled levels (1-500, including
cursed-only level 42) won live with the autopilot dodging telegraphs; the estimator agreed on every outcome
and stays conservative (−12.6% HP). Generation: ~6.6 ms average, max ~15-19 ms (boss sizing adds runs).

## Pass 2b: final enemy wave

Each level now ends with a climax-tier wave after the pre-boss gate (`generator.cadence.finale_length`).
Fairness rule 4: every level ends with an enemy wave. Calibration found two estimator gaps, now fixed:

- Multishot volleys overlap on targets: projectile count counts as `projectiles^0.85`
  (`estimator.multishot_exponent`).
- The winnability margin now uses the closest call (lowest HP), not the HP left at the finish.
- Spike/boss margin 5% -> 12%; `max_upscale` 1.6 -> 1.5.

| Kind | Levels | Mean casual win | Std dev |
|---|---|---|---|
| normal | 344 | 80% | 0.19 |
| spike | 49 | 68% | 0.23 |
| boss (run part) | 50 | 80% | 0.19 |
| reward | 57 | 95% | 0.09 |

Levels 1-25 all >= 68% casual wins. Coins per level rose ~25% from the extra kills (~6.2k by level 50,
~333k by 500). **Calibration:** 52/52 sampled levels won live, and the estimator agreed on every outcome
(live runs end with ~11% more HP than predicted). Generation: ~4.3 ms average, p99 7.8 ms, max ~12 ms.

## Pass 2: fixed gate cadence

Every level now has 7 gates (6 + pre-boss) instead of 3-6, so players end runs much stronger. Changes:

- `enemy_hp`: base 1.0 → 1.2, linear 0.03 → 0.035. `enemy_damage`: base 1.0 → 1.15.
  `generator.max_upscale` 1.4 → 1.6.
- Spike levels start at level 10 (`rhythm.spike_min_level`); onboarding fades over 20 levels.
- Estimator back to conservative (`hero_aim` 0.75, `leak_hit_rate` 1.0). The near-unbiased setting
  let 3/51 live runs die in the opening.
- Rhythm and up-scaling weighted toward the back half of each level (see above).

| Kind | Levels | Mean casual win | Std dev |
|---|---|---|---|
| normal | 344 | 83% | 0.18 |
| spike | 49 | 64% | 0.24 |
| boss (run part) | 50 | 79% | 0.19 |
| reward | 57 | 97% | 0.06 |

| levels | casual win | best hp | median win | spike win | reward win | repair scale | run s | coins/level (casual) | cumulative coins |
|---|---|---|---|---|---|---|---|---|---|
| 1-50 | 88% | 72% | 56% | 85% | 94% | 1.05 | 55 | 82 | 5,077 |
| 51-100 | 82% | 64% | 32% | 76% | 95% | 0.95 | 55 | 164 | 15,441 |
| 101-150 | 80% | 61% | 44% | 67% | 97% | 0.95 | 55 | 231 | 30,936 |
| 151-200 | 85% | 65% | 38% | 62% | 99% | 0.93 | 55 | 318 | 50,247 |
| 201-250 | 84% | 67% | 30% | 57% | 99% | 0.97 | 55 | 369 | 73,163 |
| 251-300 | 81% | 71% | 24% | 66% | 100% | 0.88 | 55 | 440 | 102,080 |
| 301-350 | 82% | 66% | 36% | 49% | 96% | 0.93 | 55 | 531 | 135,976 |
| 351-400 | 82% | 62% | 42% | 75% | 96% | 0.86 | 55 | 614 | 174,214 |
| 401-450 | 81% | 65% | 36% | 64% | 97% | 0.95 | 55 | 648 | 216,026 |
| 451-500 | 77% | 60% | 36% | 44% | 95% | 0.84 | 55 | 720 | 266,319 |

Levels 1-25 all have a casual win rate of 72% or higher. **Calibration:** 51/51 sampled levels (1-500)
won live with the autopilot; the estimator agreed on every outcome and stays conservative (live runs
end with ~8.5% more HP than predicted).

**Watch list:** late spike levels (300-500) dip to 44-49% casual wins; revisit after bosses and
modifiers land. A ~0.9 repair scale late means the curves slightly outpace the expected player there.

## Pass 1 (Milestone 4) results (superseded)

Targets (casual win rate): normal ~80%, spike ~65%, boss run ~75% (the boss fight adds its own
challenge in Milestone 5), reward ~90%+, early levels ~90%+.

| Kind | Levels | Mean casual win | Std dev |
|---|---|---|---|
| normal | 343 | 81% | 0.18 |
| spike | 50 | 68% | 0.23 |
| boss (run part) | 50 | 73% | 0.23 |
| reward | 57 | 93% | 0.13 |

| levels | casual win | best hp | median win | spike win | reward win | repair scale | run s | coins/level (casual) | cumulative coins |
|---|---|---|---|---|---|---|---|---|---|
| 1-50 | 80% | 58% | 36% | 70% | 100% | 1.06 | 53 | 80 | 5,472 |
| 51-100 | 83% | 64% | 48% | 75% | 98% | 0.96 | 55 | 163 | 16,384 |
| 101-150 | 80% | 66% | 38% | 69% | 95% | 0.97 | 55 | 252 | 33,208 |
| 151-200 | 78% | 58% | 34% | 62% | 88% | 0.96 | 56 | 318 | 55,254 |
| 201-250 | 82% | 57% | 38% | 62% | 97% | 0.91 | 57 | 419 | 81,863 |
| 251-300 | 82% | 57% | 44% | 67% | 99% | 1.00 | 55 | 475 | 112,197 |
| 301-350 | 82% | 67% | 46% | 61% | 89% | 0.96 | 54 | 557 | 147,894 |
| 351-400 | 75% | 66% | 26% | 63% | 81% | 1.00 | 54 | 605 | 191,638 |
| 401-450 | 79% | 61% | 38% | 85% | 97% | 1.01 | 56 | 700 | 240,861 |
| 451-500 | 80% | 60% | 30% | 70% | 87% | 0.90 | 56 | 766 | 292,361 |

Difficulty stays flat across 500 levels instead of drifting, and a repair scale near 1.0 means the
curves match the expected player.

### Calibration (live autopilot vs Estimator, 45 levels from 1 to 500)

- 45/45 levels won live; the Estimator agreed on every outcome (no false wins).
- The Estimator is deliberately **conservative**: live runs finish with about 21% more HP than
  predicted and kill about 7% more. The autopilot never dodges shots, so a careful human does better still.
- `estimator.hero_aim = 0.8`, `estimator.leak_hit_rate = 0.85`. Making the model more optimistic
  produced false wins (levels the live bot lost), so it stays on the safe side.

### Changes made in this pass

- `enemy_hp.linear` 0.06 → 0.03 and `enemy_damage.linear` 0.025 → 0.02. The old curves outpaced the
  expected player, forcing heavy repairs that flattened the spike/reward rhythm.
- Added the in-level density/HP ramp. High levels used to open with crowds a 1-shot hero can't
  physically clear (level 55 died 70 m in).
- Replaced one-sided repair with two-sided targeting on the median-path score: normal-level std dev
  fell from 0.22 to 0.18 and the rhythm became visible.
- Onboarding shift for levels 1-15. Boss levels' run portion is targeted like a normal level.
- Estimator fixes found by calibration: ally soak capped by ally HP, gap walls excluded from the
  element mix, grouped events share one time window, conservative aim/leak constants.
- Autopilot fixes: avoids wall pieces before steering to gates, breaks one piece of a full wall.

### Known issues / next passes

- About 18% of normal levels still read HARD or EASY for the casual model, mostly from gate luck
  (element choices). Revisit after bosses and modifiers land (Milestone 5).
- **Economy hook (Milestone 6):** shop upgrade costs must let a player who wins about 80% of the
  time reach `player_power(N)` from the casual coins column. Cumulative casual coins: ~5.5k by
  level 50, ~33k by 150, ~292k by 500 (before coin upgrades).
- Generation is 3 ms average and 6.5 ms max on desktop. Profile on a mid-range phone in Milestone 10:
  budget 50 ms, and `generator.max_tune_steps` is the lever if needed.
