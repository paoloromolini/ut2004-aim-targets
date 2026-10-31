// Aim Targets - offline aim and movement trainer built around floating spheres.
// Made for the Shock Rifle (beam and combo) and the Lightning Gun.
//
// Modes:
//   Flick  - static spheres, a new one appears after every hit
//   Strafe - spheres that strafe left and right
//   Sniper - small, distant, slowly drifting spheres
//   Mixed  - cycles through the three modes
//
// Console commands:  mutate aim help
// Settings:          System/AimTargets.ini
class MutAimTargets extends Mutator config(AimTargets);

#exec AUDIO IMPORT FILE=Sounds\HitSound.wav NAME=HitSound

const ModeFlick = 0;
const ModeStrafe = 1;
const ModeSniper = 2;
const ModeMixed = 3;

// Speed (units/s) at which you count as moving / strafing.
const MoveSpeed = 200.0;
const StrafeSpeed = 250.0;

// A shot without a hit after this many seconds is a miss.
const MissDelay = 0.15;

// Seconds between attempts to spawn a target when no spot is found.
const SpawnRetry = 0.25;

// Vertical spread of the spawn directions (rotation units, 1800 = about 10 degrees).
const PitchArc = 1800;

// Below this speed (units/s) the player counts as standing still.
const StillSpeed = 100.0;

// Distance bonus: x1.0 up to DistRef, then +1.0 for every DistStep units, capped at DistMax.
const DistRef = 500.0;
const DistStep = 2000.0;
const DistMax = 3.0;

// Rounds kept in the history used by the progress report.
const MaxHistory = 600;


// =====================================================
// CONFIG (System/AimTargets.ini)
// =====================================================

var config int RoundDuration;
var config int BreakSeconds;            // pause between rounds, the summary stays on screen
var config int SelectedMode;            // 0 flick, 1 strafe, 2 sniper, 3 mixed
var config int TargetCount;
var config float TargetSizeScale;       // 1.0 = original size
var config float Difficulty;            // 1.0 .. 10.0
var config bool bAdaptive;
var config float AdaptStep;
var config float RaiseThreshold;        // accuracy % that raises the difficulty
var config float LowerThreshold;        // accuracy % that lowers it

var config bool bHitSound;
var config float HitSoundVolume;

// Standing still drains health, moving slowly gives it back.
var config bool bStillDrain;
var config float StillGraceSeconds;
var config float StillDrainPerSecond;
var config float MoveRegenPerSecond;
var config bool bStillCanKill;

// One line per round: used by tools/aimmods.sh report.
var config array<string> History;

// Personal records, indexed by mode (flick, strafe, sniper).
var config int BestScore[3];
var config int BestAccuracy[3];
var config int BestTime[3];             // average milliseconds per target, 0 = none yet


// =====================================================
// STATE
// =====================================================

var int ActiveMode;
var int RoundNumber;
var int RoundTimeLeft;
var int IntermissionTimeLeft;

var bool bTrainerStarted;
var bool bRoundActive;
var bool bIntermission;

var PlayerController PC;
var AimTargetsOverlay HUD;
var array<AimTarget> Targets;
var float NextSpawnTry;

var Sound HitSound;

// Standing still.
var float StillTime;
var float DrainAccum;
var float RegenAccum;
var bool bDraining;

// Round statistics.
var int Score;
var int ShotsFired;
var int ShotsHit;
var int Misses;
var int TargetsHit;
var int Expired;
var int Streak;
var int BestStreak;
var int MovingShots;
var int MovingHits;
var int Bullseyes;
var int ComboHits;
var float TimeSum;
var int TimeCount;

// Shot tracking.
var Weapon LastWeapon;
var int LastAmmo0;
var int LastAmmo1;
var int LastHitShot;
var bool bPendingShot;
var bool bPendingHit;
var float PendingShotTime;
var float LastShotTime;
var vector LastShotVel;
var vector LastShotLoc;
var bool bLastShotAir;


// =====================================================
// INITIALIZATION
// =====================================================

function PostBeginPlay()
{
    Super.PostBeginPlay();

    RoundDuration = Max(RoundDuration, 15);
    BreakSeconds = Max(BreakSeconds, 5);
    SelectedMode = Clamp(SelectedMode, 0, 3);
    TargetCount = Clamp(TargetCount, 1, 8);
    TargetSizeScale = FClamp(TargetSizeScale, 0.3, 1.5);
    Difficulty = FClamp(Difficulty, 1.0, 10.0);

    if (Level.Game != None)
    {
        // Endless training: no frag / time limit ending the match.
        Level.Game.GoalScore = 0;
        Level.Game.TimeLimit = 0;
    }

    // The first round starts in Timer() once the match has actually begun.
    SetTimer(1.0, True);
}


