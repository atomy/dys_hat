// =============================================================================================
// Pink female "light punk" player model for Dystopia  --  models/player/light_punk_pink.mdl
//
// The player skin of the dys_hats plugin (!skin / !pink). It is a SIDE-BY-SIDE model: it does not replace the
// stock light_punk.mdl, the plugin switches opted-in Punk Light players to it.
// Build: build.bat in this folder (studiomdl of Source SDK Base 2013 Multiplayer, MDL v48 like Dystopia's player
// models) writes ..\..\content\models\player\light_punk_pink.* ; the materials are in ..\..\content\materials\.
//
// Derived from a Crowbar decompile of the stock light_punk QC. Differences from stock:
//   * body mesh = pink_reference.smd (new female mesh, 41 stock bones + 2 ponytail bones)
//   * no $lod / $shadowlod blocks (single full-detail mesh, ~8k tris)
//   * 3 materials: pink_body, pink_head, Dys_PunkBody_Light02 (stock gloves + boots)
//   * $cdmaterials / $texturegroup below (the 5 stock skin families: normal, thermal, headshot, thermal headshot,
//     predator, so the game's thermal / headshot / stealth skins keep working)
//   * $jigglebone x2 for the ponytail (tune in the JIGGLE TUNING section at the bottom)
// Everything else (attachments, hitboxes, bind-pose $definebone lines, $bonemerge, pose parameters, IK chains,
// ragdoll sequence, $includemodel for all animations, collision joints) is the stock QC verbatim. The stock
// physics mesh (light_punk_physics.smd) and ragdoll pose (light_punk_anims\ragdoll.smd) are from Dystopia's light_punk.
// =============================================================================================

$modelname "player/light_punk_pink.mdl"
$bodygroup "Urban"
{
	studio "pink_reference.smd"
}

$surfaceprop "flesh"

$contents "solid"

$illumposition -0.006 -2.448 34.815

// search order: our materials first, then the stock light_punk folder (gloves/boots, thermal, headshot_thermal),
// then models\player\ (predator stealth cloak)
$cdmaterials "models\player\light_punk_pink\"
$cdmaterials "models\player\light_punk\"
$cdmaterials "models\player\"

// skin families: 0 normal | 1 thermal | 2 headshot | 3 thermal headshot | 4 predator (stealth)
// columns: body, head, gloves+boots (the stock black ones, original UVs)
// family 3 uses pink_headshot_thermal (thermal blobs on the new head UVs, same opacity as pink_headshot)
$texturegroup "skinfamilies"
{
	{ "pink_body"           "pink_head"                 "Dys_PunkBody_Light02" }
	{ "Dys_PunkBody_therm"  "Dys_PunkHead_therm"        "Dys_PunkBody_therm"   }
	{ "pink_body"           "pink_headshot"             "Dys_PunkBody_Light02" }
	{ "Dys_PunkBody_therm"  "pink_headshot_thermal"     "Dys_PunkBody_therm"   }
	{ "predator"            "predator"                  "predator"             }
}

$attachment "primary" "ValveBiped.Bip01_Spine4" -17 3 -6 rotate 15 -20 0
$attachment "katana" "ValveBiped.Bip01_Spine4" 0 -6 4 rotate -20 -20 0
$attachment "neck" "ValveBiped.Bip01_Head1" 0 0 0 rotate 0 0 0
$attachment "eyes" "ValveBiped.Bip01_Head1" 3.3 -7.3 0 rotate 0 -90 -90

$cbox 0 0 0 0 0 0

$bbox -22.762 -10.539 -1.786 22.749 5.637 71.41

