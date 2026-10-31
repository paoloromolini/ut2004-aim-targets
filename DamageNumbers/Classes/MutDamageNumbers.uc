// Shows the damage you deal as pop-up numbers. Settings: System/DamageNumbers.ini
class MutDamageNumbers extends Mutator;

function PostBeginPlay()
{
    local DamageNumbersRules Rules;

    Super.PostBeginPlay();

    if (Level.Game != None)
    {
        Rules = Spawn(class'DamageNumbersRules');

        if (Rules != None)
        {
            if (Level.Game.GameRulesModifiers == None)
                Level.Game.GameRulesModifiers = Rules;
            else
                Level.Game.GameRulesModifiers.AddGameRules(Rules);
        }
    }

    SetTimer(1.0, True);
}


// Creates the overlay as soon as the HUD exists, so the settings are loaded
// before the first hit.
function Timer()
{
    local Controller C;
    local PlayerController PC;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        PC = PlayerController(C);

        if (PC != None)
            class'DamageNumbersOverlay'.static.GetFor(PC);
    }
}


defaultproperties
{
    GroupName="DamageNumbers"

    FriendlyName="Damage Numbers"

    Description="Pop-up numbers that show the damage you deal."
}
