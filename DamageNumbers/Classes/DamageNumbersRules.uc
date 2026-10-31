class DamageNumbersRules extends GameRules;

function int NetDamage(
    int OriginalDamage,
    int Damage,
    Pawn Injured,
    Pawn InstigatedBy,
    vector HitLocation,
    out vector Momentum,
    class<DamageType> DamageType
)
{
    local PlayerController PC;

    // Preserve the other GameRules in the chain.
    Damage = Super.NetDamage(
        OriginalDamage,
        Damage,
        Injured,
        InstigatedBy,
        HitLocation,
        Momentum,
        DamageType
    );

    if (Damage <= 0 || Injured == None || InstigatedBy == None)
        return Damage;

    if (Injured == InstigatedBy)
        return Damage;

    PC = PlayerController(InstigatedBy.Controller);

    if (PC == None)
        return Damage;

    // No numbers for friendly fire.
    if (Injured.Controller != None && Injured.Controller.SameTeamAs(PC))
        return Damage;

    class'DamageNumbersOverlay'.static.ShowFor(PC, Damage, Injured.Health <= Damage);

    return Damage;
}


defaultproperties
{
}