$hboxset "default"
$hbox 1 "ValveBiped.Bip01_Head1" -2.25 -6.5 -3.5 7.25 1.5 3.5
$hbox 4 "ValveBiped.Bip01_L_UpperArm" 0 -2.75 -2.75 12.51 1.75 2.25
$hbox 4 "ValveBiped.Bip01_L_Forearm" 0 -2.19 -2.38 13 1.81 1.62
$hbox 4 "ValveBiped.Bip01_L_Hand" 0.06 -2 -1.5 4.06 1 2.5
$hbox 5 "ValveBiped.Bip01_R_UpperArm" 0 -3 -2.25 12.39 2 2.75
$hbox 5 "ValveBiped.Bip01_R_Forearm" -0.5 -2.2 -1.55 12.5 1.8 2.45
$hbox 5 "ValveBiped.Bip01_R_Hand" 0.06 -2 -2.5 4.06 1 1.5
$hbox 6 "ValveBiped.Bip01_L_Thigh" 4.5 -2.75 -3.25 17.5 4.75 3.25
$hbox 6 "ValveBiped.Bip01_L_Calf" 0 -1.5 -3 15.64 5.5 3
$hbox 6 "ValveBiped.Bip01_L_Foot" -2.5 -1 -1.5 8.5 4 3.5
$hbox 7 "ValveBiped.Bip01_R_Thigh" 4.5 -2.75 -3.25 17.5 4.75 3.25
$hbox 7 "ValveBiped.Bip01_R_Calf" 0 -1.5 -3 15.64 5.5 3
$hbox 7 "ValveBiped.Bip01_R_Foot" -2.5 -1 -2.5 8.5 4 2.5
$hbox 3 "ValveBiped.Bip01_Pelvis" -7 -5.5 -5.5 7 8.5 4.5
$hbox 2 "ValveBiped.Bip01_Spine2" -4.5 -3 -8 8.5 9 8
$skipboneinbbox

// stock bind pose of the 41 stock bones (unchanged). The two ponytail bones need no $definebone:
// they are defined by the nodes/skeleton block of pink_reference.smd (parent ValveBiped.Bip01_Head1).
$definebone "ValveBiped.Bip01_Pelvis" "" 0 -1.132619 38.741383 0 0 89.999982 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Thigh" "ValveBiped.Bip01_Pelvis" 4.552066 0 0 1.995898 -88.6034 -90.127235 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Calf" "ValveBiped.Bip01_L_Thigh" 19.229235 0 0 0 9.235106 0 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Foot" "ValveBiped.Bip01_L_Calf" 16.651842 0 0.000001 -12.506524 -77.168823 -10.49269 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Toe0" "ValveBiped.Bip01_L_Foot" 6.169973 0 0 -1.588298 -21.925208 1.106612 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Thigh" "ValveBiped.Bip01_Pelvis" -4.552066 0 0 1.995898 -91.40625 -89.873132 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Calf" "ValveBiped.Bip01_R_Thigh" 19.056541 0 0 0 9.235106 0 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Foot" "ValveBiped.Bip01_R_Calf" 16.812616 -0.000001 0 12.506525 -77.168877 11.143227 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Toe0" "ValveBiped.Bip01_R_Foot" 6.229549 0.000002 0 1.345249 -21.940678 -6.218829 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_Spine" "ValveBiped.Bip01_Pelvis" 0 3.345131 -3.580906 4.766608 89.999982 89.999982 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_Spine1" "ValveBiped.Bip01_Spine" 3.995827 0 0 0 -2.833734 0 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_Spine2" "ValveBiped.Bip01_Spine1" 5.899929 0.000001 0 0 8.297403 0 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_Spine4" "ValveBiped.Bip01_Spine2" 6.289459 -0.000001 0 0 16.075475 0 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_Neck1" "ValveBiped.Bip01_Spine4" 3.643188 -0.000002 0 0 -3.607915 179.999855 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_Head1" "ValveBiped.Bip01_Neck1" 2.636375 0 0 0 12.859637 0 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Clavicle" "ValveBiped.Bip01_Spine4" 2.983047 2.468426 1.937661 -70.562561 -149.191166 50.99897 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_UpperArm" "ValveBiped.Bip01_L_Clavicle" 5.006035 0 -0.000002 -11.786886 -24.954089 -90.113486 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Forearm" "ValveBiped.Bip01_L_UpperArm" 12.399609 0.000001 -0.000011 0.000002 -13.773561 -0.000001 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Hand" "ValveBiped.Bip01_L_Forearm" 9.885498 -0.000002 -0.000034 7.896679 0.686405 85.248213 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Finger2" "ValveBiped.Bip01_L_Hand" 4.271812 0.088501 0.120656 -2.498209 -22.850357 5.159772 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Finger21" "ValveBiped.Bip01_L_Finger2" 1.768612 -0.000004 -0.000001 -7.179387 -23.222317 1.845039 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Finger22" "ValveBiped.Bip01_L_Finger21" 2.037243 0 0 -6.773502 -16.101485 -5.490885 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Finger1" "ValveBiped.Bip01_L_Hand" 4.145716 0.085503 1.102052 -9.256648 -27.200827 20.3655 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Finger11" "ValveBiped.Bip01_L_Finger1" 2.016329 0 -0.000001 -6.327687 -2.910227 0.000002 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Finger12" "ValveBiped.Bip01_L_Finger11" 1.601828 0 -0.000001 -17.713901 -11.012078 1.601303 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Finger0" "ValveBiped.Bip01_L_Hand" 0.961481 -0.494453 0.982206 -39.247951 -26.046259 -84.126818 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Finger01" "ValveBiped.Bip01_L_Finger0" 2.68388 -0.000004 -0.000004 20.069044 21.90469 5.313611 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_L_Finger02" "ValveBiped.Bip01_L_Finger01" 1.406315 0 -0.000004 6.500033 -5.230591 0.571123 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Clavicle" "ValveBiped.Bip01_Spine4" 2.983047 2.468424 -1.937661 70.562561 -149.191112 -55.220068 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_UpperArm" "ValveBiped.Bip01_R_Clavicle" 5.006041 0.000004 0.000003 13.539563 -24.090817 94.049478 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Forearm" "ValveBiped.Bip01_R_UpperArm" 12.297447 0 0 -0.000002 -13.773563 0 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Hand" "ValveBiped.Bip01_R_Forearm" 10.013632 0 0.000008 -7.891577 0.621543 -84.873843 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Finger2" "ValveBiped.Bip01_R_Hand" 4.567101 0.093792 -0.12961 3.648825 -34.418846 -3.982288 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Finger21" "ValveBiped.Bip01_R_Finger2" 2.4529 -0.000004 0.000002 7.760479 -24.728755 4.061351 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Finger22" "ValveBiped.Bip01_R_Finger21" 1.357212 0.000006 -0.000001 5.858199 -7.492172 -0.000002 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Finger1" "ValveBiped.Bip01_R_Hand" 4.428606 0.076885 -1.175364 7.583498 -20.546674 -9.092613 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Finger11" "ValveBiped.Bip01_R_Finger1" 2.136295 0.000004 0 6.798717 -22.750667 -0.69208 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Finger12" "ValveBiped.Bip01_R_Finger11" 1.360088 0.000004 0 16.880186 -19.34259 -5.39795 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Finger0" "ValveBiped.Bip01_R_Hand" 1.017908 -0.535065 -1.051176 33.371642 -25.951046 73.833279 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Finger01" "ValveBiped.Bip01_R_Finger0" 2.410522 0 0 -18.90366 7.033803 -3.285903 0 0 0 0 0 0
$definebone "ValveBiped.Bip01_R_Finger02" "ValveBiped.Bip01_R_Finger01" 1.428497 -0.000001 -0.000004 -16.207318 5.14007 -6.924416 0 0 0 0 0 0