// Gives the Shock Rifle and the Lightning Gun to the player.
function ModifyPlayer(Pawn Other)
{
    Super.ModifyPlayer(Other);

    if (Other != None && PlayerController(Other.Controller) != None)
    {
        Other.GiveWeapon("XWeapons.ShockRifle");
        Other.GiveWeapon("XWeapons.SniperRifle");
    }
}


// The local player: the only one the trainer scores.
function EnsurePlayer()
{
    local Controller C;
    local PlayerController P;

    if (PC != None && PC.Player != None)
        return;

    PC = None;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        P = PlayerController(C);

        if (P != None && Viewport(P.Player) != None)
        {
            PC = P;
            return;
        }
    }
}


function EnsureHUD()
{
    local int i;

    if (HUD != None || PC == None || PC.myHUD == None)
        return;

    for (i = 0; i < PC.myHUD.Overlays.Length; i++)
    {
        HUD = AimTargetsOverlay(PC.myHUD.Overlays[i]);

        if (HUD != None)
        {
            HUD.Trainer = Self;
            return;
        }
    }

    HUD = PC.Spawn(class'AimTargetsOverlay', PC.myHUD);

    if (HUD != None)
    {
        PC.myHUD.AddHudOverlay(HUD);
        HUD.Trainer = Self;
    }
}


// =====================================================
// DIFFICULTY -> TARGET PARAMETERS
// =====================================================

function float TargetRadius()
{
    if (ActiveMode == ModeSniper)
        return FMax(30.0, 90.0 - 5.0 * Difficulty) * TargetSizeScale;

    if (ActiveMode == ModeStrafe)
        return FMax(26.0, 60.0 - 3.0 * Difficulty) * TargetSizeScale;

    return FMax(22.0, 56.0 - 3.0 * Difficulty) * TargetSizeScale;
}

function float MinDistance()
{
    if (ActiveMode == ModeSniper)
        return 1800.0;

    if (ActiveMode == ModeStrafe)
        return 900.0;

    return 800.0;
}

function float MaxDistance()
{
    if (ActiveMode == ModeSniper)
        return 3200.0;

    if (ActiveMode == ModeStrafe)
        return 1700.0;

    return 1500.0;
}

// Half width of the spawn cone (rotation units, 65536 = 360 degrees).
function int SpawnArc()
{
    if (ActiveMode == ModeSniper)
        return 7000;

    if (ActiveMode == ModeStrafe)
        return 4500;

    return 6000;
}

function float TargetLifetime()
{
    if (ActiveMode == ModeSniper)
        return 6.0;

    if (ActiveMode == ModeStrafe)
        return 8.0;

    return FMax(1.8, 4.5 - 0.25 * Difficulty);
}

function float TargetSpeed()
{
    if (ActiveMode == ModeSniper)
        return 60.0 + 25.0 * Difficulty;

    if (ActiveMode == ModeStrafe)
        return 150.0 + 60.0 * Difficulty;

    return 0.0;
}

function float MoveRange()
{
    if (ActiveMode == ModeSniper)
        return 300.0;

    return 500.0;
}

function float ChangeInterval()
{
    return FMax(0.5, 1.6 - 0.1 * Difficulty);
}

function int WantedTargets()
{
    if (ActiveMode == ModeFlick)
        return TargetCount;

    return Max(1, TargetCount - 1);
}

function string ModeName(int M)
{
    if (M == ModeFlick)
        return "FLICK";

    if (M == ModeStrafe)
        return "STRAFE";

    if (M == ModeSniper)
        return "SNIPER";

    return "MIXED";
}

function string FormatTime(int Seconds)
{
    local int M;
    local int S;

    M = Seconds / 60;
    S = Seconds - M * 60;

    if (S < 10)
        return M $ ":0" $ S;

    return M $ ":" $ S;
}

function string FormatLevel(float D)
{
    local int Whole;

    Whole = int(D);

    return Whole $ "." $ (int(D * 10.0) - Whole * 10);
}

function int AccuracyPct()
{
    if (ShotsFired <= 0)
        return 0;

    return Min(100, int(float(ShotsHit) / float(ShotsFired) * 100.0));
}

function int AvgTimeMs()
{
    if (TimeCount <= 0)
        return 0;

    return int(TimeSum / float(TimeCount) * 1000.0);
}


// =====================================================
// HISTORY AND PROGRESS
// =====================================================

function string Pad2(int N)
{
    if (N < 10)
        return "0" $ N;

    return "" $ N;
}

function string TimeStamp()
{
    return Level.Year $ "-" $ Pad2(Level.Month) $ "-" $ Pad2(Level.Day)
        $ " " $ Pad2(Level.Hour) $ ":" $ Pad2(Level.Minute);
}

function string Signed(int V)
{
    if (V > 0)
        return "+" $ V;

    return "" $ V;
}


