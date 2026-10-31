// HUD of the aim trainer: stats panel, banners, hit feedback and round summary.
class AimTargetsOverlay extends HudOverlay config(AimTargets);

// Multiplier for every text on screen. Raise it if the text is too small.
var config float TextScale;

var MutAimTargets Trainer;

var Font NormalFont;
var Font BigFont;
var float BigScale;
var float FontForScreenY;

var string BannerText;
var float BannerUntil;

var string FeedText;
var float FeedUntil;

var array<string> SummaryLines;
var array<int> SummaryKinds;    // 0 white, 1 gold, 2 green, 3 red
var float SummaryUntil;


// =====================================================
// API USED BY THE TRAINER
// =====================================================

simulated function ShowBanner(string Text, float Seconds)
{
    BannerText = Text;
    BannerUntil = Level.TimeSeconds + Seconds;
}


simulated function ShowFeed(string Text, float Seconds)
{
    FeedText = Text;
    FeedUntil = Level.TimeSeconds + Seconds;
}


simulated function ClearSummary()
{
    SummaryLines.Length = 0;
    SummaryKinds.Length = 0;
}


simulated function AddSummaryLine(string Text, int Kind)
{
    local int i;

    i = SummaryLines.Length;
    SummaryLines.Length = i + 1;
    SummaryKinds.Length = i + 1;

    SummaryLines[i] = Text;
    SummaryKinds[i] = Kind;
}


// =====================================================
// DRAWING HELPERS
// =====================================================

simulated function SelectFonts(Canvas C)
{
    if (C.ClipY == FontForScreenY && NormalFont != None)
        return;

    FontForScreenY = C.ClipY;

    if (C.ClipY >= 1300)
    {
        NormalFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile37", class'Font'));
        BigFont = NormalFont;
        BigScale = 1.7;
    }
    else if (C.ClipY >= 900)
    {
        NormalFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile29", class'Font'));
        BigFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile37", class'Font'));
        BigScale = 1.3;
    }
    else if (C.ClipY >= 700)
    {
        NormalFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile24", class'Font'));
        BigFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile29", class'Font'));
        BigScale = 1.2;
    }
    else
    {
        NormalFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile17", class'Font'));
        BigFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile24", class'Font'));
        BigScale = 1.2;
    }
}


// Draws one line and returns its height.
simulated function float DrawLine(
    Canvas C, string S, float X, float Y, bool bCenter, bool bBig,
    byte R, byte G, byte B, int Alpha
)
{
    local float XL;
    local float YL;

    if (bBig)
    {
        C.Font = BigFont;
        C.FontScaleX = BigScale * TextScale;
    }
    else
    {
        C.Font = NormalFont;
        C.FontScaleX = TextScale;
    }

    C.FontScaleY = C.FontScaleX;
    C.StrLen(S, XL, YL);

    if (bCenter)
        X -= XL * 0.5;

    // Shadow.
    C.DrawColor.R = 0;
    C.DrawColor.G = 0;
    C.DrawColor.B = 0;
    C.DrawColor.A = Alpha;
    C.SetPos(X + 2.0, Y + 2.0);
    C.DrawText(S);

    C.DrawColor.R = R;
    C.DrawColor.G = G;
    C.DrawColor.B = B;
    C.DrawColor.A = Alpha;
    C.SetPos(X, Y);
    C.DrawText(S);

    return YL * 1.1;
}


// =====================================================
// MAIN DRAW
// =====================================================

simulated function Render(Canvas C)
{
    local float SavedScaleX;
    local float SavedScaleY;
    local Font SavedFont;

    if (Trainer == None)
        return;

    SelectFonts(C);

    SavedScaleX = C.FontScaleX;
    SavedScaleY = C.FontScaleY;
    SavedFont = C.Font;

    DrawPanel(C);
    DrawMessages(C);
    DrawSummary(C);

    C.FontScaleX = SavedScaleX;
    C.FontScaleY = SavedScaleY;
    C.Font = SavedFont;
}