$bonemerge "ValveBiped.Bip01_Pelvis"
$bonemerge "ValveBiped.Bip01_Spine"
$bonemerge "ValveBiped.Bip01_Spine1"
$bonemerge "ValveBiped.Bip01_Spine2"
$bonemerge "ValveBiped.Bip01_Spine4"
$bonemerge "ValveBiped.Bip01_L_Clavicle"
$bonemerge "ValveBiped.Bip01_L_UpperArm"
$bonemerge "ValveBiped.Bip01_L_Forearm"
$bonemerge "ValveBiped.Bip01_L_Hand"
$bonemerge "ValveBiped.Bip01_R_Clavicle"
$bonemerge "ValveBiped.Bip01_R_UpperArm"
$bonemerge "ValveBiped.Bip01_R_Forearm"
$bonemerge "ValveBiped.Bip01_R_Hand"

// =============================================================================================
// JIGGLE TUNING  --  ponytail, two flexible jigglebones. ALL tunable numbers live in this block.
//
//   Axis convention: the jiggle "length" axis is the bone's local +Z (jigglebones.cpp takes the forward
//   axis from matrix column 2); yaw/pitch are the two perpendicular swing axes. The rig export orients
//   pink_ponytail_1/2 so +Z points from the bone origin towards the next joint / the ponytail tip; the two
//   length lines below are the measured bone lengths.
//
//   length            distance from the bone origin to the simulated tip (units)  -> keep = bone segment length
//   tip_mass          small = light hair, barely sags under gravity
//   *_stiffness       spring constant back to the animated pose (higher = stiffer, ~1.5 Hz at 90)
//   *_damping         velocity damping (lower = more bouncy; ~2*sqrt(stiffness) would be critically damped)
//   angle_constraint  max total deflection of the tip in degrees (hard limit, prevents the strand folding through the head/back)
//   yaw/pitch_constraint  min max swing limits in degrees per axis
//   allow_length_flex NOT set  -> the strand cannot stretch along its axis
// =============================================================================================
$jigglebone "pink_ponytail_1"
{
	is_flexible
	{
		length 3.25
		tip_mass 3
		yaw_stiffness 90
		yaw_damping 5
		pitch_stiffness 90
		pitch_damping 5
		angle_constraint 40
		yaw_constraint -35 35
		yaw_friction 0
		yaw_bounce 0
		pitch_constraint -35 35
		pitch_friction 0
		pitch_bounce 0
	}
}