// Field number Index (0 based) of a history line "a|b|c".
function string HistoryField(string Line, int Index)
{
    local int i;
    local int P;

    for (i = 0; i < Index; i++)
    {
        P = InStr(Line, "|");

        if (P < 0)
            return "";

        Line = Mid(Line, P + 1);
    }

    P = InStr(Line, "|");

    if (P < 0)
        return Line;

    return Left(Line, P);
}


// Average of a numeric history field over the last Count rounds of a mode.
function float RecentAverage(string ModeStr, int FieldIndex, int Count, out int Found)
{
    local int i;
    local float Sum;

    Found = 0;

    for (i = History.Length - 1; i >= 0 && Found < Count; i--)
    {
        if (HistoryField(History[i], 1) == ModeStr)
        {
            Sum += float(HistoryField(History[i], FieldIndex));
            Found++;
        }
    }

    if (Found == 0)
        return 0;

    return Sum / float(Found);
}


// Compares this round with the last 5 rounds of the same mode.
// Call BEFORE RecordHistory. Kind: 0 white, 2 green (better), 3 red (worse).
function string TrendText(out int Kind)
{
    local int N;
    local int ScoreDelta;
    local int AccDelta;
    local float AvgScore;
    local float AvgAcc;

    Kind = 0;

    AvgScore = RecentAverage(ModeName(ActiveMode), 3, 5, N);

    if (N < 3 || AvgScore <= 0.0)
        return "PROGRESS: play a few more rounds of this mode to see your trend";

    AvgAcc = RecentAverage(ModeName(ActiveMode), 4, 5, N);

    ScoreDelta = int((float(Score) - AvgScore) / AvgScore * 100.0);
    AccDelta = AccuracyPct() - int(AvgAcc);

    if (ScoreDelta >= 5)
        Kind = 2;
    else if (ScoreDelta <= -5)
        Kind = 3;

    return "VS YOUR LAST " $ N $ " ROUNDS: SCORE " $ Signed(ScoreDelta)
        $ "%   ACCURACY " $ Signed(AccDelta) $ " pts";
}


// One line per round. Fields (separated by |):
// 0 date, 1 mode, 2 difficulty, 3 score, 4 accuracy %, 5 avg ms per target,
// 6 targets hit, 7 expired, 8 shots while moving %, 9 best streak,
// 10 bullseyes, 11 combo hits, 12 shots fired
function RecordHistory(string DiffStr)
{
    local int MovingPct;

    // Rounds played away from the keyboard say nothing.
    if (ShotsFired <= 0 && TargetsHit <= 0)
        return;

    if (ShotsFired > 0)
        MovingPct = int(float(MovingShots) / float(ShotsFired) * 100.0);

    History[History.Length] = TimeStamp()
        $ "|" $ ModeName(ActiveMode)
        $ "|" $ DiffStr
        $ "|" $ Score
        $ "|" $ AccuracyPct()
        $ "|" $ AvgTimeMs()
        $ "|" $ TargetsHit
        $ "|" $ Expired
        $ "|" $ MovingPct
        $ "|" $ BestStreak
        $ "|" $ Bullseyes
        $ "|" $ ComboHits
        $ "|" $ ShotsFired;

    while (History.Length > MaxHistory)
        History.Remove(0, 1);
}


// =====================================================
// STANDING STILL
// =====================================================

// Standing still drains health, moving gives a little back.
function UpdateStillDrain(float Delta)
{
    local Pawn P;
    local int N;
    local bool bMoving;

    if (!bStillDrain)
    {
        bDraining = False;
        return;
    }

    P = PC.Pawn;

    bMoving = P.Physics == PHYS_Falling || VSize(P.Velocity) >= StillSpeed;

    if (bMoving)
    {
        StillTime = 0;
        DrainAccum = 0;
        bDraining = False;

        if (P.Health < P.HealthMax)
        {
            RegenAccum += MoveRegenPerSecond * Delta;
            N = int(RegenAccum);

            if (N > 0)
            {
                RegenAccum -= float(N);
                P.Health = Min(P.Health + N, P.HealthMax);
            }
        }

        return;
    }

    RegenAccum = 0;
    StillTime += Delta;

    if (StillTime < StillGraceSeconds)
    {
        bDraining = False;
        return;
    }

    bDraining = True;
    DrainAccum += StillDrainPerSecond * Delta;

    // Hurt in chunks of half a second so the pain feedback is not constant.
    if (DrainAccum < StillDrainPerSecond * 0.5)
        return;

    N = int(DrainAccum);
    DrainAccum -= float(N);

    if (N <= 0)
        return;

    if (!bStillCanKill && P.Health - N < 1)
    {
        P.Health = 1;
        return;
    }

    P.TakeDamage(N, None, P.Location, vect(0,0,0), class'Suicided');
}


// =====================================================
// ROUND MANAGEMENT
// =====================================================

