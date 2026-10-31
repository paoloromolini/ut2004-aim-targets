// A floating sphere to shoot at. Spawned, moved and scored by MutAimTargets.
class AimTarget extends Actor;

// Radius of ParticleMeshes.Simple.ParticleSphere2 (its bounding box is +-96).
const MeshRadius = 96.0;

var MutAimTargets Trainer;

var float Radius;
var float SpawnTime;
var float ExpireTime;
var bool bDead;

// Movement (driven by the trainer).
var float Speed;
var float Range;
var vector Anchor;
var vector Lateral;
var float Sign;
var float NextChange;
var vector Vel;

var Material SkinStill;
var Material SkinMoving;


function Setup(float R, bool bMoving)
{
    Radius = R;

    SetCollisionSize(R, R);
    SetDrawScale(R / MeshRadius);

    if (bMoving)
        Skins[0] = SkinMoving;
    else
        Skins[0] = SkinStill;
}


// Everything the weapons do to the target ends up here
// (beams, projectiles and splash damage such as the shock combo).
function TakeDamage(
    int Damage,
    Pawn EventInstigator,
    vector HitLocation,
    vector Momentum,
    class<DamageType> DamageType
)
{
    if (Trainer != None && !bDead)
        Trainer.TargetHit(Self, EventInstigator, Damage, HitLocation, DamageType);
}


defaultproperties
{
    DrawType=DT_StaticMesh
    StaticMesh=StaticMesh'ParticleMeshes.Simple.ParticleSphere2'

    SkinStill=Shader'XGameShaders.PlayerShaders.PlayerTrans'
    SkinMoving=Shader'XGameShaders.PlayerShaders.PlayerTransRed'
    Skins(0)=Shader'XGameShaders.PlayerShaders.PlayerTrans'

    Physics=PHYS_None
    RemoteRole=ROLE_None
    bMovable=True
    bUnlit=True

    CollisionRadius=48.0
    CollisionHeight=48.0
    bCollideActors=True
    bCollideWorld=True
    bBlockActors=False
    bBlockPlayers=False
    bProjTarget=True
    bBlockZeroExtentTraces=True
    bBlockNonZeroExtentTraces=True
    bUseCylinderCollision=True
}