$jigglebone "pink_ponytail_2"
{
	is_flexible
	{
		length 7.70
		tip_mass 2
		yaw_stiffness 60
		yaw_damping 4
		pitch_stiffness 60
		pitch_damping 4
		angle_constraint 55
		yaw_constraint -50 50
		yaw_friction 0
		yaw_bounce 0
		pitch_constraint -50 50
		pitch_friction 0
		pitch_bounce 0
	}
}

$poseparameter "move_yaw" -180 180 loop 0
$poseparameter "body_pitch" -90 90 loop 0
$poseparameter "body_yaw" -90 90 loop 0

$ikchain "rhand" "ValveBiped.Bip01_R_Hand" knee 0.707 0.707 0
$ikchain "lhand" "ValveBiped.Bip01_L_Hand" knee 0.707 0.707 0
$ikchain "rfoot" "ValveBiped.Bip01_R_Foot" knee 0.707 -0.707 0
$ikchain "lfoot" "ValveBiped.Bip01_L_Foot" knee 0.707 -0.707 0

$sequence "ragdoll" {
	"light_punk_anims\ragdoll.smd"
	activity "ACT_DIERAGDOLL" 1
	fadein 0.2
	fadeout 0.2
	fps 30
	ikrule "rhand" release contact 0 fakeorigin 0 0 0 fakerotate 0 0 0 floor 0 height 0 radius 0 range 0 0 6 6 target 0
	ikrule "lhand" release contact 0 fakeorigin 0 0 0 fakerotate 0 0 0 floor 0 height 0 radius 0 range 0 0 6 6 target 1
	ikrule "rfoot" release contact 0 fakeorigin 0 0 0 fakerotate 0 0 0 floor 0 height 0 radius 0 range 0 0 6 6 target 2
	ikrule "lfoot" release contact 0 fakeorigin 0 0 0 fakerotate 0 0 0 floor 0 height 0 radius 0 range 0 0 6 6 target 3
}

$includemodel "player/light_shared.mdl"