function ResetStats()
{
    Score = 0;
    ShotsFired = 0;
    ShotsHit = 0;
    Misses = 0;
    TargetsHit = 0;
    Expired = 0;
    Streak = 0;
    BestStreak = 0;
    MovingShots = 0;
    MovingHits = 0;
    Bullseyes = 0;
    ComboHits = 0;
    TimeSum = 0;
    TimeCount = 0;

    LastWeapon = None;
    LastHitShot = 0;
    bPendingShot = False;
    bPendingHit = False;
    LastShotTime = -10.0;
}


function ClearTargets()
{
    local int i;

    for (i = 0; i < Targets.Length; i++)
    {
        if (Targets[i] != None)
            Targets[i].Destroy();
    }

    Targets.Length = 0;
}


function StartNewRound()
{
    RoundNumber++;

    if (SelectedMode == ModeMixed)
        ActiveMode = (RoundNumber - 1) - ((RoundNumber - 1) / 3) * 3;
    else
        ActiveMode = Clamp(SelectedMode, 0, 2);

    RoundTimeLeft = RoundDuration;

    bRoundActive = True;
    bIntermission = False;

    ResetStats();
    ClearTargets();
    NextSpawnTry = 0;

    StillTime = 0;
    DrainAccum = 0;
    RegenAccum = 0;
    bDraining = False;

    // Every round starts with full health.
    if (PC != None && PC.Pawn != None)
        PC.Pawn.Health = PC.Pawn.HealthMax;

    if (HUD != None)
    {
        HUD.SummaryUntil = 0;
        HUD.ShowBanner(
            "ROUND " $ RoundNumber $ " - " $ ModeName(ActiveMode)
            $ "  (LV " $ FormatLevel(Difficulty) $ ")",
            3.0
        );
    }
}


// Raises or lowers the difficulty from the accuracy of the round.
// Returns a short description for the summary.
function string AdaptDifficulty()
{
    local float Perf;
    local float OldDifficulty;

    if (!bAdaptive)
        return "DIFFICULTY: " $ FormatLevel(Difficulty) $ " (fixed)";

    // Too few shots: the player was probably away, do not punish.
    if (ShotsFired < 5)
        return "DIFFICULTY: " $ FormatLevel(Difficulty) $ " (too few shots)";

    Perf = float(AccuracyPct());
    OldDifficulty = Difficulty;

    if (Perf >= RaiseThreshold)
        Difficulty = FMin(10.0, Difficulty + AdaptStep);
    else if (Perf < LowerThreshold)
        Difficulty = FMax(1.0, Difficulty - AdaptStep);

    if (Difficulty > OldDifficulty)
        return "DIFFICULTY UP: " $ FormatLevel(OldDifficulty) $ " -> " $ FormatLevel(Difficulty);

    if (Difficulty < OldDifficulty)
        return "DIFFICULTY DOWN: " $ FormatLevel(OldDifficulty) $ " -> " $ FormatLevel(Difficulty);

    return "DIFFICULTY: " $ FormatLevel(Difficulty) $ " (accuracy " $ AccuracyPct() $ "%)";
}


