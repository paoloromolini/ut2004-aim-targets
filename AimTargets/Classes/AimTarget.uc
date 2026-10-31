// A flying sphere. Spawned, moved and scored by MutAimTargets.
class AimTarget extends Actor;

// Radius of ParticleMeshes.Simple.ParticleSphere2 (its bounding box is +-96).
const MeshRadius = 96.0;

var MutAimTargets Trainer;

var float Radius;
var float SpawnTime;
var bool bDead;

// Movement (driven by the trainer).
var float Speed;
var float Sign;             // which way it zig-zags (+1 / -1)
var float Bob;              // up / down swerve (-1 .. 1)
var float NextChange;
var vector Vel;

// Used when the skin set in the ini cannot be loaded.
var Material SkinFallback;


function Setup(float R, Material Skin)
{
    Radius = R;

    SetCollisionSize(R, R);
    SetDrawScale(R / MeshRadius);

    if (Skin != None)
        Skins[0] = Skin;
    else
        Skins[0] = SkinFallback;
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

    SkinFallback=Shader'XGameShaders.PlayerShaders.PlayerTrans'
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
