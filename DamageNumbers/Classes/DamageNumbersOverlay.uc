// Floating damage numbers drawn next to the crosshair (HUD overlay).
//
// The idea of showing damage as a pop-up number comes from HexedUT2k4
// (MIT, https://github.com/hexengraf/HexedUT2k4). This is an independent
// implementation.
class DamageNumbersOverlay extends HudOverlay config(DamageNumbers);

// Position of the number: 0.0 - 1.0 of the screen (the crosshair is at 0.5 / 0.5).
var config float PosX;
var config float PosY;

// Multiplier for the size of the numbers.
var config float TextScale;

// Also show the sum of the hits made in the last second.
var config bool bShowTotal;

const LifeTime = 1.1;
const FadeTime = 0.35;
const PopTime = 0.15;

// Hits closer than this are merged into one number (flak pellets, splash...).
const MergeWindow = 0.06;

// Hits closer than this are added to the total.
const TotalWindow = 1.2;

var int LastValue;
var float LastTime;
var bool bLastKill;

var int TotalValue;
var int TotalHits;
var float TotalTime;

var Font NumberFont;
var float FontForScreenY;


// =====================================================
// ACCESS (creates the overlay on demand)
// =====================================================

static function DamageNumbersOverlay GetFor(PlayerController PC)
{
    local int i;
    local DamageNumbersOverlay O;

    // Only the local player has a HUD.
    if (PC == None || PC.myHUD == None || Viewport(PC.Player) == None)
        return None;

    for (i = 0; i < PC.myHUD.Overlays.Length; i++)
    {
        O = DamageNumbersOverlay(PC.myHUD.Overlays[i]);

        if (O != None)
            return O;
    }

    O = PC.Spawn(class'DamageNumbersOverlay', PC.myHUD);

    if (O != None)
        PC.myHUD.AddHudOverlay(O);

    return O;
}


static function ShowFor(PlayerController PC, int Value, optional bool bKill)
{
    local DamageNumbersOverlay O;

    O = GetFor(PC);

    if (O != None)
        O.ShowDamage(Value, bKill);
}


// =====================================================
// DATA
// =====================================================

simulated function ShowDamage(int Value, bool bKill)
{
    local float Now;

    if (Value <= 0)
        return;

    Now = Level.TimeSeconds;

    if (LastValue > 0 && Now - LastTime < MergeWindow)
    {
        LastValue += Value;
        bLastKill = bLastKill || bKill;
    }
    else
    {
        LastValue = Value;
        bLastKill = bKill;
    }

    LastTime = Now;

    if (Now - TotalTime > TotalWindow)
    {
        TotalValue = 0;
        TotalHits = 0;
    }

    TotalValue += Value;
    TotalHits++;
    TotalTime = Now;
}


// =====================================================
// DRAWING
// =====================================================

simulated function SelectFont(Canvas C)
{
    if (C.ClipY == FontForScreenY && NumberFont != None)
        return;

    FontForScreenY = C.ClipY;

    if (C.ClipY >= 1000)
        NumberFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile37", class'Font'));
    else if (C.ClipY >= 700)
        NumberFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile29", class'Font'));
    else
        NumberFont = Font(DynamicLoadObject("UT2003Fonts.FontEurostile21", class'Font'));
}


simulated function Blend(
    out Color C, float T,
    int R0, int G0, int B0,
    int R1, int G1, int B1
)
{
    C.R = byte(float(R0) + float(R1 - R0) * T);
    C.G = byte(float(G0) + float(G1 - G0) * T);
    C.B = byte(float(B0) + float(B1 - B0) * T);
}


// White -> yellow -> orange -> red -> purple as the damage grows.
simulated function Color DamageColor(int Value)
{
    local Color C;

    if (Value < 20)
        Blend(C, float(Value) / 20.0, 255, 255, 255, 255, 255, 32);
    else if (Value < 45)
        Blend(C, float(Value - 20) / 25.0, 255, 255, 32, 255, 119, 32);
    else if (Value < 75)
        Blend(C, float(Value - 45) / 30.0, 255, 119, 32, 255, 32, 32);
    else
        Blend(C, FMin(1.0, float(Value - 75) / 35.0), 255, 32, 32, 143, 32, 245);

    return C;
}


simulated function DrawNumber(
    Canvas C, int Value, float Scale, float X, float Y,
    Color Col, int Alpha
)
{
    local float XL;
    local float YL;
    local string S;

    S = "" $ Value;

    C.Font = NumberFont;
    C.FontScaleX = Scale * TextScale;
    C.FontScaleY = C.FontScaleX;
    C.StrLen(S, XL, YL);

    X = (C.ClipX - XL) * X;
    Y = (C.ClipY - YL) * Y;

    // Shadow.
    C.DrawColor.R = 0;
    C.DrawColor.G = 0;
    C.DrawColor.B = 0;
    C.DrawColor.A = Alpha;
    C.SetPos(X + 2.0, Y + 2.0);
    C.DrawText(S);

    C.DrawColor = Col;
    C.DrawColor.A = Alpha;
    C.SetPos(X, Y);
    C.DrawText(S);
}


simulated function Render(Canvas C)
{
    local float Now;
    local float Age;
    local float Scale;
    local float Rise;
    local float SavedScaleX;
    local float SavedScaleY;
    local int Alpha;
    local Color Col;

    Now = Level.TimeSeconds;

    if (LastValue <= 0 && TotalHits <= 0)
        return;

    SelectFont(C);

    SavedScaleX = C.FontScaleX;
    SavedScaleY = C.FontScaleY;

    // LAST HIT (pops up, floats up and fades)

    Age = Now - LastTime;

    if (LastValue > 0 && Age < LifeTime)
    {
        Scale = 0.8 + 0.8 * FMin(1.0, float(LastValue) / 110.0);

        if (Age < PopTime)
            Scale = Scale * (1.0 + 0.5 * (1.0 - Age / PopTime));

        Rise = FMin(Age, 0.6) * 0.06;

        if (bLastKill)
        {
            Col.R = 255;
            Col.G = 64;
            Col.B = 64;
            Scale = Scale * 1.25;
        }
        else
        {
            Col = DamageColor(LastValue);
        }

        Alpha = 255;

        if (LifeTime - Age < FadeTime)
            Alpha = Clamp(int((LifeTime - Age) / FadeTime * 255.0), 0, 255);

        DrawNumber(C, LastValue, Scale, PosX, PosY - Rise, Col, Alpha);
    }

    // TOTAL of the last second (only when there was more than one hit)

    Age = Now - TotalTime;

    if (bShowTotal && TotalHits > 1 && Age < TotalWindow)
    {
        Alpha = 255;

        if (TotalWindow - Age < FadeTime)
            Alpha = Clamp(int((TotalWindow - Age) / FadeTime * 255.0), 0, 255);

        DrawNumber(C, TotalValue, 0.7, PosX, PosY + 0.07, DamageColor(TotalValue), Alpha);
    }

    C.FontScaleX = SavedScaleX;
    C.FontScaleY = SavedScaleY;
}


defaultproperties
{
    PosX=0.5
    PosY=0.40
    TextScale=1.0
    bShowTotal=True
}