function EndRound()
{
    local int M;
    local int Acc;
    local int AvgMs;
    local int OldBestScore;
    local int OldBestAcc;
    local int OldBestTime;
    local bool bNewScore;
    local bool bNewAcc;
    local bool bNewTime;
    local int TrendKind;
    local string Line;
    local string AdaptText;
    local string TrendLine;
    local string DiffStr;

    if (!bRoundActive)
        return;

    bRoundActive = False;
    bIntermission = True;
    bDraining = False;
    IntermissionTimeLeft = BreakSeconds;

    ClearTargets();

    M = ActiveMode;
    Acc = AccuracyPct();
    AvgMs = AvgTimeMs();

    // PERSONAL RECORDS

    OldBestScore = BestScore[M];
    OldBestAcc = BestAccuracy[M];
    OldBestTime = BestTime[M];

    bNewScore = Score > OldBestScore;
    bNewAcc = ShotsFired >= 10 && Acc > OldBestAcc;
    bNewTime = TimeCount >= 5 && (OldBestTime == 0 || AvgMs < OldBestTime);

    if (bNewScore)
        BestScore[M] = Score;

    if (bNewAcc)
        BestAccuracy[M] = Acc;

    if (bNewTime)
        BestTime[M] = AvgMs;

    // The trend compares with the rounds BEFORE this one, so it comes first.
    TrendLine = TrendText(TrendKind);

    // History keeps the difficulty the round was played at.
    DiffStr = FormatLevel(Difficulty);
    RecordHistory(DiffStr);

    AdaptText = AdaptDifficulty();

    SaveConfig();

    // SUMMARY

    if (PC != None)
        PC.ClientMessage("[AIM TARGETS] Round over - score " $ Score $ ", accuracy " $ Acc $ "%");

    if (HUD == None)
        return;

    HUD.ClearSummary();

    HUD.AddSummaryLine("ROUND " $ RoundNumber $ " COMPLETE - " $ ModeName(M), 1);

    Line = "SCORE: " $ Score $ "   (best " $ OldBestScore $ ")";
    if (bNewScore)
        Line = Line $ "   NEW RECORD!";
    HUD.AddSummaryLine(Line, 0);

    Line = "ACCURACY: " $ Acc $ "%  (" $ ShotsHit $ "/" $ ShotsFired $ " shots)   (best " $ OldBestAcc $ "%)";
    if (bNewAcc)
        Line = Line $ "   NEW RECORD!";
    HUD.AddSummaryLine(Line, 0);

    if (TimeCount > 0)
    {
        Line = "AVG TIME PER TARGET: " $ AvgMs $ " ms";
        if (OldBestTime > 0)
            Line = Line $ "   (best " $ OldBestTime $ " ms)";
        if (bNewTime)
            Line = Line $ "   NEW RECORD!";
        HUD.AddSummaryLine(Line, 0);
    }

    HUD.AddSummaryLine(
        "TARGETS: " $ TargetsHit $ " hit, " $ Expired $ " expired   BEST STREAK: " $ BestStreak,
        0
    );

    if (ShotsFired > 0)
    {
        HUD.AddSummaryLine(
            "SHOTS WHILE MOVING: " $ int(float(MovingShots) / float(ShotsFired) * 100.0) $ "%",
            0
        );
    }

    if (Bullseyes > 0 || ComboHits > 0)
        HUD.AddSummaryLine("BULLSEYES: " $ Bullseyes $ "   COMBO HITS: " $ ComboHits, 0);

    HUD.AddSummaryLine(TrendLine, TrendKind);
    HUD.AddSummaryLine(AdaptText, 2);

    if (SelectedMode == ModeMixed)
        HUD.AddSummaryLine("NEXT MODE: " $ ModeName(RoundNumber - (RoundNumber / 3) * 3), 1);

    HUD.SummaryUntil = Level.TimeSeconds + float(BreakSeconds) - 0.5;
}


// =====================================================
// TIMER (every second): round clock
// =====================================================

function Timer()
{
    if (Level.Game == None || Level.Game.bGameEnded)
        return;

    EnsurePlayer();
    EnsureHUD();

    if (!bTrainerStarted)
    {
        if (Level.Game.GameReplicationInfo != None
            && Level.Game.GameReplicationInfo.bMatchHasBegun)
        {
            bTrainerStarted = True;
            bIntermission = True;
            IntermissionTimeLeft = 5;

            if (HUD != None)
                HUD.ShowBanner("GET READY - type 'mutate aim help' in the console", 4.0);
        }

        return;
    }

    if (bRoundActive)
    {
        RoundTimeLeft--;

        if (HUD != None)
        {
            if (RoundTimeLeft == 30 || RoundTimeLeft == 10)
                HUD.ShowBanner(RoundTimeLeft $ " SECONDS", 1.2);
            else if (RoundTimeLeft > 0 && RoundTimeLeft <= 3)
                HUD.ShowBanner("" $ RoundTimeLeft, 0.9);
        }

        if (RoundTimeLeft <= 0)
            EndRound();
    }
    else if (bIntermission)
    {
        IntermissionTimeLeft--;

        if (IntermissionTimeLeft <= 0)
            StartNewRound();
    }
}


// =====================================================
// TICK (every frame): shots and targets
// =====================================================

event Tick(float DeltaTime)
{
    if (Level.Game == None || Level.Game.bGameEnded)
        return;

    if (!bTrainerStarted || !bRoundActive)
        return;

    if (PC == None || PC.Pawn == None || PC.Pawn.Health <= 0)
        return;

    UpdateShots();
    CheckMisses();
    UpdateTargets(DeltaTime);
    UpdateStillDrain(DeltaTime);
}


// Counts the shots from the ammo consumed by the primary fire, then refills the ammo.
// The Shock Rifle ball (alt fire) is not a shot: it is only the setup of a combo.
function UpdateShots()
{
    local Weapon W;
    local WeaponFire Fire0;
    local WeaponFire Fire1;
    local int Ammo0;
    local int Used;
    local int Shots;
    local vector Vel;

    if (PC == None || PC.Pawn == None)
        return;

    W = PC.Pawn.Weapon;

    if (W == None)
    {
        LastWeapon = None;
        return;
    }

    Ammo0 = W.AmmoAmount(0);

    if (LastWeapon == W && Ammo0 < LastAmmo0)
    {
        Used = LastAmmo0 - Ammo0;

        Fire0 = W.GetFireMode(0);
        Fire1 = W.GetFireMode(1);

        // Shared ammo: tell the modes apart by which one is firing.
        if (Fire1 != None && Fire1.bIsFiring && (Fire0 == None || !Fire0.bIsFiring))
        {
            Shots = 0;
        }
        else
        {
            Shots = Used;

            if (Fire0 != None && Fire0.AmmoPerFire > 1)
                Shots = Max(1, Used / Fire0.AmmoPerFire);
        }

        if (Shots > 0)
        {
            ShotsFired += Shots;

            Vel = PC.Pawn.Velocity;
            Vel.Z = 0;

            LastShotTime = Level.TimeSeconds;
            LastShotVel = Vel;
            LastShotLoc = PC.Pawn.Location;
            bLastShotAir = PC.Pawn.Physics == PHYS_Falling;

            if (VSize(Vel) >= MoveSpeed || bLastShotAir)
                MovingShots += Shots;

            bPendingShot = True;
            bPendingHit = False;
            PendingShotTime = Level.TimeSeconds;
        }
    }

    W.MaxOutAmmo();

    LastWeapon = W;
    LastAmmo0 = W.AmmoAmount(0);
    LastAmmo1 = W.AmmoAmount(1);
}