simulated function DrawPanel(Canvas C)
{
    local float X;
    local float Y;

    X = C.ClipX * 0.015;
    Y = C.ClipY * 0.25;

    Y += DrawLine(
        C, "LEVEL " $ Trainer.PlayLevel $ "   (" $ Trainer.LevelTargets() $ " targets)",
        X, Y, False, False, 255, 215, 0, 255
    );

    if (Trainer.bRoundActive)
        Y += DrawLine(C, "TIME  " $ Trainer.FormatTime(Trainer.RoundTimeLeft), X, Y, False, False, 255, 255, 255, 255);
    else if (Trainer.bIntermission)
        Y += DrawLine(C, "NEXT ROUND IN  " $ Trainer.IntermissionTimeLeft, X, Y, False, False, 120, 220, 255, 255);

    if (!Trainer.bRoundActive)
        return;

    Y += DrawLine(C, "SCORE  " $ Trainer.Score, X, Y, False, False, 255, 255, 255, 255);
    Y += DrawLine(C, "ACCURACY  " $ Trainer.AccuracyPct() $ "%", X, Y, False, False, 255, 255, 255, 255);

    if (Trainer.Streak > 1)
        Y += DrawLine(C, "STREAK  " $ Trainer.Streak, X, Y, False, False, 255, 150, 0, 255);

    if (Trainer.DeathsTouch + Trainer.DeathsStill > 0)
        Y += DrawLine(C, "DEATHS  " $ (Trainer.DeathsTouch + Trainer.DeathsStill), X, Y, False, False, 255, 90, 90, 255);

    if (Trainer.TimeCount > 0)
        Y += DrawLine(C, "TIME TO KILL  " $ Trainer.AvgTimeMs() $ " ms", X, Y, False, False, 255, 255, 255, 255);

    if (Trainer.RecordScore > 0)
        Y += DrawLine(C, "BEST  " $ Trainer.RecordScore, X, Y, False, False, 160, 160, 160, 255);
}


simulated function DrawMessages(Canvas C)
{
    local float Now;
    local int Alpha;

    Now = Level.TimeSeconds;

    // Banner (round start, countdown...)
    if (Now < BannerUntil)
        DrawLine(C, BannerText, C.ClipX * 0.5, C.ClipY * 0.14, True, True, 255, 255, 255, 255);

    // Points of the last hit, under the crosshair.
    if (Now < FeedUntil)
    {
        Alpha = Clamp(int((FeedUntil - Now) * 2.0 * 255.0), 0, 255);
        DrawLine(C, FeedText, C.ClipX * 0.5, C.ClipY * 0.58, True, False, 255, 215, 0, Alpha);
    }

    // Standing still: health is draining.
    if (Trainer.bDraining)
        DrawLine(C, "KEEP MOVING!", C.ClipX * 0.5, C.ClipY * 0.66, True, True, 255, 40, 40, 255);
}


simulated function DrawSummary(Canvas C)
{
    local int i;
    local float Y;

    if (Level.TimeSeconds > SummaryUntil || SummaryLines.Length == 0)
        return;

    Y = C.ClipY * 0.18;

    for (i = 0; i < SummaryLines.Length; i++)
    {
        if (SummaryKinds[i] == 1)
            Y += DrawLine(C, SummaryLines[i], C.ClipX * 0.5, Y, True, False, 255, 215, 0, 255);
        else if (SummaryKinds[i] == 2)
            Y += DrawLine(C, SummaryLines[i], C.ClipX * 0.5, Y, True, False, 90, 255, 120, 255);
        else if (SummaryKinds[i] == 3)
            Y += DrawLine(C, SummaryLines[i], C.ClipX * 0.5, Y, True, False, 255, 90, 90, 255);
        else
            Y += DrawLine(C, SummaryLines[i], C.ClipX * 0.5, Y, True, False, 255, 255, 255, 255);
    }
}


defaultproperties
{
    TextScale=1.0
}
