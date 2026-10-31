# Aim Targets for UT2004

An **offline aim and movement trainer** for Unreal Tournament 2004, built as two
mutators. No bots: purple spheres **fly at you and kill you the moment they touch
you**. Shoot them first with the **Shock Rifle** (beam and combo), the
**Lightning Gun**, the **Flak Cannon** or the **Rocket Launcher** (the only weapons
allowed), while you keep moving. Round after round there are more of them, they
are faster and they zig-zag more.

| Mutator | What it does |
|---|---|
| **Aim Targets** | The trainer: levels, targets, scoring, records, progress history |
| **Damage Numbers** | Fortnite-style pop-up numbers with the damage you deal to other players and bots. Independent from Aim Targets, which does not show damage numbers on its targets |

> Designed for **offline, solo practice** against targets (no bots needed).

## Download

You do not need to compile anything: get the ready-made files from the
[**Releases** page](https://github.com/paoloromolini/ut2004-aim-targets/releases/latest).

1. Download `AimTargets-v1.0.zip` (or the latest version) from the release.
2. Copy the files of its `System` folder into the `System` folder of your UT2004
   installation (for example `C:\UnrealTournament2004\System`):
   - `AimTargets.u` and `AimTargets.ucl` - the trainer
   - `DamageNumbers.u` and `DamageNumbers.ucl` - optional, pop-up damage numbers
     for your other offline matches
3. Start the game: *Instant Action* -> *Deathmatch*, **0 bots**, and enable
   **Aim Targets** in *Mutators*. See [How to play](#how-to-play).

To remove it, delete those files. If you prefer to build it yourself, see
[Installation from source](#installation-from-source).

## How the game works

- Targets **never stand still and never disappear**: they always fly towards you,
  swerving left, right, up and down, and they kill you on contact.
- **Level 1** has 3 targets that barely swerve. At every level the targets get
  faster (one more every two levels, up to 10), they change direction more
  often and they get smaller.
- They come from in front of you **and from the sides** (up to 100 degrees left
  and right of where you are looking), so you cannot just stare at one spot.
- A round lasts 60 seconds. When it ends you go to the next level, unless you died
  3 times or more: then you play the same level again.
- **Every target goes down with the first hit.**
- **Only four weapons are allowed**: Shock Rifle, Lightning Gun, Flak Cannon and
  Rocket Launcher. Automatic weapons (assault rifle, minigun, link gun...) would
  make the targets too easy, so every other weapon is taken away from you and the
  weapon and ammo pickups are removed from the map.
- A destroyed target is replaced by a new one that appears far away and starts
  coming at you. They never teleport.
- **You must keep moving**: standing still drains your health fast, and moving
  while you shoot is worth more points.

## Features

- **Levels that keep rising**: more targets, more speed, more zig-zag, smaller spheres
- **Instant death on contact**, with automatic respawn
- **Rewards movement**: shots while moving, strafing or in the air are worth more
- **Rewards precision and distance**: bullseyes and far targets score more
- **Shock combos count**: pop a target with a combo for a bonus
- **Standing still drains your health fast**, moving gives a little back
- **Announcer voice**: the 5-4-3-2-1 countdown, "Play!", and the killing spree
  calls (Killing Spree, Rampage, Dominating, Unstoppable, GodLike, Holy Shit)
  every 5 hits in a row - it uses the announcer pack you picked in the game
- **Hit sound** whose pitch rises with your streak (you can replace the sound)
- **Round summary** with personal records and a comparison with your last rounds
- **HTML progress report** with charts and a verdict (improving / stable / declining)

## Requirements

- Unreal Tournament 2004 (developed and compiled against build 3374)
- Only to build from source: the game's own `ucc.exe` (it ships with the game)

## Installation from source

The sources are compiled by the game's own compiler.

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
2. In *Mutators*, enable **Aim Targets**. (**Damage Numbers** is a separate mutator
   for your other offline matches.)
3. Start. The first round begins a few seconds after the match starts; the
   trainer removes the frag and time limit so the match never ends.
4. Type `mutate aim help` in the console for the commands.

The last 5 seconds of a round and of a break are counted down by the announcer.
Between rounds there is a 20 second break and the summary stays on screen.
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

Shooting them while they are still far away is worth the most. A shot that misses
breaks the streak. The Shock Rifle ball is not counted as a shot: it is only the
setup of a combo. With the Flak Cannon and the Rocket Launcher a single shot that
hits several targets counts as one hit for the accuracy. Every 5 hits in a row the announcer calls it (Killing Spree at
5, Rampage at 10, Dominating at 15, Unstoppable at 20, GodLike at 25, Holy Shit
from 30).

### Dying

- **A target touches you:** you die instantly.
- **You stand still:** below 100 units/s for more than a second you lose 20 health
  per second, in half-second chunks, and "KEEP MOVING!" appears: about five
  seconds without moving and you are dead. Moving gives back 3 health per second.

You respawn automatically after 1.5 seconds, with a short grace period. The streak
is lost and the targets start again from far away. The deaths are counted in the
summary and in the report.

## Console commands

```
mutate aim help
mutate aim level <n>        start from this level
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
internet needed) and opens it. You get charts of score, accuracy, time to kill a
target, level and shots while moving, with a moving average, plus a verdict that
compares your last 5 rounds with the 5 before. Since the level rises by itself,
the verdict ignores the score and judges accuracy and time to kill, allowing for
the fact that accuracy drops a little at every level. You need at least 6 rounds
before it gives a verdict.

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
| `StartLevel` | 1 | Level of the first round |
| `MaxLevel` | 30 | Highest level |
| `Level1Targets`, `MaxTargets` | 3, 10 | Targets at level 1 (one more every two levels), and the most at the same time |
| `Level1Speed`, `SpeedPerLevel`, `TopSpeed` | 300, 40, 750 | Target speed at level 1, added at every level, and its limit (units/s; you run at about 440) |
| `SpawnAngle` | 100 | Degrees left and right of your view in which targets can appear (180 = all around you) |
| `DeathsToRepeat` | 3 | This many deaths in a round and you play the level again |
| `AllowedWeapons` | Shock Rifle, Lightning Gun, Flak Cannon, Rocket Launcher | The only weapons you can use, as full class names (one `AllowedWeapons=` line each, for example `AllowedWeapons=XWeapons.ShockRifle`). Everything else is removed |
| `TargetScale` | 0.7 | Sphere size, 1.0 = original |
| `TargetSkin` | `UT2004Weapons.Shaders.PurpleShockShader` | Material of the spheres. Other options to try: `UT2004Weapons.Shaders.PurpleShockFinal`, `AWCity.Lights.PlasmaPurple`, `XGameShaders.PlayerShaders.PlayerTrans` (blue), `XGameShaders.PlayerShaders.PlayerTransRed` |
| `bHitSound`, `HitSoundVolume` | True, 1.0 | Hit sound |
| `bAnnouncer` | True | Countdown, "Play!" and killing spree voice |
| `bStillDrain` | True | Standing still costs health |
| `StillGraceSeconds`, `StillDamagePerSecond`, `MoveRegenPerSecond` | 1.0, 20.0, 3.0 | Drain and regeneration |
| `bStillCanKill` | True | If False, the drain stops at 1 health |
| `bTouchKills` | True | A target that touches you kills you |
| `RespawnDelay` | 1.5 | Seconds before you are respawned after dying |

`System\DamageNumbers.ini`, section `[DamageNumbers.DamageNumbersOverlay]`:

| Setting | Default | Meaning |
|---|---|---|
| `PosX`, `PosY` | 0.5, 0.40 | Position on screen (0 - 1, the crosshair is at 0.5 / 0.5) |
| `TextScale` | 1.0 | Size of the numbers |
| `bShowTotal` | True | Also show the sum of the last second |

`System\AimTargets.ini` also has `TextScale` under `[AimTargets.AimTargetsOverlay]`
for the size of the panel and the messages.

### Changing the hit sound

The sound is `AimTargets/Sounds/HitSound.wav` (16-bit PCM, mono or stereo). Replace
it with your own and compile again: the sound is built into `AimTargets.u`.
`tools/make_hitsound.py` can generate a simple replacement.

## How it works

- Targets are plain actors (`ParticleMeshes.Simple.ParticleSphere2`) with their
  own collision. Beams, projectiles and splash damage all end up in their
  `TakeDamage`, which is why the Shock combo works.
- The trainer moves the targets itself every frame: they steer towards you with a
  sideways and vertical swerve that grows with the level.
- Shots are counted from the ammo the primary fire consumes, and the ammo is
  refilled every frame.
- The HUD (and the pop-up numbers of Damage Numbers) are `HudOverlay` actors
  attached to the player's HUD, so they disappear with the level.
- The game logic lives in `AimTargets/Classes/MutAimTargets.uc`.

## Known limitations

- Targets use a cylinder for collision, so the corners of the cylinder fall
  outside the visible sphere. Beam hits that land there are ignored and count as
  a miss.
- Targets that get stuck behind level geometry slide or climb around it, but a
  very closed map can slow them down. Open maps work best.
- Developed for single-player use; behaviour on a network game is untested.
- The history starts from the first round played with the version that saves it.

## Credits

- The idea of pop-up damage numbers comes from
  [HexedUT2k4](https://github.com/hexengraf/HexedUT2k4) (MIT). `Damage Numbers`
  is an independent implementation, no code was copied.
- Unreal Tournament 2004 is a trademark of Epic Games. This project is not
  affiliated with or endorsed by Epic Games.

## License

Add a license of your choice before publishing (MIT is a common one for mods).