// A shot that hit nothing breaks the streak.
function CheckMisses()
{
    if (bPendingShot && !bPendingHit && Level.TimeSeconds - PendingShotTime > MissDelay)
    {
        bPendingShot = False;
        Misses++;
        Streak = 0;
    }
}


// =====================================================
// TARGETS
// =====================================================

function UpdateTargets(float Delta)
{
    local int i;
    local AimTarget T;

    for (i = Targets.Length - 1; i >= 0; i--)
    {
        T = Targets[i];

        if (T == None)
        {
            Targets.Remove(i, 1);
            continue;
        }

        // Not hit in time: it counts against you and a new one appears.
        if (Level.TimeSeconds >= T.ExpireTime)
        {
            Expired++;
            Streak = 0;

            T.Destroy();
            Targets.Remove(i, 1);
            continue;
        }

        if (T.Speed > 0.0)
            MoveTarget(T, Delta);
    }

    while (Targets.Length < WantedTargets() && Level.TimeSeconds >= NextSpawnTry)
    {
        if (!SpawnTarget())
        {
            NextSpawnTry = Level.TimeSeconds + SpawnRetry;
            break;
        }
    }
}


// Strafes the target on a plane perpendicular to the line of sight at spawn.
function MoveTarget(AimTarget T, float Delta)
{
    if (Level.TimeSeconds >= T.NextChange)
    {
        T.Sign = -T.Sign;
        T.Vel = Normal(T.Lateral * T.Sign + vect(0,0,1) * (FRand() - 0.5) * 0.5) * T.Speed;
        T.NextChange = Level.TimeSeconds + ChangeInterval() * (0.6 + FRand() * 0.8);
    }

    // Too far from where it started: come back.
    if (VSize(T.Location - T.Anchor) > T.Range)
        T.Vel = Normal(T.Anchor - T.Location) * T.Speed;

    // Blocked by the level: turn around.
    if (!T.Move(T.Vel * Delta))
    {
        T.Sign = -T.Sign;
        T.Vel = -T.Vel;
        T.NextChange = Level.TimeSeconds + 0.3;
    }
}


// Spawns a target at a random spot in front of the player, in line of sight.
function bool SpawnTarget()
{
    local AimTarget T;
    local int Attempt;
    local int Arc;
    local int i;
    local bool bFree;
    local rotator R;
    local vector Eye;
    local vector Cand;
    local vector ToCand;
    local float Rad;

    Eye = PC.Pawn.Location + PC.Pawn.EyePosition();
    Rad = TargetRadius();
    Arc = SpawnArc();

    for (Attempt = 0; Attempt < 20; Attempt++)
    {
        R.Yaw = PC.Rotation.Yaw + Rand(2 * Arc + 1) - Arc;
        R.Pitch = Rand(2 * PitchArc + 1) - PitchArc;
        R.Roll = 0;

        Cand = Eye + vector(R) * RandRange(MinDistance(), MaxDistance());

        if (!FastTrace(Cand, Eye))
            continue;

        // Not on top of another target.
        bFree = True;

        for (i = 0; i < Targets.Length; i++)
        {
            if (Targets[i] != None && VSize(Targets[i].Location - Cand) < Rad * 3.0)
                bFree = False;
        }

        if (!bFree)
            continue;

        T = Spawn(class'AimTarget',,, Cand);

        if (T == None)
            continue;

        T.Trainer = Self;
        T.Setup(Rad, TargetSpeed() > 0.0);
        T.SpawnTime = Level.TimeSeconds;
        T.ExpireTime = Level.TimeSeconds + TargetLifetime();

        T.Speed = TargetSpeed();
        T.Range = MoveRange();
        T.Anchor = Cand;

        ToCand = Cand - Eye;
        ToCand.Z = 0;
        T.Lateral = Normal(vect(0,0,1) cross ToCand);

        if (FRand() < 0.5)
            T.Sign = 1.0;
        else
            T.Sign = -1.0;

        T.NextChange = 0;

        Targets[Targets.Length] = T;

        return True;
    }

    return False;
}


