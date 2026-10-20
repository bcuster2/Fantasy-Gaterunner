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

## How difficulty is set

1. **Curves** set the baseline per level: `enemy_hp`, `enemy_damage`, `density`, `bad_gate_chance`,
   `coin_multiplier`, `max_density` (readability cap).
2. **In-level ramp.** Every run starts with a fresh hero, so early segments use 20% of the level's
   extra density and 75% of its HP, reaching 100% by 60% of the level
   (`generator.density_ramp_start / hp_ramp_start / ramp_full_at`).
3. **Targeting.** The generator nudges each level's enemy HP/damage (×0.9 down, ×1.1 up, max ×1.4) until
   the median-path score lands in `generator.target_median_score[kind]`. Score = distance fraction
   reached if the median path dies, or 1 + remaining HP fraction if it survives. This evens out
   segment and gate luck and keeps the rhythm readable. The first 15 levels aim higher (onboarding).
4. **Guarantee.** The best path must survive with HP to spare (15%, or 5% on spike/boss levels).
   Otherwise enemies are scaled down, and crowds are thinned after the second round.

## Pass 1 (Milestone 4) results

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
