// Aim Targets - offline aim and movement trainer.
//
// Floating spheres fly at you and kill you the moment they touch you. Shoot them
// first, with the Shock Rifle (beam and combo) or the Lightning Gun, while you keep
// moving. Round after round there are more of them, they are faster and they
// zig-zag more.
//
// Console commands:  mutate aim help
// Settings:          System/AimTargets.ini
class MutAimTargets extends Mutator config(AimTargets);

#exec AUDIO IMPORT FILE=Sounds\HitSound.wav NAME=HitSound

// Speed (units/s) at which you count as moving / strafing.
const MoveSpeed = 200.0;
const StrafeSpeed = 250.0;

// A shot without a hit after this many seconds is a miss.
const MissDelay = 0.15;

// Seconds between two targets appearing, and between attempts when no spot is found.
const SpawnGap = 0.5;
const SpawnRetry = 0.25;

// Vertical spread of the spawn directions (rotation units, 1800 = about 10 degrees).
const PitchArc = 1800;

// Below this speed (units/s) the player counts as standing still.
const StillSpeed = 100.0;

// Distance bonus: x1.0 up to DistRef, then +1.0 for every DistStep units, capped at DistMax.
const DistRef = 500.0;
const DistStep = 2000.0;
const DistMax = 3.0;

// Seconds after a respawn in which a touching target does not kill you.
const TouchGraceSeconds = 2.0;

// An announcer sound plays every time the streak reaches a multiple of this.
const SpreeStep = 5;

// Rounds kept in the history used by the progress report.
const MaxHistory = 600;


// =====================================================
// CONFIG (System/AimTargets.ini)
// =====================================================

var config int RoundDuration;
var config int BreakSeconds;            // pause between rounds, the summary stays on screen

// Level progression: from round to round there are more targets, they are faster
// and they zig-zag more.
var config int StartLevel;
var config int MaxLevel;
var config int Level1Targets;           // targets at level 1 (one more every two levels)
var config int MaxTargets;              // most targets at the same time
var config float Level1Speed;           // target speed at level 1 (units/s)
var config float SpeedPerLevel;         // added at every level
var config float TopSpeed;
var config float SpawnAngle;            // targets appear within this many degrees left/right of where you look
var config int DeathsToRepeat;          // this many deaths in a round and you repeat the level

// Only these weapons can be used (full class names). Automatic weapons such as the
// assault rifle, the minigun or the link gun would make the targets too easy.
var config array<string> AllowedWeapons;

var config float TargetScale;           // 1.0 = original size
var config string TargetSkin;           // material of the targets (purple by default)

var config bool bHitSound;
var config float HitSoundVolume;

// Announcer voice: 5-4-3-2-1 countdown, "Play!", and the killing spree
// calls (Unstoppable...) for long streaks. Uses the announcer pack you picked.
var config bool bAnnouncer;

// Standing still drains health, moving slowly gives it back.
var config bool bStillDrain;
var config float StillGraceSeconds;
var config float StillDamagePerSecond;
var config float MoveRegenPerSecond;
var config bool bStillCanKill;

// A target that touches you kills you.
var config bool bTouchKills;
var config float RespawnDelay;          // seconds before you are respawned after dying

// One line per round: used by tools/aimmods.sh report.
var config array<string> History;

// Personal records.
var config int RecordScore;
var config int RecordLevel;
var config int RecordAccuracy;
var config int RecordTime;              // average milliseconds to kill a target, 0 = none yet


// =====================================================
// STATE
// =====================================================

var int PlayLevel;
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
var Material TargetMaterial;

// Standing still.
var float StillTime;
var float DrainAccum;
var float RegenAccum;
var bool bDraining;

// Dying and respawning.
var bool bWasDead;
var float RespawnAt;
var float TouchGraceUntil;
var int DeathsTouch;
var int DeathsStill;