// Called by a target when a weapon damages it.
function TargetHit(AimTarget T, Pawn Shooter, int Damage, vector HitLoc, class<DamageType> DT)
{
    local int i;
    local int Points;
    local bool bCombo;
    local bool bAir;
    local float Now;
    local float Err;
    local float Center;
    local float Speed;
    local float Lat;
    local float Mult;
    local float MoveMult;
    local float DistMult;
    local float Pitch;
    local vector Eye;
    local vector Dir;
    local vector Vel;
    local vector Loc;
    local vector ToT;
    local string Label;

    if (!bRoundActive || T == None || PC == None || PC.Pawn == None || Shooter != PC.Pawn)
        return;

    // Count the shot before its hit (the hit arrives in the same frame).
    UpdateShots();

    Now = Level.TimeSeconds;

    bCombo = DT != None && ClassIsChildOf(DT, class'DamTypeShockCombo');

    // BULLSEYE: how close to the center of the sphere the shot went.
    // Only for shots that travelled along the view ray (beams); projectiles
    // and splash damage are accepted as they are.
    Center = 0.0;
    Eye = Shooter.Location + Shooter.EyePosition();
    Dir = vector(PC.GetViewRotation());

    if (!bCombo && HitLoc != vect(0,0,0))
    {
        // Distance of the impact point from the view ray.
        Err = VSize((HitLoc - Eye) - Dir * ((HitLoc - Eye) dot Dir));

        if (Err < 8.0)
        {
            // The collision is a cylinder: its corners are outside the sphere.
            Err = VSize((T.Location - Eye) - Dir * ((T.Location - Eye) dot Dir));

            if (Err > T.Radius)
                return;

            Center = 1.0 - Err / T.Radius;
        }
    }

    // MOVEMENT: judged at the moment of the shot.
    if (Now - LastShotTime < 0.4)
    {
        Vel = LastShotVel;
        Loc = LastShotLoc;
        bAir = bLastShotAir;
    }
    else
    {
        Vel = PC.Pawn.Velocity;
        Vel.Z = 0;
        Loc = PC.Pawn.Location;
        bAir = PC.Pawn.Physics == PHYS_Falling;
    }

    Speed = VSize(Vel);

    ToT = T.Location - Loc;
    ToT.Z = 0;

    if (VSize(ToT) > 1.0)
        ToT = Normal(ToT);

    // Speed sideways relative to the target = strafing.
    Lat = Abs(Vel dot (ToT cross vect(0,0,1)));

    MoveMult = 1.0;
    Label = "";

    if (bAir)
    {
        MoveMult = 2.0;
        Label = "  AIR x2";
    }
    else if (Lat >= StrafeSpeed)
    {
        MoveMult = 2.0;
        Label = "  STRAFE x2";
    }
    else if (Speed >= MoveSpeed)
    {
        MoveMult = 1.5;
        Label = "  MOVING x1.5";
    }

    Mult = MoveMult;

    if (Center >= 0.7)
    {
        Mult = Mult * 1.5;
        Label = Label $ "  BULLSEYE";
        Bullseyes++;
    }
    else if (Center >= 0.4)
    {
        Mult = Mult * 1.2;
    }

    if (bCombo)
    {
        Mult = Mult * 2.0;
        Label = Label $ "  COMBO x2";
        ComboHits++;
    }

    // DISTANCE: the farther the target, the more points.
    DistMult = FMin(DistMax, 1.0 + FMax(0.0, VSize(T.Location - Eye) - DistRef) / DistStep);

    if (DistMult >= 1.2)
        Label = Label $ "  DISTANCE x" $ FormatLevel(DistMult);

    Mult = Mult * DistMult;

    Mult = Mult * (1.0 + 0.1 * float(Min(Streak, 10)));

    Points = int(100.0 * Mult);

    // STATS

    Score += Points;
    TargetsHit++;
    Streak++;
    BestStreak = Max(BestStreak, Streak);

    TimeSum += Now - T.SpawnTime;
    TimeCount++;

    if (MoveMult > 1.0)
        MovingHits++;

    // At most one counted hit per shot (a combo can pop several targets).
    if (ShotsFired > LastHitShot)
    {
        ShotsHit++;
        LastHitShot = ShotsFired;
    }

    bPendingHit = True;

    // FEEDBACK

    // The pitch rises with the streak (a bullseye adds a bit more).
    if (bHitSound && HitSound != None && PC.ViewTarget != None)
    {
        Pitch = 1.0 + 0.05 * float(Min(Streak, 12));

        if (Center >= 0.7)
            Pitch += 0.15;

        PC.ViewTarget.PlaySound(HitSound,, HitSoundVolume,,, FClamp(Pitch, 1.0, 2.0));
    }

    if (HUD != None)
        HUD.ShowFeed("+" $ Points $ Label, 1.0);

    class'DamageNumbersOverlay'.static.ShowFor(PC, Damage, False);

    // The target disappears, a new one is spawned in the next tick.

    T.bDead = True;

    for (i = Targets.Length - 1; i >= 0; i--)
    {
        if (Targets[i] == T)
            Targets.Remove(i, 1);
    }

    T.Destroy();
}