$collisionjoints "light_punk_physics.smd"
{
	$mass 94
	$inertia 10
	$damping 0
	$rotdamping 0
	$rootbone "valvebiped.bip01_pelvis"

	$jointmassbias "ValveBiped.Bip01_Pelvis" 2.6

	$jointmassbias "ValveBiped.Bip01_Spine" 3
	$jointconstrain "ValveBiped.Bip01_Spine" x limit -8 8 0
	$jointconstrain "ValveBiped.Bip01_Spine" y limit -10 10 0
	$jointconstrain "ValveBiped.Bip01_Spine" z limit -15 30 0

	$jointmassbias "ValveBiped.Bip01_Spine2" 3.4
	$jointconstrain "ValveBiped.Bip01_Spine2" x limit -15 15 0
	$jointconstrain "ValveBiped.Bip01_Spine2" y limit -12 12 0
	$jointconstrain "ValveBiped.Bip01_Spine2" z limit -20 15 0

	$jointmassbias "ValveBiped.Bip01_L_UpperArm" 0.8
	$jointconstrain "ValveBiped.Bip01_L_UpperArm" x limit -40 40 0
	$jointconstrain "ValveBiped.Bip01_L_UpperArm" y limit -91 20 0
	$jointconstrain "ValveBiped.Bip01_L_UpperArm" z limit -80 23 0

	$jointmassbias "ValveBiped.Bip01_L_Forearm" 0.6
	$jointconstrain "ValveBiped.Bip01_L_Forearm" x limit 0 0 0
	$jointconstrain "ValveBiped.Bip01_L_Forearm" y limit 0 0 0
	$jointconstrain "ValveBiped.Bip01_L_Forearm" z limit -123 -3 0

	$jointmassbias "ValveBiped.Bip01_L_Hand" 0.2
	$jointconstrain "ValveBiped.Bip01_L_Hand" x limit -52 37 0
	$jointconstrain "ValveBiped.Bip01_L_Hand" y limit -12 8 0
	$jointconstrain "ValveBiped.Bip01_L_Hand" z limit -52 -1 0

	$jointmassbias "ValveBiped.Bip01_R_UpperArm" 0.8
	$jointconstrain "ValveBiped.Bip01_R_UpperArm" x limit -40 40 0
	$jointconstrain "ValveBiped.Bip01_R_UpperArm" y limit -20 91 0
	$jointconstrain "ValveBiped.Bip01_R_UpperArm" z limit -80 24 0

	$jointmassbias "ValveBiped.Bip01_R_Forearm" 0.6
	$jointconstrain "ValveBiped.Bip01_R_Forearm" x limit 0 0 0
	$jointconstrain "ValveBiped.Bip01_R_Forearm" y limit 0 0 0
	$jointconstrain "ValveBiped.Bip01_R_Forearm" z limit -120 -3 0

	$jointmassbias "ValveBiped.Bip01_R_Hand" 0.2
	$jointconstrain "ValveBiped.Bip01_R_Hand" x limit -60 60 0
	$jointconstrain "ValveBiped.Bip01_R_Hand" y limit -8 12 0
	$jointconstrain "ValveBiped.Bip01_R_Hand" z limit -52 -1 0

	$jointmassbias "ValveBiped.Bip01_R_Thigh" 1.3
	$jointconstrain "ValveBiped.Bip01_R_Thigh" x limit -12 12 0
	$jointconstrain "ValveBiped.Bip01_R_Thigh" y limit -8 33 0
	$jointconstrain "ValveBiped.Bip01_R_Thigh" z limit -79 24 0

	$jointmassbias "ValveBiped.Bip01_R_Calf" 0.8
	$jointconstrain "ValveBiped.Bip01_R_Calf" x limit 0 0 0
	$jointconstrain "ValveBiped.Bip01_R_Calf" y limit 0 0 0
	$jointconstrain "ValveBiped.Bip01_R_Calf" z limit -6 116 0

	$jointmassbias "ValveBiped.Bip01_R_Foot" 0.4
	$jointconstrain "ValveBiped.Bip01_R_Foot" x limit -17 10 0
	$jointconstrain "ValveBiped.Bip01_R_Foot" y limit -25 19 0
	$jointconstrain "ValveBiped.Bip01_R_Foot" z limit -15 35 0

	$jointmassbias "ValveBiped.Bip01_L_Thigh" 1.3
	$jointconstrain "ValveBiped.Bip01_L_Thigh" x limit -12 12 0
	$jointconstrain "ValveBiped.Bip01_L_Thigh" y limit -8 33 0
	$jointconstrain "ValveBiped.Bip01_L_Thigh" z limit -79 24 0

	$jointmassbias "ValveBiped.Bip01_L_Calf" 0.8
	$jointconstrain "ValveBiped.Bip01_L_Calf" x limit 0 0 0
	$jointconstrain "ValveBiped.Bip01_L_Calf" y limit 0 0 0
	$jointconstrain "ValveBiped.Bip01_L_Calf" z limit -6 116 0

	$jointmassbias "ValveBiped.Bip01_L_Foot" 0.4
	$jointconstrain "ValveBiped.Bip01_L_Foot" x limit -17 10 0
	$jointconstrain "ValveBiped.Bip01_L_Foot" y limit -25 19 0
	$jointconstrain "ValveBiped.Bip01_L_Foot" z limit -15 35 0

	$jointconstrain "ValveBiped.Bip01_Head1" x limit -72 60 0
	$jointconstrain "ValveBiped.Bip01_Head1" y limit -37 33 0
	$jointconstrain "ValveBiped.Bip01_Head1" z limit -19 45 0
}
