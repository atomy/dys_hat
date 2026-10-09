# Dystopia Hats (`dys_hats`)

A SourceMod plugin that gives [Dystopia](https://store.steampowered.com/app/17580/Dystopia/) players TF2-style hats
and a plush backpack. Hats are opt-in: nobody wears one until they pick it with `!hat`.

The hats are Half-Life 2 props that ship with Dystopia, so players download nothing and `sv_pure` is not affected.
No admin flag is needed to pick a hat. Optional TF2 hats can be shown to players who copy them from their own
Team Fortress 2 install (see [TF2 hats](#tf2-hats)).

| | |
|---|---|
| version | 1.3.0 |
| needs | SourceMod 1.11+ (Metamod:Source), SDKTools, SDKHooks; clientprefs optional (remembers choices) |
| tested on | Dystopia 1.5.8, Linux and Windows dedicated servers |

## Install

Copy the files into the server's `dystopia/addons/sourcemod/`:

| from this repo | to `addons/sourcemod/` |
|---|---|
| `plugins/dys_hats.smx` | `plugins/` |
| `configs/dys_hats.cfg` | `configs/` |
| `gamedata/sdktools.games/custom/game.dystopia.txt` | `gamedata/sdktools.games/custom/` (create `custom/`) |
| `configs/dys_hats_tf2.cfg` | `configs/` (only if you want [TF2 hats](#tf2-hats)) |

Restart the server afterwards: the gamedata file is only read when SDKTools loads.

Check: `sm plugins list` shows "Dystopia Hats (1.3.0)", the SourceMod log has
`[dys_hats.smx] Read 11 hat(s) and 8 setting(s) from configs/dys_hats.cfg, 0 TF2 hat(s) ...` (26 with the TF2
list), and there is no
`Error parsing gameconfig file` line.

### Why the gamedata file (it fixes all SourceMod plugins on Dystopia)

SourceMod's `gamedata/sdktools.games/game.dystopia.txt` is from an old Dystopia build. In Dystopia 1.5.8 its offsets
point at other functions: `AcceptEntityInput` called the slot before `CBaseEntity::AcceptInput` and `TeleportEntity`
called `CBaseEntity::EndTouch` (old 36 / 101, now 37 / 109 on Linux). Without the fix a hat is never attached to the
head (it stays at the map origin), and any other plugin using these natives misbehaves the same way.

The file in this repo corrects all 13 SDKTools offsets (`GiveNamedItem`, `RemovePlayerItem`, `Weapon_GetSlot`,
`Ignite`, `Extinguish`, `Teleport`, `CommitSuicide`, `GetVelocity`, `EyeAngles`, `AcceptInput`, `SetEntityModel`,
`WeaponEquip`, `Activate`). Linux values are the `CDYSPlayer` vtable slots read from the `server_srv.so` symbols.
Windows values are the same slots in `server.dll`, found through MSVC RTTI. 455 of 464 slots introduce the same class
on both platforms once shifted by the extra GCC destructor. The `CommitSuicide` overload order was confirmed from the
stack cleanup: `ret 8` for (bool, bool), `ret 0Ch` for the Vector version. SourceMod reads files in `custom/` after
its own, and a SourceMod update doesn't overwrite them. SDKHooks' Dystopia offsets are still correct (checked:
SetTransmit 21, OnTakeDamage 63, Think 48, Touch 100, Use 98, Weapon_* ...).

Careful: SourceMod's gamedata parser wants one key/value per line. A malformed file in `custom/` stops SDKTools from
loading, and every plugin that needs it fails ("Required extension SDKTools not running").

## Players

| chat / console | effect |
|---|---|
| `!hat` (`/hat`, `!hats`, `sm_hat`) | menu; it stays open on the same page, so you can try hats one after another |
| `!hat <id>` | wear that hat, e.g. `!hat melon` |
| `!hat off` (`none`) | no hat; `!hat default` = back to the server default |
| `!hat next` | the next hat |
| `!hat list` | the ids |
| `!hat show` / `!hat hide` | see your own hat (in third person) / hide it again (the default); per player, until you disconnect |
| `!hat tf2` | whether you see TF2 hats, and how to get them |
| `!plush` (`sm_plush`, `!plush on` / `off`) | wear / take off the plush backpack |
| `!plush show` / `!plush hide` | see your own plush (third person) / hide it from you again (default) |

The choice is stored with clientprefs (if that extension runs), so it survives reconnects and map changes.

Behaviour:
* You don't see your own hat in first person: it is not sent to you. Spectators watching you in first person don't
  see it either.
* The hat is hidden while you are cloaked (stealth implant, `m_iCamouflageAmount` > 0), so it never gives a stealther
  away. It is removed while you are jacked into cyberspace (the avatar model has no `eyes` attachment), and it comes
  back after the jack-out.
* On death the hat falls off as a physics prop. It is debris, so it collides with nothing but the world, nobody can
  pick it up, and it disappears after 8 s. It does not drop while you are cloaked.
* No collision and no hitbox: it changes nothing in the game.

### Plush backpack (`!plush`)

The heavy plush from dys_fortress (`models/twincannon/plush_heavy.mdl`, ships with the game) worn on the back:
scale 1.2 (34 u tall), from the waist to behind the head, its back against the wearer's back, its face looking
backwards. It is off until a player types `!plush` (stored with clientprefs like the hat), and it follows the same
rules as hats: hidden while cloaked, removed in cyberspace, falls off on death, not sent to its wearer
(`!plush show` / `!plush hide` per player, `sm_hats_hide_own 0` for everyone).

Placement per class model, from the bind pose: light and medium models carry it on the upper-chest bone (attachment
`katana`, it follows the torso), the heavies have only `eyes` (it follows the head a little when aiming up or down).
The back surface sits 7-8 u behind the spine on light / medium Punk models, 18 u on the medium Corp (gear) and 15-17 u
on heavies, so each model has its own offset. Tune live: `sm_plush_tune light_punk pos <x> <y> <z>`,
`... ang <p> <y> <r>`, `... att <attachment>`, `sm_plush_tune all scale <s>` (prints the line for the `plush` block).

## Settings and hat list (`configs/dys_hats.cfg`)

The file is read at every map start and by `sm_hats_reload`. Its `settings` block wins over `server.cfg` (which may
run before SourceMod loads its plugins). Changes made over rcon last until the next map.

| cvar | default | |
|---|---|---|
| `sm_hats_enabled` | 1 | |
| `sm_hats_default` | `none` | hat for players who never picked one (`none` = bare heads) |
| `sm_hats_tf2_fallback` | `cone` | HL2 hat that players without the TF2 files see on a TF2 hat that has no `"fallback"` of its own |
| `sm_hats_bots` | 0 | 0 = bots wear no hat, 1 = the default hat, 2 = a random hat per life |
| `sm_hats_drop` | 1 | hat falls off on death |
| `sm_hats_drop_time` | 8 | seconds a fallen hat stays |
| `sm_hats_hide_own` | 1 | don't send your own hat and plush to you (per player: `!hat show`, `!plush show`) |
| `sm_hats_debug` | 0 | log every equip / hide / drop |
| `sm_hats_plush` | 1 | players may wear the plush backpack (`!plush`) |
| `sm_hats_plush_bots` | 0 | 1 = bots wear it too |

Admin commands (flag `config`):

| command | |
|---|---|
| `sm_hats_reload` | re-read `configs/dys_hats.cfg` |
| `sm_hats_tune <id> pos <fwd> <left> <up>` / `ang <p> <y> <r>` / `scale <s>` | move every worn hat of that id at once; prints the line for `dys_hats.cfg` |
| `sm_plush_tune <player model\|default\|all> ...` | the same for the plush |
| `sm_hats_dump` | every player's hat, cyberspace and camouflage state, and the SetTransmit counters |
| `sm_hats_tf2view <client> <0\|1>` | treat a client as having the TF2 hat files or not (testing) |

Hats (menu order = file order):
`cone` Traffic cone, `bucket` Metal bucket, `pail` Plastic bucket, `pot` Cooking pot, `flowerpot` Flower pot,
`lampshade` Lamp shade, `melon` Watermelon, `milk` Milk carton, `can` Soda can, `hula` Hula doll,
`halo` Saw-blade halo. You can add more with any model in the game's VPKs/folders. A model the server can't find is
skipped with an error in the log. Optional per-hat keys: `"scale"` (m_flModelScale) and `"teamskins" "1"` (skin 0 for
Punks, skin 1 for Corps, for models with red/blue skins such as TF2 hats). A hat only falls off on death if its model
has a `.phy` collision model.

`pos` is "forward left up" in units from the player model's `eyes` attachment, and `ang` is "pitch yaw roll"
(roll 180 = upside down). The starting values come from the six class models' bind pose: in that frame the head's
centre is about 5 u behind the attachment and the top of the head 3-6 u above it, so every hat sits at
forward = -5. That's why the buckets and pots have roll 180 with the rim around the forehead.

If a hat sits wrong in game, adjust it live from the server console or rcon, e.g.:

```
sm_hats_tune cone pos -5 0 17        // moves every worn cone at once, prints the line for dys_hats.cfg
sm_hats_tune melon ang 0 90 0
sm_hats_tune halo scale 0.7
```

`sm_hats_dump` world positions come from the server's bone setup, which doesn't match the client animation (the
server puts the `eyes` attachment 15-22 u in front of the eye position), so judge the look in the game, not from
these numbers.

## TF2 hats

26 TF2 hats (Bill's Hat, Ellis' Cap, Ghastly Gibus, Tyrant's Helm, Stainless Pot, Killer's Kabuto, Max's Severed Head,
Officer's Ushanka, Fancy Fedora, Texas Ten Gallon, Pickelhaube, Brigade Helm, Santa Hat, ...), opt-in per player.
Nobody's files are handed out: the server and every player who wants them copy the hats from their OWN Team Fortress 2
install (TF2 is free) with `tools/tf2_hats.py`. Never put the TF2 files in a repo or on a FastDL server.

How it works: a TF2 hat is listed in `configs/dys_hats_tf2.cfg` (every hat there counts as `"tf2" "1"`). Its wearer
gets two entities: the TF2 model, sent only to players whose userinfo has `dys_tf2hats 1`, and an HL2 stand-in
(`"fallback"`, e.g. Bill's Hat -> Cooking pot), sent only to everyone else. Nobody sees an ERROR model. Death drops,
cloak hiding, cyberspace and `!hat show` work for both. Anyone may wear a TF2 hat; what a viewer sees depends only on
the viewer's files.

**Server** (needs Python 3 and a TF2 install on some PC):
```
python tools/tf2_hats.py --tf2 "<TF2 dir>" --out <folder> --cfg dys_hats_tf2.cfg
```
Copy `<folder>/models` to the server's `dystopia/download/models` (the server needs the models; `materials` is only
for players) and `dys_hats_tf2.cfg` to `addons/sourcemod/configs/`. The `configs/dys_hats_tf2.cfg` in this repo is
that file (offsets and model paths only, no TF2 content). Hats whose model the server can't find are skipped (one log
line each). With `sv_pure` 1/2, add `models\player\items\...`, `materials\models\player\items\...`,
`models\workshop\...` and `materials\models\workshop\...` as `allow_from_disk` to the server's
`pure_server_whitelist.txt`, or clients reject their own copies.

**Players** (Windows, Python 3 from python.org, TF2 installed):
1. Download [`tools/tf2_hats.py`](tools/tf2_hats.py) from this repo.
2. `python tf2_hats.py --tf2 "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2" --out "<Steam>/steamapps/common/Dystopia/dystopia/download"`
3. Add `setinfo dys_tf2hats 1` to `dystopia/cfg/autoexec.cfg` (or type it in the console before joining).

To remove: delete `dystopia/download/models/player/items`, `.../models/workshop`,
`dystopia/download/materials/models/player/items` and `.../materials/models/workshop` (all files are listed in
`dystopia/download/dys_hats_tf2_files.txt`).

How the offsets are computed (no guessing): TF2 bone-merges hats onto the player skeleton, so the tool maps the hat's
mesh onto the TF2 class model the hat was made for (first hat bone the class skeleton also has, e.g. `prp_helmet` or
`bip_head`). It takes TF2's `eyes` attachment (x forward, z up, as Dystopia's), and moves the TF2 head top (`head`
attachment) onto Dystopia's head top (-5.9 0 4.9 in the `eyes` frame, the mean of the six classes), +1.5 u lift. It
undoes the transform the hat prop itself plays (animation 0, frame 0). The engineer and pyro have no `eyes`
attachment: they use the soldier's offsets from the head bone. Hat models are MDL v48 (TF2 = Dystopia) and the VTFs
are 7.2-7.4. VMTs lose their `Proxies` block (TF2-only proxies such as ItemTintColor / invis), and paintable hats get
their default paint (`$colortint_base`) baked into `$color2`. Keep `scale` at 1 for TF2 hats: their model origin is
at the feet of the TF2 character (~78 u below the hat), so any scale moves them far off the head.

## Building

`build.bat [path\to\spcomp.exe]` (or set `SPCOMP`) compiles `scripting/dys_hats.sp` to `plugins/dys_hats.smx` with
SourceMod's spcomp 1.11+. It uses `scripting/include` if present, else the `include` folder next to spcomp.exe.
On Linux: `spcomp scripting/dys_hats.sp -i<sourcemod>/scripting/include -oplugins/dys_hats.smx`.

## Test status

Tested on Dystopia 1.5.8 with SourceMod 1.11.0.6970, on a Linux and a Windows dedicated server with bots, SourceTV
as the viewer for the SetTransmit checks:

| check | result |
|---|---|
| compile (spcomp 1.11) | 0 errors, 0 warnings |
| hats attach to `eyes` (attachment 4 on light/medium, 2 on heavy), offsets applied | OK with the gamedata fix (without it: attachment 0, hat at 0 0 0) |
| re-attach after a class change at respawn, after `sm_hats_tune`, after `sm_hats_bots` changes | OK |
| cloak: hidden while camouflaged, shown again after | OK (dys_vaccine) |
| death drop: props removed after 8 s | OK |
| cyberspace: removed at jack-in, back after jack-out | OK, 5 cycles (dys_cybernetic) |
| TF2 opt-in: TF2 hat sent only to viewers with the files, stand-in only to the others; both drop on death | OK |
| plush on all class models (`katana` / `eyes`), re-attach after `sm_plush_tune`, death drops | OK |
| Windows `CommitSuicide` (`sm_slay`) with the corrected offset | OK |
| SourceMod exceptions | 0 |

Not tested yet (needs a real game client): how the hats look, whether owners really never see their own hat, the menu
appearance (Dystopia has the `ShowMenu` user message, so SourceMod should use its numbered radio menus).

**Windows + SourceTV:** with SourceMod 1.11 loaded, a Windows dedicated server with `tv_enable 1` exits right after
the map activates (`DedicatedMain returned -1`). This also happens without dys_hats, and not without SourceMod; the
same setup on Linux runs fine. Don't enable SourceTV on a Windows server that runs SourceMod.

## License

GPLv3, like SourceMod itself. See [LICENSE](LICENSE).