// =====================================================
// CONSOLE COMMANDS:  mutate aim <command>
// =====================================================

function Mutate(string MutateString, PlayerController Sender)
{
    if (MutateString ~= "aim")
        HandleCommand("help", Sender);
    else if (Left(MutateString, 4) ~= "aim ")
        HandleCommand(Mid(MutateString, 4), Sender);

    Super.Mutate(MutateString, Sender);
}


function HandleCommand(string Cmd, PlayerController Sender)
{
    local string Arg;
    local int M;

    if (Sender == None)
        return;

    if (Left(Cmd, 5) ~= "mode ")
    {
        Arg = Mid(Cmd, 5);

        if (Arg ~= "flick")
            SelectedMode = ModeFlick;
        else if (Arg ~= "strafe")
            SelectedMode = ModeStrafe;
        else if (Arg ~= "sniper")
            SelectedMode = ModeSniper;
        else if (Arg ~= "mixed")
            SelectedMode = ModeMixed;
        else
        {
            Sender.ClientMessage("[AIM TARGETS] Unknown mode. Use flick, strafe, sniper or mixed.");
            return;
        }

        SaveConfig();
        Sender.ClientMessage("[AIM TARGETS] Mode: " $ ModeName(SelectedMode) $ " (starts next round)");
    }
    else if (Left(Cmd, 5) ~= "diff ")
    {
        Difficulty = FClamp(float(Mid(Cmd, 5)), 1.0, 10.0);
        SaveConfig();
        Sender.ClientMessage("[AIM TARGETS] Difficulty: " $ FormatLevel(Difficulty) $ " (starts next round)");
    }
    else if (Left(Cmd, 8) ~= "targets ")
    {
        TargetCount = Clamp(int(Mid(Cmd, 8)), 1, 8);
        SaveConfig();
        Sender.ClientMessage("[AIM TARGETS] Targets: " $ TargetCount $ " (starts next round)");
    }
    else if (Left(Cmd, 9) ~= "adaptive ")
    {
        bAdaptive = (Mid(Cmd, 9) ~= "on");
        SaveConfig();

        if (bAdaptive)
            Sender.ClientMessage("[AIM TARGETS] Adaptive difficulty ON");
        else
            Sender.ClientMessage("[AIM TARGETS] Adaptive difficulty OFF");
    }
    else if (Cmd ~= "summary")
    {
        // Shows the last round summary again.
        if (HUD != None && HUD.SummaryLines.Length > 0)
            HUD.SummaryUntil = Level.TimeSeconds + 15.0;
        else
            Sender.ClientMessage("[AIM TARGETS] No round finished yet.");
    }
    else if (Cmd ~= "reset")
    {
        for (M = 0; M < 3; M++)
        {
            BestScore[M] = 0;
            BestAccuracy[M] = 0;
            BestTime[M] = 0;
        }

        History.Length = 0;

        SaveConfig();
        Sender.ClientMessage("[AIM TARGETS] Personal records and history cleared.");
    }
    else
    {
        Sender.ClientMessage("[AIM TARGETS] mutate aim mode <flick|strafe|sniper|mixed>");
        Sender.ClientMessage("[AIM TARGETS] mutate aim diff <1-10>   mutate aim targets <1-8>");
        Sender.ClientMessage("[AIM TARGETS] mutate aim adaptive <on|off>   mutate aim summary   mutate aim reset");
        Sender.ClientMessage(
            "[AIM TARGETS] Now: " $ ModeName(SelectedMode) $ ", difficulty "
            $ FormatLevel(Difficulty) $ ", " $ TargetCount $ " targets"
        );
    }
}


defaultproperties
{
    GroupName="AimTargets"

    FriendlyName="Aim Targets"

    Description="Offline aim trainer with floating targets for the Shock Rifle and the Lightning Gun: flick, strafe and sniper modes, adaptive difficulty, personal records."

    HitSound=Sound'HitSound'

    RoundDuration=60
    BreakSeconds=20
    SelectedMode=3
    TargetCount=3
    TargetSizeScale=0.85
    Difficulty=3.0
    bAdaptive=True
    AdaptStep=0.5
    RaiseThreshold=60.0
    LowerThreshold=35.0

    bHitSound=True
    HitSoundVolume=1.0

    bStillDrain=True
    StillGraceSeconds=1.0
    StillDrainPerSecond=8.0
    MoveRegenPerSecond=3.0
    bStillCanKill=True
}