// Round statistics.
var int Score;
var int ShotsFired;
var int ShotsHit;
var int Misses;
var int TargetsHit;
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
    MaxLevel = Max(MaxLevel, 1);
    StartLevel = Clamp(StartLevel, 1, MaxLevel);
    MaxTargets = Clamp(MaxTargets, 2, 16);
    Level1Targets = Clamp(Level1Targets, 1, MaxTargets);
    SpawnAngle = FClamp(SpawnAngle, 20.0, 180.0);
    TargetScale = FClamp(TargetScale, 0.3, 1.5);
    RespawnDelay = FMax(RespawnDelay, 0.5);

    PlayLevel = StartLevel;

    // The skin can be changed in the ini without recompiling.
    TargetMaterial = Material(DynamicLoadObject(TargetSkin, class'Material', True));

    if (Level.Game != None)
    {
        // Endless training: no frag / time limit ending the match.
        Level.Game.GoalScore = 0;
        Level.Game.TimeLimit = 0;
    }

    // The first round starts in Timer() once the match has actually begun.
    SetTimer(1.0, True);
}


// Gives the allowed weapons to the player and takes the others away.
function ModifyPlayer(Pawn Other)
{
    local int i;

    Super.ModifyPlayer(Other);

    if (Other != None && PlayerController(Other.Controller) != None)
    {
        for (i = 0; i < AllowedWeapons.Length; i++)
            Other.GiveWeapon(AllowedWeapons[i]);

        StripWeapons(Other);
    }
}


function bool IsAllowedWeapon(Weapon W)
{
    local int i;

    for (i = 0; i < AllowedWeapons.Length; i++)
    {
        if (string(W.Class) ~= AllowedWeapons[i])
            return True;
    }

    return False;
}


// Removes every weapon that is not in the allowed list.
function StripWeapons(Pawn P)
{
    local Inventory Inv;
    local Inventory Nxt;
    local Weapon W;
    local bool bRemoved;

    // An empty list would leave the player with nothing: ignore it.
    if (P == None || AllowedWeapons.Length == 0)
        return;

    Inv = P.Inventory;

    while (Inv != None)
    {
        Nxt = Inv.Inventory;
        W = Weapon(Inv);

        if (W != None && !IsAllowedWeapon(W))
        {
            P.DeleteInventory(W);
            W.Destroy();
            bRemoved = True;
        }

        Inv = Nxt;
    }

    if (bRemoved && P.Weapon == None && P.Controller != None)
        P.Controller.SwitchToBestWeapon();
}


