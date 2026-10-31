# Aim Targets for UT2004

An **offline aim and movement trainer** for Unreal Tournament 2004, built as two
mutators. No bots: you shoot floating spheres with the **Shock Rifle** (beam and
combo) and the **Lightning Gun**, while the game rewards you for moving, for
precision and for distance, adapts its difficulty to you, and tells you whether
you are actually getting better.

| Mutator | What it does |
|---|---|
| **Aim Targets** | The trainer: rounds, targets, scoring, adaptive difficulty, records, progress history |
| **Damage Numbers** | Fortnite-style pop-up numbers with the damage you deal. Works on its own in any offline match, and Aim Targets uses it too |

> Designed for **offline, solo practice** against targets (no bots needed).

## Features

- **Three training modes** (plus a mixed mode that cycles through them)
  - **Flick** - static spheres in front of you; hit one and a new one appears
  - **Strafe** - spheres that strafe left and right, so you have to track and lead
  - **Sniper** - small, distant, slowly drifting spheres for the Lightning Gun
- **Rewards movement**: shots while moving, strafing or in the air are worth more
- **Rewards precision and distance**: bullseyes and far targets score more
- **Shock combos count**: pop a target with a combo for a bonus
- **Adaptive difficulty** (1 - 10): sphere size, speed and lifetime follow your accuracy
- **Standing still drains your health**, moving gives a little back
- **Hit sound** whose pitch rises with your streak
- **Damage numbers** next to the crosshair, coloured and sized by damage
- **Round summary** with personal records and a comparison with your last rounds
- **HTML progress report** with charts and a verdict (improving / stable / declining)

## Requirements

- Unreal Tournament 2004 (developed and compiled against build 3374)
- The game's own `ucc.exe` to compile (it ships with the game)

## Installation

The mods are distributed as source and compiled by the game's compiler.

1. Copy the `DamageNumbers` and `AimTargets` folders into your UT2004 folder
   (next to `System`, `Maps`, ...). Each one contains a `Classes` folder (and
   `AimTargets` also a `Sounds` folder).
2. Open `System\UT2004.ini` and add these two lines after the last
   `EditPackages=` line, **in this order**:

   ```ini
   EditPackages=DamageNumbers
   EditPackages=AimTargets
   ```

3. Delete `System\DamageNumbers.u` and `System\AimTargets.u` if they already
   exist. `ucc make` reports "Success" without rebuilding when an old `.u` is there.
4. Compile: run `ucc make` from the `System` folder (`System\ucc.exe make`).
   The log must end with `Success - 0 error(s), 0 warning(s)`.

### Helper script (WSL / Linux)

`tools/aimmods.sh` does the copy-and-compile for you. It assumes the game is in
`/mnt/c/UnrealTournament2004`; change the `UT=` line at the top if yours is elsewhere.

```
tools/aimmods.sh build     # copy the sources into the game, delete the old .u, recompile
tools/aimmods.sh disable   # take the mods out of the game folder
tools/aimmods.sh enable    # put them back
tools/aimmods.sh report    # build the progress report and open it in the browser
```

## How to play

1. *Instant Action* -> *Deathmatch*, **0 bots**, and a map with some open space.
2. In *Mutators*, enable **Aim Targets** (add **Damage Numbers** too if you want it
   in your other offline matches).
3. Start. The first round begins a few seconds after the match starts; the
   trainer removes the frag and time limit so the match never ends.
4. Type `mutate aim help` in the console for the commands.

Rounds last 60 seconds with a 20 second break (the summary stays on screen).
Every round starts with full health.

### Scoring

Every target is worth **100 points**, multiplied by:

| Bonus | Multiplier |
|---|---|
| Moving (speed >= 200) | x1.5 |
| Strafing (sideways speed >= 250) | x2 |
| In the air | x2 |
| Bullseye (close to the sphere's center) | x1.5 (x1.2 when close) |
| Shock combo | x2 |
| Distance | x1.0 up to 500 units, then +1.0 per 2000 units, capped at x3 |
| Streak of consecutive hits | +10% per hit, up to x2 |

A shot that misses breaks the streak, and so does a target that expires. The
Shock Rifle ball is not counted as a shot: it is only the setup of a combo.

### Standing still

If you stay below 100 units/s for more than a second you lose 8 health per
second, in half-second chunks, and "KEEP MOVING!" appears. Moving gives back 3
health per second. You can die. All of this is configurable (see below).

## Console commands

```
mutate aim help
mutate aim mode flick|strafe|sniper|mixed
mutate aim diff <1-10>
mutate aim targets <1-8>
mutate aim adaptive on|off
mutate aim summary          show the last round summary again
mutate aim reset            clear personal records and history
```

## Progress report

Every finished round is saved to `System\AimTargets.ini`. To see how you are
doing, run:

```
tools/aimmods.sh report
```

It writes `report/AimTargetsReport.html` (a single self-contained page, no
internet needed) and opens it. For each mode you get charts of score, accuracy,
time per target, difficulty and shots while moving, with a moving average, plus
a verdict that compares your last 5 rounds with the 5 before. Because the game
raises the difficulty when you do well, the verdict also looks at accuracy,
speed and difficulty, not only at the score. You need at least 6 rounds of a
mode before it gives a verdict.

You can also run the script directly (Python 3, no dependencies):

```
python3 tools/report.py <path-to>/System/AimTargets.ini report.html
```

## Configuration

The `AimTargets` settings are written to the `.ini` the first time a round ends.
The overlay settings (`DamageNumbers`, and the panel `TextScale`) are not written
automatically: if the file or the section is missing, create it with the lines
you want to change. Edit the files with the game closed.

`System\AimTargets.ini`, section `[AimTargets.MutAimTargets]`:

| Setting | Default | Meaning |
|---|---|---|
| `RoundDuration` | 60 | Seconds per round |
| `BreakSeconds` | 20 | Pause between rounds (the summary stays visible) |
| `SelectedMode` | 3 | 0 flick, 1 strafe, 2 sniper, 3 mixed |
| `TargetCount` | 3 | Targets at once (strafe and sniper use one less) |
| `TargetSizeScale` | 0.85 | Sphere size, 1.0 = original |
| `Difficulty` | 3.0 | Starting difficulty (1 - 10) |
| `bAdaptive` | True | Difficulty follows your accuracy |
| `AdaptStep`, `RaiseThreshold`, `LowerThreshold` | 0.5, 60, 35 | Step, and the accuracy % that raises / lowers it |
| `bHitSound`, `HitSoundVolume` | True, 1.0 | Hit sound |
| `bStillDrain` | True | Standing still costs health |
| `StillGraceSeconds`, `StillDrainPerSecond`, `MoveRegenPerSecond` | 1.0, 8.0, 3.0 | Drain and regeneration |
| `bStillCanKill` | True | If False, the drain stops at 1 health |

`System\DamageNumbers.ini`, section `[DamageNumbers.DamageNumbersOverlay]`:

| Setting | Default | Meaning |
|---|---|---|
| `PosX`, `PosY` | 0.5, 0.40 | Position on screen (0 - 1, the crosshair is at 0.5 / 0.5) |
| `TextScale` | 1.0 | Size of the numbers |
| `bShowTotal` | True | Also show the sum of the last second |

`System\AimTargets.ini` also has `TextScale` under `[AimTargets.AimTargetsOverlay]`
for the size of the panel and the messages.

## How it works

- Targets are plain actors (`ParticleMeshes.Simple.ParticleSphere2`) with their
  own collision. Beams, projectiles and splash damage all end up in their
  `TakeDamage`, which is why the Shock combo works.
- Shots are counted from the ammo the primary fire consumes, and the ammo is
  refilled every frame.
- The HUD and the damage numbers are `HudOverlay` actors attached to the
  player's HUD, so they disappear with the level.
- Scoring, the standing-still rule and the adaptive difficulty live in
  `AimTargets/Classes/MutAimTargets.uc`.

## Known limitations

- Targets use a cylinder for collision, so the corners of the cylinder fall
  outside the visible sphere. Beam hits that land there are ignored and count as
  a miss.
- Developed for single-player use; behaviour on a network game is untested.
- The history starts from the first round played with the version that saves it.

## Credits

- The idea of pop-up damage numbers comes from
  [HexedUT2k4](https://github.com/hexengraf/HexedUT2k4) (MIT). `Damage Numbers`
  is an independent implementation, no code was copied.
- The hit sound is generated by `tools/make_hitsound.py`.
- Unreal Tournament 2004 is a trademark of Epic Games. This project is not
  affiliated with or endorsed by Epic Games.

## License

Add a license of your choice before publishing (MIT is a common one for mods).