// No weapon or ammo pickups on the map: only the allowed weapons are used.
function bool CheckReplacement(Actor Other, out byte bSuperRelevant)
{
    if (Other.IsA('WeaponPickup') || Other.IsA('AmmoPickup') || Other.IsA('WeaponLocker'))
        return False;

    return True;
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
// LEVEL -> TARGET PARAMETERS
// =====================================================

// One more target every two levels.
function int LevelTargets()
{
    return Min(MaxTargets, Level1Targets + (PlayLevel - 1) / 2);
}

function float LevelSpeed()
{
    return FMin(TopSpeed, Level1Speed + SpeedPerLevel * float(PlayLevel - 1));
}

// How much a target swerves sideways while it comes at you (0 = straight line).
function float LevelWeave()
{
    return FMin(0.9, 0.15 + 0.07 * float(PlayLevel - 1));
}

// Seconds between changes of direction: the higher the level, the sharper the zig-zag.
function float LevelFlip()
{
    return FMax(0.35, 1.6 - 0.1 * float(PlayLevel - 1));
}

// Up and down swerve, from the middle levels on.
function float LevelBob()
{
    return FMin(0.5, 0.04 * float(PlayLevel - 1));
}

function float TargetRadius()
{
    return FMax(26.0, 56.0 - 1.5 * float(PlayLevel - 1)) * TargetScale;
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


// Average of a numeric history field over the last Count rounds of this game.
function float RecentAverage(int FieldIndex, int Count, out int Found)
{
    local int i;
    local float Sum;

    Found = 0;

    for (i = History.Length - 1; i >= 0 && Found < Count; i--)
    {
        if (HistoryField(History[i], 1) == "CHASE")
        {
            Sum += float(HistoryField(History[i], FieldIndex));
            Found++;
        }
    }

    if (Found == 0)
        return 0;

    return Sum / float(Found);
}


// Compares this round with your last 5 rounds. The score is not compared,
// because it grows with the level: accuracy and time to kill tell more.
// Call BEFORE RecordHistory. Kind: 0 white, 2 green (better), 3 red (worse).
function string TrendText(out int Kind)
{
    local int N;
    local int AccDelta;
    local int MsDelta;
    local float AvgAcc;
    local float AvgMs;
    local string S;

    Kind = 0;

    AvgAcc = RecentAverage(4, 5, N);

    if (N < 3)
        return "PROGRESS: play a few more rounds to see your trend";

    AccDelta = AccuracyPct() - int(AvgAcc);
    S = "VS YOUR LAST " $ N $ " ROUNDS: ACCURACY " $ Signed(AccDelta) $ " pts";

    AvgMs = RecentAverage(5, 5, N);

    if (AvgMs > 0.0 && TimeCount > 0)
    {
        MsDelta = AvgTimeMs() - int(AvgMs);
        S = S $ "   TIME TO KILL " $ Signed(MsDelta) $ " ms";
    }

    if (AccDelta >= 3)
        Kind = 2;
    else if (AccDelta <= -3)
        Kind = 3;

    return S;
}


// One line per round. Fields (separated by |):
// 0 date, 1 game ("CHASE"), 2 level, 3 score, 4 accuracy %, 5 avg ms to kill a target,
// 6 targets hit, 7 (unused, 0), 8 shots while moving %, 9 best streak,
// 10 bullseyes, 11 combo hits, 12 shots fired,
// 13 deaths touched by a target, 14 deaths from standing still
function RecordHistory()
{
    local int MovingPct;

    // Rounds played away from the keyboard say nothing.
    if (ShotsFired <= 0 && TargetsHit <= 0)
        return;

    if (ShotsFired > 0)
        MovingPct = int(float(MovingShots) / float(ShotsFired) * 100.0);

    History[History.Length] = TimeStamp()
        $ "|CHASE"
        $ "|" $ PlayLevel
        $ "|" $ Score
        $ "|" $ AccuracyPct()
        $ "|" $ AvgTimeMs()
        $ "|" $ TargetsHit
        $ "|0"
        $ "|" $ MovingPct
        $ "|" $ BestStreak
        $ "|" $ Bullseyes
        $ "|" $ ComboHits
        $ "|" $ ShotsFired
        $ "|" $ DeathsTouch
        $ "|" $ DeathsStill;

    while (History.Length > MaxHistory)
        History.Remove(0, 1);
}


// =====================================================
// ANNOUNCER (the voice of the announcer pack you chose in the game)
// =====================================================

function name CountdownName(int N)
{
    if (N == 5)
        return 'Five';

    if (N == 4)
        return 'Four';

    if (N == 3)
        return 'Three';

    if (N == 2)
        return 'Two';

    if (N == 1)
        return 'One';

    return '';
}


// 5, 4, 3, 2, 1
function PlayCountdown(int N)
{
    if (bAnnouncer && PC != None && N >= 1 && N <= 5)
        PC.PlayStatusAnnouncement(CountdownName(N), 1, True);
}


// "Play!" at the start of a round.
function PlayStart()
{
    if (bAnnouncer && PC != None)
        PC.PlayStatusAnnouncement('Play', 1, True);
}


// Killing spree calls: 5 hits in a row Killing Spree, 10 Rampage, 15 Dominating,
// 20 Unstoppable, 25 GodLike, 30 and more Holy Shit.
function CheckSpree()
{
    local int Tier;
    local string Text;

    if (Streak < SpreeStep || Streak - (Streak / SpreeStep) * SpreeStep != 0)
        return;

    Tier = Streak / SpreeStep;

    if (Tier == 1)
    {
        Text = "KILLING SPREE!";
        if (bAnnouncer && PC != None)
            PC.PlayRewardAnnouncement('Killing_Spree', 1, True);
    }
    else if (Tier == 2)
    {
        Text = "RAMPAGE!";
        if (bAnnouncer && PC != None)
            PC.PlayRewardAnnouncement('Rampage', 1, True);
    }
    else if (Tier == 3)
    {
        Text = "DOMINATING!";
        if (bAnnouncer && PC != None)
            PC.PlayRewardAnnouncement('Dominating', 1, True);
    }
    else if (Tier == 4)
    {
        Text = "UNSTOPPABLE!";
        if (bAnnouncer && PC != None)
            PC.PlayRewardAnnouncement('Unstoppable', 1, True);
    }
    else if (Tier == 5)
    {
        Text = "GODLIKE!";
        if (bAnnouncer && PC != None)
            PC.PlayRewardAnnouncement('GodLike', 1, True);
    }
    else
    {
        Text = "HOLY SHIT!";
        if (bAnnouncer && PC != None)
            PC.PlayRewardAnnouncement('HolyShit', 1, True);
    }

    if (HUD != None)
        HUD.ShowBanner(Text $ "  " $ Streak $ " IN A ROW", 1.8);
}


// =====================================================
// DYING AND RESPAWNING
// =====================================================

// Kills the player on the spot (a target touched you).
function KillPlayer()
{
    if (PC == None || PC.Pawn == None)
        return;

    DeathsTouch++;
    Streak = 0;

    if (HUD != None)
        HUD.ShowBanner("A TARGET TOUCHED YOU!", 2.0);

    PC.Pawn.TakeDamage(10000, None, PC.Pawn.Location, vect(0,0,0), class'Suicided');
}


// While you are dead: respawn after a short delay (you do not have to click).
function HandleDead()
{
    if (!bWasDead)
    {
        bWasDead = True;
        RespawnAt = Level.TimeSeconds + RespawnDelay;
        Streak = 0;
        bPendingShot = False;
        bDraining = False;
        ClearTargets();
        return;
    }

    if (Level.TimeSeconds >= RespawnAt)
    {
        PC.ServerReStartPlayer();
        RespawnAt = Level.TimeSeconds + 0.5;
    }
}


// First tick after a respawn: the targets start again from far away.
function OnRespawned()
{
    bWasDead = False;

    TouchGraceUntil = Level.TimeSeconds + TouchGraceSeconds;

    StillTime = 0;
    DrainAccum = 0;
    RegenAccum = 0;

    LastWeapon = None;
    NextSpawnTry = 0;
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
    DrainAccum += StillDamagePerSecond * Delta;

    // Hurt in chunks of half a second so the pain feedback is not constant.
    if (DrainAccum < StillDamagePerSecond * 0.5)
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

    if (P.Health <= N)
    {
        DeathsStill++;
        Streak = 0;

        if (HUD != None)
            HUD.ShowBanner("YOU STOOD STILL!", 2.0);
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
    Streak = 0;
    BestStreak = 0;
    MovingShots = 0;
    MovingHits = 0;
    Bullseyes = 0;
    ComboHits = 0;
    TimeSum = 0;
    TimeCount = 0;
    DeathsTouch = 0;
    DeathsStill = 0;

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

    RoundTimeLeft = RoundDuration;

    bRoundActive = True;
    bIntermission = False;

    ResetStats();
    ClearTargets();
    NextSpawnTry = Level.TimeSeconds + 1.0;

    StillTime = 0;
    DrainAccum = 0;
    RegenAccum = 0;
    bDraining = False;

    // Every round starts with full health.
    if (PC != None && PC.Pawn != None)
        PC.Pawn.Health = PC.Pawn.HealthMax;

    TouchGraceUntil = Level.TimeSeconds + TouchGraceSeconds;

    PlayStart();

    if (HUD != None)
    {
        HUD.SummaryUntil = 0;
        HUD.ShowBanner(
            "LEVEL " $ PlayLevel $ "  -  " $ LevelTargets() $ " TARGETS",
            3.0
        );
    }
}


function EndRound()
{
    local int Acc;
    local int AvgMs;
    local int OldRecordScore;
    local int OldRecordAcc;
    local int OldRecordTime;
    local int Deaths;
    local int PlayedLevel;
    local int TrendKind;
    local bool bNewScore;
    local bool bNewAcc;
    local bool bNewTime;
    local bool bNewLevel;
    local bool bAdvance;
    local string Line;
    local string TrendLine;
    local string LevelLine;

    if (!bRoundActive)
        return;

    bRoundActive = False;
    bIntermission = True;
    bDraining = False;
    IntermissionTimeLeft = BreakSeconds;

    ClearTargets();

    PlayedLevel = PlayLevel;
    Acc = AccuracyPct();
    AvgMs = AvgTimeMs();
    Deaths = DeathsTouch + DeathsStill;

    // PERSONAL RECORDS

    OldRecordScore = RecordScore;
    OldRecordAcc = RecordAccuracy;
    OldRecordTime = RecordTime;

    bNewScore = Score > OldRecordScore;
    bNewAcc = ShotsFired >= 10 && Acc > OldRecordAcc;
    bNewTime = TimeCount >= 5 && (OldRecordTime == 0 || AvgMs < OldRecordTime);
    bNewLevel = PlayedLevel > RecordLevel;

    if (bNewScore)
        RecordScore = Score;

    if (bNewAcc)
        RecordAccuracy = Acc;

    if (bNewTime)
        RecordTime = AvgMs;

    if (bNewLevel)
        RecordLevel = PlayedLevel;

    // The trend compares with the rounds BEFORE this one, so it comes first.
    TrendLine = TrendText(TrendKind);

    RecordHistory();

    // LEVEL PROGRESSION: too many deaths and you play the same level again.

    bAdvance = Deaths < DeathsToRepeat;

    if (bAdvance && PlayLevel < MaxLevel)
    {
        PlayLevel++;
        LevelLine = "NEXT: LEVEL " $ PlayLevel $ " - " $ LevelTargets() $ " targets, faster, more zig-zag";
    }
    else if (!bAdvance)
    {
        LevelLine = "TOO MANY DEATHS - YOU PLAY LEVEL " $ PlayLevel $ " AGAIN";
    }
    else
    {
        LevelLine = "TOP LEVEL REACHED - YOU STAY AT LEVEL " $ PlayLevel;
    }

    SaveConfig();

    // SUMMARY

    if (PC != None)
        PC.ClientMessage("[AIM TARGETS] Round over - score " $ Score $ ", accuracy " $ Acc $ "%");

    if (HUD == None)
        return;

    HUD.ClearSummary();

    HUD.AddSummaryLine("ROUND " $ RoundNumber $ " COMPLETE  -  LEVEL " $ PlayedLevel, 1);

    Line = "SCORE: " $ Score $ "   (best " $ OldRecordScore $ ")";
    if (bNewScore)
        Line = Line $ "   NEW RECORD!";
    HUD.AddSummaryLine(Line, 0);

    Line = "ACCURACY: " $ Acc $ "%  (" $ ShotsHit $ "/" $ ShotsFired $ " shots)   (best " $ OldRecordAcc $ "%)";
    if (bNewAcc)
        Line = Line $ "   NEW RECORD!";
    HUD.AddSummaryLine(Line, 0);

    if (TimeCount > 0)
    {
        Line = "AVG TIME TO KILL A TARGET: " $ AvgMs $ " ms";
        if (OldRecordTime > 0)
            Line = Line $ "   (best " $ OldRecordTime $ " ms)";
        if (bNewTime)
            Line = Line $ "   NEW RECORD!";
        HUD.AddSummaryLine(Line, 0);
    }

    HUD.AddSummaryLine("TARGETS DESTROYED: " $ TargetsHit $ "   BEST STREAK: " $ BestStreak, 0);

    if (ShotsFired > 0)
    {
        HUD.AddSummaryLine(
            "SHOTS WHILE MOVING: " $ int(float(MovingShots) / float(ShotsFired) * 100.0) $ "%",
            0
        );
    }

    if (Bullseyes > 0 || ComboHits > 0)
        HUD.AddSummaryLine("BULLSEYES: " $ Bullseyes $ "   COMBO HITS: " $ ComboHits, 0);

    if (Deaths > 0)
    {
        HUD.AddSummaryLine(
            "DEATHS: " $ DeathsTouch $ " touched by a target, " $ DeathsStill $ " from standing still",
            3
        );
    }

    HUD.AddSummaryLine(TrendLine, TrendKind);

    if (bNewLevel)
        HUD.AddSummaryLine("LEVEL " $ PlayedLevel $ " - A NEW RECORD!", 2);

    if (bAdvance)
        HUD.AddSummaryLine(LevelLine, 2);
    else
        HUD.AddSummaryLine(LevelLine, 3);

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

    if (PC != None && PC.Pawn != None)
        StripWeapons(PC.Pawn);

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
            else if (RoundTimeLeft > 0 && RoundTimeLeft <= 5)
                HUD.ShowBanner("" $ RoundTimeLeft, 0.9);
        }

        // 5, 4, 3, 2, 1 with the announcer voice.
        if (RoundTimeLeft >= 1 && RoundTimeLeft <= 5)
            PlayCountdown(RoundTimeLeft);

        if (RoundTimeLeft <= 0)
            EndRound();
    }
    else if (bIntermission)
    {
        // Same countdown before the next round starts.
        if (IntermissionTimeLeft >= 1 && IntermissionTimeLeft <= 5)
        {
            PlayCountdown(IntermissionTimeLeft);

            if (HUD != None)
                HUD.ShowBanner("" $ IntermissionTimeLeft, 0.9);
        }

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

    if (PC == None)
        return;

    // Dead: wait a moment, then respawn.
    if (PC.Pawn == None || PC.Pawn.Health <= 0)
    {
        HandleDead();
        return;
    }

    if (bWasDead)
        OnRespawned();

    UpdateShots();
    CheckMisses();
    UpdateTargets(DeltaTime);
    UpdateStillDrain(DeltaTime);
}


// Counts the shots from the ammo consumed, then refills the ammo.
// The only exception is the Shock Rifle ball (alt fire): it is not a shot, it is
// only the setup of a combo.
function UpdateShots()
{
    local Weapon W;
    local WeaponFire Fire0;
    local WeaponFire Fire1;
    local WeaponFire Used_F;
    local bool bAlt;
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
        bAlt = Fire1 != None && Fire1.bIsFiring && (Fire0 == None || !Fire0.bIsFiring);

        if (bAlt && ShockRifle(W) != None)
        {
            Shots = 0;
        }
        else
        {
            if (bAlt)
                Used_F = Fire1;
            else
                Used_F = Fire0;

            Shots = Used;

            if (Used_F != None && Used_F.AmmoPerFire > 1)
                Shots = Max(1, Used / Used_F.AmmoPerFire);
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

        // A target that touches you kills you.
        if (bTouchKills && Level.TimeSeconds >= TouchGraceUntil && TouchesPlayer(T))
        {
            KillPlayer();
            return;
        }

        ChaseTarget(T, Delta);
    }

    // New targets come in one at a time, until the level's number is reached.
    if (Targets.Length < LevelTargets() && Level.TimeSeconds >= NextSpawnTry)
    {
        if (SpawnTarget())
            NextSpawnTry = Level.TimeSeconds + SpawnGap;
        else
            NextSpawnTry = Level.TimeSeconds + SpawnRetry;
    }
}


// The sphere (target) overlaps the body of the player.
function bool TouchesPlayer(AimTarget T)
{
    local Pawn P;
    local vector D;

    P = PC.Pawn;
    D = T.Location - P.Location;

    if (Abs(D.Z) > T.Radius + P.CollisionHeight)
        return False;

    D.Z = 0;

    return VSize(D) < T.Radius + P.CollisionRadius;
}


// The target flies at the player and zig-zags: the swerve and the speed grow with the level.
function ChaseTarget(AimTarget T, float Delta)
{
    local vector Dir;
    local vector Side;

    Dir = PC.Pawn.Location - T.Location;

    if (VSize(Dir) < 1.0)
        return;

    Dir = Normal(Dir);

    Side = vect(0,0,1) cross Dir;

    if (VSize(Side) < 0.01)
        Side = vect(1,0,0);
    else
        Side = Normal(Side);

    // New direction of the zig-zag.
    if (Level.TimeSeconds >= T.NextChange)
    {
        T.Sign = -T.Sign;
        T.Bob = FRand() * 2.0 - 1.0;
        T.NextChange = Level.TimeSeconds + LevelFlip() * (0.6 + FRand() * 0.8);
    }

    T.Vel = Normal(
        Dir
        + Side * T.Sign * LevelWeave()
        + vect(0,0,1) * T.Bob * LevelBob()
    ) * T.Speed;

    // Blocked by the level: slide sideways, or go up and over.
    if (!T.Move(T.Vel * Delta))
    {
        if (!T.Move(Side * T.Sign * T.Speed * Delta))
        {
            T.Sign = -T.Sign;
            T.Move(vect(0,0,1) * T.Speed * Delta);
        }
    }
}


// Spawns a target far away, in line of sight, in front of the player or to the sides.
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
    local float Rad;

    Eye = PC.Pawn.Location + PC.Pawn.EyePosition();
    Rad = TargetRadius();

    // Rotation units: 65536 = 360 degrees.
    Arc = int(SpawnAngle * 65536.0 / 360.0);

    for (Attempt = 0; Attempt < 20; Attempt++)
    {
        R.Yaw = PC.Rotation.Yaw + Rand(2 * Arc + 1) - Arc;
        R.Pitch = Rand(2 * PitchArc + 1) - PitchArc;
        R.Roll = 0;

        Cand = Eye + vector(R) * RandRange(1200.0, 2200.0);

        if (!FastTrace(Cand, Eye))
            continue;

        // Not on top of another target.
        bFree = True;

        for (i = 0; i < Targets.Length; i++)
        {
            if (Targets[i] != None && VSize(Targets[i].Location - Cand) < Rad * 4.0)
                bFree = False;
        }

        if (!bFree)
            continue;

        T = Spawn(class'AimTarget',,, Cand);

        if (T == None)
            continue;

        T.Trainer = Self;
        T.Setup(Rad, TargetMaterial);
        T.SpawnTime = Level.TimeSeconds;

        // A little variation so they do not all move in step.
        T.Speed = LevelSpeed() * (0.9 + FRand() * 0.2);

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

    if (Damage <= 0)
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

    // Every target goes down with the first hit.
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

    // The announcer calls the long streaks (Unstoppable...).
    CheckSpree();

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

    // The target is destroyed; the level's number of targets is topped up in the next ticks.

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
    if (Sender == None)
        return;

    if (Left(Cmd, 6) ~= "level ")
    {
        StartLevel = Clamp(int(Mid(Cmd, 6)), 1, MaxLevel);
        PlayLevel = StartLevel;
        SaveConfig();
        Sender.ClientMessage("[AIM TARGETS] Level " $ PlayLevel $ " (starts next round)");
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
        RecordScore = 0;
        RecordLevel = 0;
        RecordAccuracy = 0;
        RecordTime = 0;

        History.Length = 0;

        SaveConfig();
        Sender.ClientMessage("[AIM TARGETS] Personal records and history cleared.");
    }
    else
    {
        Sender.ClientMessage("[AIM TARGETS] mutate aim level <1-" $ MaxLevel $ ">   start from this level");
        Sender.ClientMessage("[AIM TARGETS] mutate aim summary   show the last round summary again");
        Sender.ClientMessage("[AIM TARGETS] mutate aim reset     clear records and history");
        Sender.ClientMessage(
            "[AIM TARGETS] Now: level " $ PlayLevel $ ", " $ LevelTargets() $ " targets, "
            $ int(LevelSpeed()) $ " units/s. Best level: " $ RecordLevel
        );
    }
}


defaultproperties
{
    GroupName="AimTargets"

    FriendlyName="Aim Targets"

    Description="Offline aim trainer: purple spheres fly at you and kill you if they touch you. Shoot them with the Shock Rifle or the Lightning Gun while you keep moving. Every round there are more of them, faster and with more zig-zag."

    HitSound=Sound'HitSound'

    RoundDuration=60
    BreakSeconds=20

    StartLevel=1
    MaxLevel=30
    Level1Targets=3
    MaxTargets=10
    Level1Speed=300.0
    SpeedPerLevel=40.0
    TopSpeed=750.0
    SpawnAngle=100.0
    DeathsToRepeat=3

    AllowedWeapons(0)="XWeapons.ShockRifle"
    AllowedWeapons(1)="XWeapons.SniperRifle"
    AllowedWeapons(2)="XWeapons.FlakCannon"
    AllowedWeapons(3)="XWeapons.RocketLauncher"

    TargetScale=0.7
    TargetSkin="UT2004Weapons.Shaders.PurpleShockShader"

    bHitSound=True
    HitSoundVolume=1.0
    bAnnouncer=True

    bStillDrain=True
    StillGraceSeconds=1.0
    StillDamagePerSecond=20.0
    MoveRegenPerSecond=3.0
    bStillCanKill=True

    bTouchKills=True
    RespawnDelay=1.5
}
