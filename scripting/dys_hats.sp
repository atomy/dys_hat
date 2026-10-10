/**
 * dys_hats - TF2-style hats for Dystopia (SourceMod plugin).
 *
 * Players pick a hat with !hat (nobody wears one by default: sm_hats_default "none").
 * The hats are Half-Life 2 props that ship with Dystopia, so nobody downloads anything and
 * sv_pure is not affected. The hat list lives in addons/sourcemod/configs/dys_hats.cfg.
 *
 *   !hat             menu (also /hat, !hats, sm_hat in the console)
 *   !hat <id>        wear that hat, e.g. !hat melon
 *   !hat off         no hat
 *   !hat next        try the next hat
 *   !hat list        print the hat ids
 *   !hat show / hide see your own hat (third person) / hide it again (default)
 *   !plush           wear / take off the plush backpack (the heavy plush from dys_fortress)
 *   !plush show      see your own plush (hidden from you by default: it clips into the first-person view)
 *   !hat tf2         how to see TF2 hats (players who set "setinfo dys_tf2hats 1" get the TF2 models,
 *                    everyone else sees an HL2 stand-in; the TF2 list is configs/dys_hats_tf2.cfg)
 *
 *   !skin            player model menu (opt-in, remembered): !skin <id> | off | list
 *   !pink            switch the Pink Light Punk on / off (only while you play Punk Light)
 *
 * Hats are hidden while the wearer is cloaked (stealth implant) and while jacked into
 * cyberspace, you don't see your own hat in first person, and a hat falls off when its
 * wearer dies.
 *
 * Player skins (the "skins" block of the config) are the one thing players download: the
 * server puts the model and its materials in the download table. A skin replaces only its
 * "base" model (models/player/light_punk.mdl for the pink one); other classes and the
 * cyberspace avatar are never touched.
 *
 * Copyright (C) 2026 atomy - https://github.com/atomy/dys_hat
 * This program is free software: you can redistribute it and/or modify it under the terms of
 * the GNU General Public License as published by the Free Software Foundation, either version 3
 * of the License, or (at your option) any later version. It is distributed WITHOUT ANY
 * WARRANTY; see <https://www.gnu.org/licenses/>.
 */
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_EXTENSIONS
#include <clientprefs>
#define REQUIRE_EXTENSIONS

#define PLUGIN_VERSION "1.4.0"
#define MAX_PLUSH_MODELS 16
#define MAX_HATS 64
#define MAX_SKINS 16
#define MAX_EDICTS 2048
#define EF_NODRAW 0x020
#define OBS_MODE_IN_EYE 4
#define CHOICE_DEFAULT -2
#define CHOICE_NONE -1
#define KIND_ANY 0
#define KIND_TF2 1
#define KIND_FALLBACK 2
#define PREFIX "\x04[Hats]\x01"

public Plugin myinfo =
{
	name = "Dystopia Hats",
	author = "atomy",
	description = "TF2-style hats: !hat picks a prop to wear on your head, !skin a player model",
	version = PLUGIN_VERSION,
	url = "https://github.com/atomy/dys_hat"
};

ConVar g_cvEnabled;
ConVar g_cvDefault;
ConVar g_cvBots;
ConVar g_cvDrop;
ConVar g_cvDropTime;
ConVar g_cvHideOwn;
ConVar g_cvDebug;
ConVar g_cvPlush;
ConVar g_cvPlushBots;
ConVar g_cvTf2Fallback;
ConVar g_cvSkins;
ConVar g_cvSkinDefault;
ConVar g_cvSkinBots;

Handle g_Cookie = null;
Handle g_PlushCookie = null;
Handle g_SkinCookie = null;
bool g_Late;

// hat definitions (configs/dys_hats.cfg, or the built-in list below)
char g_HatId[MAX_HATS][32];
char g_HatName[MAX_HATS][64];
char g_HatModel[MAX_HATS][PLATFORM_MAX_PATH];
float g_HatPos[MAX_HATS][3];   // forward, left, up from the player model's "eyes" attachment
float g_HatAng[MAX_HATS][3];   // pitch, yaw, roll relative to that attachment
float g_HatScale[MAX_HATS];
bool g_HatTeamSkins[MAX_HATS];  // "teamskins": skin 0 for Punks, skin 1 for Corps (models with red/blue skins, e.g. TF2 hats)
bool g_HatHasPhysics[MAX_HATS]; // a .phy exists: the hat can fall off as a physics prop
bool g_HatTf2[MAX_HATS];        // "tf2": only players with the TF2 files see it ("setinfo dys_tf2hats 1")
char g_HatFallback[MAX_HATS][32]; // "fallback": the hat everyone else sees instead (else sm_hats_tf2_fallback)
int g_HatCount;

// plush backpack (the "plush" block of configs/dys_hats.cfg, or the built-in table)
char g_PlushModel[PLATFORM_MAX_PATH];
float g_PlushScale;
bool g_PlushOk;                                          // the model exists on this server
char g_PlushFor[MAX_PLUSH_MODELS][PLATFORM_MAX_PATH];    // player model, or "default"
char g_PlushAtt[MAX_PLUSH_MODELS][32];                   // attachment of that model ("" = the player origin)
float g_PlushPos[MAX_PLUSH_MODELS][3];
float g_PlushAng[MAX_PLUSH_MODELS][3];
int g_PlushCount;

// player skins (the "skins" block of configs/dys_hats.cfg, or the built-in pink one); only skins whose model exists
char g_SkinId[MAX_SKINS][32];
char g_SkinName[MAX_SKINS][64];
char g_SkinClass[MAX_SKINS][32];                         // shown to players, e.g. "Punk Light"
char g_SkinModel[MAX_SKINS][PLATFORM_MAX_PATH];
char g_SkinBase[MAX_SKINS][PLATFORM_MAX_PATH];           // the stock model it replaces (and only that one)
char g_SkinMaterials[MAX_SKINS][PLATFORM_MAX_PATH];      // folder whose files go to the download table
int g_SkinCount;
StringMap g_LiveModels;   // skin models that were in the download table when this map started (lowercase path)
bool g_SkinsBlocked;      // late load with players in the game: they have no skin files until the next map
char g_SkinExt[][] = { ".vvd", ".dx90.vtx", ".dx80.vtx", ".sw.vtx", ".phy" };

// per player
int g_Choice[MAXPLAYERS + 1];                           // CHOICE_DEFAULT, CHOICE_NONE or a hat index
int g_BotHat[MAXPLAYERS + 1];                           // random pick of a bot (sm_hats_bots 2)
int g_HatRef[MAXPLAYERS + 1];                           // entity reference of the worn hat
int g_HatWorn[MAXPLAYERS + 1];                          // hat index of the worn hat
char g_WornOnModel[MAXPLAYERS + 1][PLATFORM_MAX_PATH];  // player model the hat was attached to
float g_SpawnTime[MAXPLAYERS + 1];
bool g_ShowOwn[MAXPLAYERS + 1];                         // !hat show: this player sees their own hat
bool g_ShowOwnPlush[MAXPLAYERS + 1];                    // !plush show: this player sees their own plush
bool g_EntPlush[MAX_EDICTS + 1];                        // a worn plush (else a hat), for Hook_SetTransmit
bool g_PlushOn[MAXPLAYERS + 1];                         // !plush
int g_PlushRef[MAXPLAYERS + 1];
char g_PlushOnModel[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

bool g_ViewerTf2[MAXPLAYERS + 1];                       // userinfo dys_tf2hats 1: this player has the TF2 hat files
int g_FallbackRef[MAXPLAYERS + 1];                      // the stand-in entity of a worn TF2 hat

char g_SkinChoice[MAXPLAYERS + 1][32];                  // "" = sm_hats_skin_default, "none" or a skin id (also unknown ones)
char g_SkinForce[MAXPLAYERS + 1][32];                   // sm_skin_force: "" = no override, "none" or a skin id

int g_EntOwner[MAX_EDICTS + 1];                         // hat entity -> wearer
int g_EntKind[MAX_EDICTS + 1];                          // KIND_TF2: only to TF2 viewers, KIND_FALLBACK: only to the others
int g_TransmitCalls;
int g_TransmitHidden;
int g_KindBlocked[3];                                   // SetTransmit refusals by KIND_*

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_Late = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_hats_version", PLUGIN_VERSION, "Dystopia Hats version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_hats_enabled", "1", "1 = players wear hats", _, true, 0.0, true, 1.0);
	g_cvDefault = CreateConVar("sm_hats_default", "none", "Hat id for players who never picked one (\"none\" = no hat)");
	g_cvBots = CreateConVar("sm_hats_bots", "0", "Bots: 0 = no hat, 1 = the default hat, 2 = a random hat", _, true, 0.0, true, 2.0);
	g_cvDrop = CreateConVar("sm_hats_drop", "1", "1 = the hat falls off when its wearer dies", _, true, 0.0, true, 1.0);
	g_cvDropTime = CreateConVar("sm_hats_drop_time", "8", "Seconds a fallen hat stays on the floor", _, true, 1.0, true, 60.0);
	g_cvHideOwn = CreateConVar("sm_hats_hide_own", "1", "1 = your own hat and plush are not sent to you (they clip into the first-person view; !hat show / !plush show per player)", _, true, 0.0, true, 1.0);
	g_cvDebug = CreateConVar("sm_hats_debug", "0", "1 = log every hat change", _, true, 0.0, true, 1.0);
	g_cvPlush = CreateConVar("sm_hats_plush", "1", "1 = players can wear the plush backpack with !plush", _, true, 0.0, true, 1.0);
	g_cvPlushBots = CreateConVar("sm_hats_plush_bots", "0", "1 = bots wear the plush backpack", _, true, 0.0, true, 1.0);
	g_cvTf2Fallback = CreateConVar("sm_hats_tf2_fallback", "cone", "HL2 hat id shown instead of a TF2 hat to players without the TF2 files (TF2 hats without their own \"fallback\")");
	g_cvSkins = CreateConVar("sm_hats_skins", "1", "1 = players may use player skins (!skin, !pink); the skin files go to the download table", _, true, 0.0, true, 1.0);
	g_cvSkinDefault = CreateConVar("sm_hats_skin_default", "none", "Skin id for players who never picked one (\"none\" = the stock models)");
	g_cvSkinBots = CreateConVar("sm_hats_skins_bots", "0", "Bots: 0 = never a skin, 1 = the default skin (sm_hats_skin_default)", _, true, 0.0, true, 1.0);
	g_LiveModels = new StringMap();

	RegConsoleCmd("sm_hat", Cmd_Hat, "!hat: hat menu; !hat <id> | off | next | list | show | hide | tf2");
	RegConsoleCmd("sm_hats", Cmd_Hat, "Same as sm_hat");
	RegConsoleCmd("sm_plush", Cmd_Plush, "!plush: wear / take off the plush backpack; !plush on | off");
	RegAdminCmd("sm_plush_tune", Cmd_PlushTune, ADMFLAG_CONFIG, "sm_plush_tune <player model|default> pos <x> <y> <z> | ang <p> <y> <r> | att <attachment> | scale <s>");
	RegAdminCmd("sm_hats_reload", Cmd_Reload, ADMFLAG_CONFIG, "Reload configs/dys_hats.cfg");
	RegAdminCmd("sm_hats_tune", Cmd_Tune, ADMFLAG_CONFIG, "sm_hats_tune <id> pos <fwd> <left> <up> | ang <pitch> <yaw> <roll> | scale <s>: adjust a hat live");
	RegAdminCmd("sm_hats_dump", Cmd_Dump, ADMFLAG_CONFIG, "Print where every worn hat sits (debug)");
	RegAdminCmd("sm_hats_tf2view", Cmd_Tf2View, ADMFLAG_CONFIG, "sm_hats_tf2view <client index> <0|1>: treat a client as having the TF2 hat files or not (test)");
	RegConsoleCmd("sm_skin", Cmd_Skin, "!skin: player model menu; !skin <id> | off | list");
	RegConsoleCmd("sm_pink", Cmd_Pink, "!pink: switch the Pink Light Punk skin on / off");
	RegAdminCmd("sm_skin_force", Cmd_SkinForce, ADMFLAG_CONFIG, "sm_skin_force <target> <id|off|reset>: set the skin of any player, bots too (test what others see)");

	HookEventEx("player_spawn", Event_Spawn);
	HookEventEx("player_death", Event_Death);
	HookEventEx("player_team", Event_Team);

	if (GetExtensionFileStatus("clientprefs.ext") == 1)
	{
		g_Cookie = RegClientCookie("dys_hats", "Dystopia Hats: chosen hat", CookieAccess_Protected);
		g_PlushCookie = RegClientCookie("dys_hats_plush", "Dystopia Hats: plush backpack on", CookieAccess_Protected);
		g_SkinCookie = RegClientCookie("dys_hats_skin", "Dystopia Hats: chosen player skin", CookieAccess_Protected);
	}

	for (int i = 1; i <= MaxClients; i++)
		ResetClient(i);

	LoadConfig();
	CreateTimer(0.1, Timer_Tick, _, TIMER_REPEAT);

	if (g_Late)
	{
		PrecacheHats();
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i))
				continue;
			if (g_Cookie != null && AreClientCookiesCached(i))
				OnClientCookiesCached(i);
			if (!IsFakeClient(i))
				g_SkinsBlocked = true;
		}
		if (g_SkinsBlocked && g_SkinCount > 0)
			LogMessage("Loaded during a map with players in the game: player skins start at the next map (they need the download first)");
	}
}

public void OnPluginEnd()
{
	char model[PLATFORM_MAX_PATH];
	for (int i = 1; i <= MaxClients; i++)
	{
		RemoveHat(i, "unload");
		RemovePlush(i, "unload");
		// nobody keeps a skin the plugin no longer manages
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			GetClientModel(i, model, sizeof(model));
			int s = SkinOfModel(model);
			if (s >= 0)
				SetPlayerModel(i, g_SkinBase[s], "unload");
		}
	}
}

public void OnMapEnd()
{
	g_SkinsBlocked = false;  // everyone reconnects for the next map and downloads the skins then
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_HatRef[i] = INVALID_ENT_REFERENCE;
		g_HatWorn[i] = -1;
		g_WornOnModel[i][0] = '\0';
		g_PlushRef[i] = INVALID_ENT_REFERENCE;
		g_PlushOnModel[i][0] = '\0';
		g_FallbackRef[i] = INVALID_ENT_REFERENCE;
	}
	for (int e = 0; e <= MAX_EDICTS; e++)
	{
		g_EntOwner[e] = 0;
		g_EntPlush[e] = false;
		g_EntKind[e] = KIND_ANY;
	}
	PrecacheHats();
	RegisterSkins(true);
}

public void OnConfigsExecuted()
{
	// the settings in configs/dys_hats.cfg win over server.cfg (it runs before SourceMod loads plugins)
	LoadConfig();
	PrecacheHats();
	RegisterSkins(true);
	// server.cfg has run by now
	ConVar allow = FindConVar("sv_allowdownload");
	ConVar url = FindConVar("sv_downloadurl");
	char dl[8];
	if (url != null)
		url.GetString(dl, sizeof(dl));
	if (g_cvSkins.BoolValue && g_SkinCount > 0 && allow != null && !allow.BoolValue && dl[0] == '\0')
		LogError("sv_allowdownload is 0 and there is no sv_downloadurl: players can't download the player skins (they would see an ERROR model)");
}

// ---------------------------------------------------------------------------------------------
// config

// the "hats" block of a config file (kv at its root)
void ReadHats(KeyValues kv)
{
	if (!kv.JumpToKey("hats"))
		return;
	if (kv.GotoFirstSubKey())
	{
		char id[32], name[64], model[PLATFORM_MAX_PATH], fallback[32];
		float pos[3], ang[3];
		do
		{
			kv.GetSectionName(id, sizeof(id));
			kv.GetString("name", name, sizeof(name));
			kv.GetString("model", model, sizeof(model));
			kv.GetVector("pos", pos);
			kv.GetVector("ang", ang);
			kv.GetString("fallback", fallback, sizeof(fallback));
			if (model[0] == '\0')
			{
				LogError("hat '%s' has no model, skipped", id);
				continue;
			}
			AddHat(id, name, model, pos, ang, kv.GetFloat("scale", 1.0), kv.GetNum("teamskins", 0) != 0,
				kv.GetNum("tf2", 0) != 0, fallback);
		} while (kv.GotoNextKey());
		kv.GoBack();
	}
	kv.GoBack();
}

// optional configs/dys_hats_tf2.cfg: TF2 hats (tools/tf2_hats.py); every hat in it counts as "tf2" "1"
int ReadTf2Hats()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/dys_hats_tf2.cfg");
	if (!FileExists(path))
		return 0;
	KeyValues kv = new KeyValues("DysHats");
	int before = g_HatCount;
	if (kv.ImportFromFile(path))
	{
		ReadHats(kv);
		for (int i = before; i < g_HatCount; i++)
			g_HatTf2[i] = true;
	}
	else
		LogError("configs/dys_hats_tf2.cfg could not be parsed");
	delete kv;
	return g_HatCount - before;
}

void AddHat(const char[] id, const char[] name, const char[] model, const float pos[3], const float ang[3], float scale,
	bool teamskins = false, bool tf2 = false, const char[] fallback = "")
{
	if (g_HatCount >= MAX_HATS)
		return;
	if (FindHat(id) >= 0)
	{
		LogError("hat '%s' is defined twice, the second one is skipped", id);
		return;
	}
	if (!FileExists(model, true))
	{
		LogError("hat '%s': model %s not found, skipped", id, model);
		return;
	}
	int i = g_HatCount++;
	strcopy(g_HatId[i], sizeof(g_HatId[]), id);
	strcopy(g_HatName[i], sizeof(g_HatName[]), name[0] != '\0' ? name : id);
	strcopy(g_HatModel[i], sizeof(g_HatModel[]), model);
	for (int k = 0; k < 3; k++)
	{
		g_HatPos[i][k] = pos[k];
		g_HatAng[i][k] = ang[k];
	}
	g_HatScale[i] = scale > 0.0 ? scale : 1.0;
	g_HatTeamSkins[i] = teamskins;
	g_HatTf2[i] = tf2;
	strcopy(g_HatFallback[i], sizeof(g_HatFallback[]), fallback);
	char phy[PLATFORM_MAX_PATH];
	strcopy(phy, sizeof(phy), model);
	ReplaceString(phy, sizeof(phy), ".mdl", ".phy", false);
	g_HatHasPhysics[i] = FileExists(phy, true);
}

void AddBuiltin(const char[] id, const char[] name, const char[] model, float up, float roll)
{
	float pos[3], ang[3];
	pos[0] = -5.0;
	pos[2] = up;
	ang[2] = roll;
	AddHat(id, name, model, pos, ang, 1.0);
}

// The same list as configs/dys_hats.cfg, used when that file is missing.
void AddBuiltinHats()
{
	AddBuiltin("cone", "Traffic cone", "models/props_junk/trafficcone001a.mdl", 17.0, 0.0);
	AddBuiltin("bucket", "Metal bucket", "models/props_junk/metalbucket01a.mdl", 10.0, 180.0);
	AddBuiltin("pail", "Plastic bucket", "models/props_junk/plasticbucket001a.mdl", 16.0, 180.0);
	AddBuiltin("pot", "Cooking pot", "models/props_c17/metalpot001a.mdl", 8.5, 180.0);
	AddBuiltin("flowerpot", "Flower pot", "models/props_junk/terracotta01.mdl", 15.0, 180.0);
	AddBuiltin("lampshade", "Lamp shade", "models/props_c17/lampshade001a.mdl", 8.0, 0.0);
	AddBuiltin("melon", "Watermelon", "models/props_junk/watermelon01.mdl", 11.0, 0.0);
	AddBuiltin("milk", "Milk carton", "models/props_junk/garbage_milkcarton001a.mdl", 12.0, 0.0);
	AddBuiltin("can", "Soda can", "models/props_junk/popcan01a.mdl", 8.0, 0.0);
	AddBuiltin("hula", "Hula doll", "models/props_lab/huladoll.mdl", 5.0, 0.0);
	AddBuiltin("halo", "Saw-blade halo", "models/props_junk/sawblade001a.mdl", 14.0, 0.0);
}

void AddPlushModel(const char[] forModel, const char[] att, float x, float y, float z, float p, float yaw, float r)
{
	int i = FindPlushEntry(forModel);
	if (i < 0)
	{
		if (g_PlushCount >= MAX_PLUSH_MODELS)
			return;
		i = g_PlushCount++;
	}
	strcopy(g_PlushFor[i], sizeof(g_PlushFor[]), forModel);
	strcopy(g_PlushAtt[i], sizeof(g_PlushAtt[]), att);
	g_PlushPos[i][0] = x;
	g_PlushPos[i][1] = y;
	g_PlushPos[i][2] = z;
	g_PlushAng[i][0] = p;
	g_PlushAng[i][1] = yaw;
	g_PlushAng[i][2] = r;
}

// Computed from the bind pose of each class model: the plush (scale 1.2, 34 u tall) stands from the waist (z 37) to
// behind the head, its back 1 u into the wearer's back surface, its face looking backwards. Light and medium models
// carry it on the upper-chest bone (attachment "katana"), the heavies only have "eyes".
void AddBuiltinPlush()
{
	// katana models tuned in game: the rifle stance twists the upper body ~45 deg against the bind pose
	AddPlushModel("models/player/light_punk.mdl", "katana", -24.0, 6.0, -4.0, -40.0, 70.0, 110.0);
	// the pink skin's back is ~2.5 u closer to the spine than light_punk's: light_punk moved 2.5 u towards the body
	AddPlushModel("models/player/light_punk_pink.mdl", "katana", -25.0, 8.3, -3.7, -40.0, 70.0, 110.0);
	AddPlushModel("models/player/light_corp.mdl", "katana", -23.4, 5.1, -4.2, -40.0, 70.0, 110.0);
	AddPlushModel("models/player/medium_punk.mdl", "katana", -23.4, 4.4, -4.2, -40.0, 70.0, 110.0);
	AddPlushModel("models/player/medium_corp.mdl", "katana", -16.1, -2.2, -6.8, -41.0, 72.0, 111.0);
	AddPlushModel("models/player/heavy_punk.mdl", "eyes", -26.5, 0.0, -30.4, 2.0, 0.0, 0.0);
	AddPlushModel("models/player/heavy_corp.mdl", "eyes", -22.5, 0.0, -30.5, -4.0, 0.0, 0.0);
	AddPlushModel("default", "eyes", -24.0, 0.0, -30.5, 0.0, 0.0, 0.0);
}

int FindPlushEntry(const char[] forModel)
{
	for (int i = 0; i < g_PlushCount; i++)
	{
		if (StrEqual(g_PlushFor[i], forModel, false))
			return i;
	}
	return -1;
}

// the placement for a player model: its own entry, else "default", else -1
int PlushSlotFor(const char[] model)
{
	int i = FindPlushEntry(model);
	return i >= 0 ? i : FindPlushEntry("default");
}

int FindSkin(const char[] id)
{
	for (int i = 0; i < g_SkinCount; i++)
	{
		if (StrEqual(g_SkinId[i], id, false))
			return i;
	}
	return -1;
}

// quiet: a missing model is no error (the built-in skin on a server without the skin files)
void AddSkin(const char[] id, const char[] name, const char[] cls, const char[] model, const char[] base,
	const char[] materials, bool quiet)
{
	if (g_SkinCount >= MAX_SKINS)
		return;
	if (StrEqual(id, "none", false) || StrEqual(id, "off", false) || StrEqual(id, "default", false) || StrEqual(id, "list", false))
	{
		LogError("skin id '%s' is reserved, skipped", id);
		return;
	}
	if (FindSkin(id) >= 0)
	{
		LogError("skin '%s' is defined twice, the second one is skipped", id);
		return;
	}
	if (model[0] == '\0' || base[0] == '\0' || SameModel(model, base))
	{
		LogError("skin '%s' needs a \"model\" and a different \"base\" model, skipped", id);
		return;
	}
	if (!FileExists(model, true))
	{
		if (!quiet)
			LogError("skin '%s': model %s not found (copy the content/ folder of the dys_hats repo into dystopia/), skipped", id, model);
		return;
	}
	int i = g_SkinCount++;
	strcopy(g_SkinId[i], sizeof(g_SkinId[]), id);
	strcopy(g_SkinName[i], sizeof(g_SkinName[]), name[0] != '\0' ? name : id);
	strcopy(g_SkinClass[i], sizeof(g_SkinClass[]), cls);
	strcopy(g_SkinModel[i], sizeof(g_SkinModel[]), model);
	strcopy(g_SkinBase[i], sizeof(g_SkinBase[]), base);
	strcopy(g_SkinMaterials[i], sizeof(g_SkinMaterials[]), materials);
	ReplaceString(g_SkinModel[i], sizeof(g_SkinModel[]), "\\", "/");
	ReplaceString(g_SkinBase[i], sizeof(g_SkinBase[]), "\\", "/");
	ReplaceString(g_SkinMaterials[i], sizeof(g_SkinMaterials[]), "\\", "/");
	int len = strlen(g_SkinMaterials[i]);
	while (len > 0 && g_SkinMaterials[i][len - 1] == '/')
		g_SkinMaterials[i][--len] = '\0';
}

// The same as the "skins" block of configs/dys_hats.cfg, used when the config has none.
void AddBuiltinSkins()
{
	AddSkin("pink", "Pink Light Punk", "Punk Light", "models/player/light_punk_pink.mdl", "models/player/light_punk.mdl",
		"materials/models/player/light_punk_pink", true);
}

// the "skins" block of the config (kv at its root); false = there is none
bool ReadSkins(KeyValues kv)
{
	if (!kv.JumpToKey("skins"))
		return false;
	bool quiet = !g_cvSkins.BoolValue;  // skins switched off: a missing model is not worth an error
	if (kv.GotoFirstSubKey())
	{
		char id[32], name[64], cls[32], model[PLATFORM_MAX_PATH], base[PLATFORM_MAX_PATH], materials[PLATFORM_MAX_PATH];
		do
		{
			kv.GetSectionName(id, sizeof(id));
			kv.GetString("name", name, sizeof(name));
			kv.GetString("class", cls, sizeof(cls));
			kv.GetString("model", model, sizeof(model));
			kv.GetString("base", base, sizeof(base));
			kv.GetString("materials", materials, sizeof(materials));
			AddSkin(id, name, cls, model, base, materials, quiet);
		} while (kv.GotoNextKey());
		kv.GoBack();
	}
	kv.GoBack();
	return true;
}

void FinishPlushConfig()
{
	if (g_PlushCount == 0)
		AddBuiltinPlush();
	g_PlushOk = FileExists(g_PlushModel, true);
	if (!g_PlushOk)
		LogError("plush model %s not found, !plush is off", g_PlushModel);
	for (int i = 1; i <= MaxClients; i++)
		g_PlushOnModel[i][0] = '\0';  // re-attach with the new values
}

void LoadConfig()
{
	g_HatCount = 0;
	g_PlushCount = 0;
	g_SkinCount = 0;
	strcopy(g_PlushModel, sizeof(g_PlushModel), "models/twincannon/plush_heavy.mdl");
	g_PlushScale = 1.2;
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/dys_hats.cfg");
	KeyValues kv = new KeyValues("DysHats");
	if (!kv.ImportFromFile(path))
	{
		delete kv;
		AddBuiltinHats();
		AddBuiltinSkins();
		FinishPlushConfig();
		LogMessage("configs/dys_hats.cfg not found, using the %d built-in hats", g_HatCount);
		return;
	}

	int settings = 0;
	if (kv.JumpToKey("settings"))
	{
		if (kv.GotoFirstSubKey(false))
		{
			char key[64], value[256];
			do
			{
				kv.GetSectionName(key, sizeof(key));
				kv.GetString(NULL_STRING, value, sizeof(value));
				if (StrContains(key, "sm_hats_", false) != 0 || StrEqual(key, "sm_hats_version", false))
					continue;
				ConVar cv = FindConVar(key);
				if (cv != null)
				{
					cv.SetString(value);
					settings++;
				}
			} while (kv.GotoNextKey(false));
			kv.GoBack();
		}
		kv.GoBack();
	}

	ReadHats(kv);
	kv.Rewind();
	if (!ReadSkins(kv))
		AddBuiltinSkins();

	kv.Rewind();
	if (kv.JumpToKey("plush"))
	{
		kv.GetString("model", g_PlushModel, sizeof(g_PlushModel), g_PlushModel);
		g_PlushScale = kv.GetFloat("scale", g_PlushScale);
		if (g_PlushScale <= 0.0)
			g_PlushScale = 1.0;
		if (kv.GotoFirstSubKey())
		{
			char forModel[PLATFORM_MAX_PATH], att[32];
			float pos[3], ang[3];
			do
			{
				kv.GetSectionName(forModel, sizeof(forModel));
				kv.GetString("attachment", att, sizeof(att));
				kv.GetVector("pos", pos);
				kv.GetVector("ang", ang);
				AddPlushModel(forModel, att, pos[0], pos[1], pos[2], ang[0], ang[1], ang[2]);
			} while (kv.GotoNextKey());
		}
	}
	delete kv;
	FinishPlushConfig();
	int tf2 = ReadTf2Hats();

	if (g_HatCount == 0)
	{
		AddBuiltinHats();
		LogError("configs/dys_hats.cfg has no usable hats, using the %d built-in hats", g_HatCount);
	}
	else
		LogMessage("Read %d hat(s), %d skin(s) and %d setting(s) from configs/dys_hats.cfg, %d TF2 hat(s) from configs/dys_hats_tf2.cfg",
			g_HatCount - tf2, g_SkinCount, settings, tf2);

	// a reload can shift the indices: everybody re-equips
	for (int i = 1; i <= MaxClients; i++)
		g_HatWorn[i] = -1;
}

void PrecacheHats()
{
	for (int i = 0; i < g_HatCount; i++)
		PrecacheModel(g_HatModel[i], true);
	if (g_PlushOk)
		PrecacheModel(g_PlushModel, true);
}

// model paths compared the way the engine does: case-insensitive, \ = /
bool SameModel(const char[] a, const char[] b)
{
	for (int i = 0; ; i++)
	{
		int ca = CharToLower(a[i]);
		int cb = CharToLower(b[i]);
		if (ca == '\\')
			ca = '/';
		if (cb == '\\')
			cb = '/';
		if (ca != cb)
			return false;
		if (ca == '\0')
			return true;
	}
}

void ModelKey(const char[] model, char[] key, int maxlen)
{
	strcopy(key, maxlen, model);
	for (int i = 0; key[i] != '\0'; i++)
		key[i] = (key[i] == '\\') ? '/' : CharToLower(key[i]);
}

// the skin whose model this is, or -1
int SkinOfModel(const char[] model)
{
	for (int i = 0; i < g_SkinCount; i++)
	{
		if (SameModel(g_SkinModel[i], model))
			return i;
	}
	return -1;
}

// in the download table since this map started: everybody in the game has the files
bool SkinLive(int idx)
{
	char key[PLATFORM_MAX_PATH];
	bool live;
	ModelKey(g_SkinModel[idx], key, sizeof(key));
	return g_LiveModels.GetValue(key, live) && live;
}

// Download table + precache for every skin: at map start (OnMapStart, again after the config in OnConfigsExecuted)
// and after sm_hats_reload. Only a map-start registration makes a skin live: players who are in the game already when a
// skin shows up mid-map (late load, reload, sm_hats_skins 0 -> 1) never downloaded it and would see an ERROR model.
void RegisterSkins(bool mapStart)
{
	if (mapStart)
		g_LiveModels.Clear();
	if (!g_cvSkins.BoolValue || g_SkinCount == 0)
		return;
	char key[PLATFORM_MAX_PATH];
	for (int i = 0; i < g_SkinCount; i++)
	{
		int files = AddSkinDownloads(i);
		PrecacheModel(g_SkinModel[i], true);
		if (mapStart && !g_SkinsBlocked)
		{
			ModelKey(g_SkinModel[i], key, sizeof(key));
			g_LiveModels.SetValue(key, true);
		}
		if (g_cvDebug.BoolValue)
			LogMessage("skin '%s': %d file(s) in the download table, %s", g_SkinId[i], files, SkinLive(i) ? "live" : "from the next map on");
	}
}

// the model, its companion files and every file of its materials folder; returns the number of files
int AddSkinDownloads(int idx)
{
	char base[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	AddFileToDownloadsTable(g_SkinModel[idx]);
	int n = 1;
	strcopy(base, sizeof(base), g_SkinModel[idx]);
	int len = strlen(base);
	if (len > 4 && StrEqual(base[len - 4], ".mdl", false))
	{
		base[len - 4] = '\0';
		for (int k = 0; k < sizeof(g_SkinExt); k++)
		{
			Format(path, sizeof(path), "%s%s", base, g_SkinExt[k]);
			if (FileExists(path, true))
			{
				AddFileToDownloadsTable(path);
				n++;
			}
		}
	}
	if (g_SkinMaterials[idx][0] == '\0')
		return n;
	DirectoryListing dir = OpenDirectory(g_SkinMaterials[idx], true);
	if (dir == null)
	{
		LogError("skin '%s': materials folder %s not found", g_SkinId[idx], g_SkinMaterials[idx]);
		return n;
	}
	char name[PLATFORM_MAX_PATH];
	FileType type;
	while (dir.GetNext(name, sizeof(name), type))
	{
		if (type != FileType_File)
			continue;
		Format(path, sizeof(path), "%s/%s", g_SkinMaterials[idx], name);
		AddFileToDownloadsTable(path);
		n++;
	}
	delete dir;
	return n;
}

// the hat shown instead of TF2 hat idx to players without the TF2 files (-1 = nothing)
int FallbackFor(int idx)
{
	int f = FindHat(g_HatFallback[idx]);
	if (f < 0 || g_HatTf2[f])
	{
		char id[32];
		g_cvTf2Fallback.GetString(id, sizeof(id));
		f = FindHat(id);
	}
	return (f >= 0 && !g_HatTf2[f]) ? f : -1;
}

void ReadViewerTf2(int client)
{
	char v[8];
	g_ViewerTf2[client] = !IsFakeClient(client) && GetClientInfo(client, "dys_tf2hats", v, sizeof(v)) && StringToInt(v) != 0;
}

public void OnClientPutInServer(int client)
{
	ReadViewerTf2(client);
}

public void OnClientSettingsChanged(int client)
{
	if (IsClientInGame(client))
		ReadViewerTf2(client);
}

int FindHat(const char[] id)
{
	for (int i = 0; i < g_HatCount; i++)
	{
		if (StrEqual(g_HatId[i], id, false))
			return i;
	}
	return -1;
}

// ---------------------------------------------------------------------------------------------
// players

void ResetClient(int client)
{
	g_Choice[client] = CHOICE_DEFAULT;
	g_BotHat[client] = g_HatCount > 0 ? GetRandomInt(0, g_HatCount - 1) : -1;
	g_HatRef[client] = INVALID_ENT_REFERENCE;
	g_HatWorn[client] = -1;
	g_WornOnModel[client][0] = '\0';
	g_SpawnTime[client] = 0.0;
	g_ShowOwn[client] = false;
	g_ShowOwnPlush[client] = false;
	g_PlushOn[client] = false;
	g_PlushRef[client] = INVALID_ENT_REFERENCE;
	g_PlushOnModel[client][0] = '\0';
	g_ViewerTf2[client] = false;
	g_FallbackRef[client] = INVALID_ENT_REFERENCE;
	g_SkinChoice[client][0] = '\0';
	g_SkinForce[client][0] = '\0';
}

public void OnClientConnected(int client)
{
	ResetClient(client);
}

public void OnClientDisconnect(int client)
{
	RemoveHat(client, "disconnect");
	RemovePlush(client, "disconnect");
}

public void OnClientCookiesCached(int client)
{
	if (g_Cookie == null || IsFakeClient(client))
		return;
	char id[32];
	GetClientCookie(client, g_Cookie, id, sizeof(id));
	if (id[0] == '\0' || StrEqual(id, "default"))
		g_Choice[client] = CHOICE_DEFAULT;
	else if (StrEqual(id, "none"))
		g_Choice[client] = CHOICE_NONE;
	else
	{
		int idx = FindHat(id);
		g_Choice[client] = idx >= 0 ? idx : CHOICE_DEFAULT;
	}
	if (g_PlushCookie != null)
	{
		GetClientCookie(client, g_PlushCookie, id, sizeof(id));
		g_PlushOn[client] = StrEqual(id, "1");
	}
	if (g_SkinCookie != null)
	{
		// "none" or a skin id; an id this server doesn't have is kept (it may come back) and means no skin meanwhile
		GetClientCookie(client, g_SkinCookie, id, sizeof(id));
		TrimString(id);
		if (StrEqual(id, "default", false))
			id[0] = '\0';
		strcopy(g_SkinChoice[client], sizeof(g_SkinChoice[]), id);
	}
}

int DefaultHat()
{
	char id[32];
	g_cvDefault.GetString(id, sizeof(id));
	return FindHat(id);
}

int WantedHat(int client)
{
	if (IsFakeClient(client))
	{
		if (IsClientSourceTV(client) || IsClientReplay(client))
			return -1;
		switch (g_cvBots.IntValue)
		{
			case 1: return DefaultHat();
			case 2: return g_BotHat[client] < g_HatCount ? g_BotHat[client] : -1;
		}
		return -1;
	}
	if (g_Choice[client] == CHOICE_DEFAULT)
		return DefaultHat();
	return g_Choice[client] < g_HatCount ? g_Choice[client] : -1;
}

// the skin this player should have (-1 = the stock model): sm_skin_force, else bots per sm_hats_skins_bots, else the
// player's !skin choice ("" = sm_hats_skin_default)
int WantedSkin(int client)
{
	if (!g_cvSkins.BoolValue)
		return -1;
	char id[32];
	if (g_SkinForce[client][0] != '\0')
		strcopy(id, sizeof(id), g_SkinForce[client]);
	else if (IsFakeClient(client))
	{
		if (IsClientSourceTV(client) || IsClientReplay(client) || !g_cvSkinBots.BoolValue)
			return -1;
		g_cvSkinDefault.GetString(id, sizeof(id));
	}
	else if (g_SkinChoice[client][0] == '\0')
		g_cvSkinDefault.GetString(id, sizeof(id));
	else
		strcopy(id, sizeof(id), g_SkinChoice[client]);
	return FindSkin(id);  // "none" or an unknown id: -1
}

// SetEntityModel that leaves m_nSkin alone (the game drives it: thermal, headshot, stealth)
bool SetPlayerModel(int client, const char[] model, const char[] why)
{
	if (!IsModelPrecached(model))
		return false;
	int skin = GetEntProp(client, Prop_Send, "m_nSkin");
	SetEntityModel(client, model);
	if (GetEntProp(client, Prop_Send, "m_nSkin") != skin)
		SetEntProp(client, Prop_Send, "m_nSkin", skin);
	if (g_cvDebug.BoolValue)
		LogMessage("%N: player model %s (%s)", client, model, why);
	return true;
}

// Puts a player who wants a skin into it while their model is the skin's base model, and back into the base model
// when they don't want it any more. Any other model (other classes, the cyberspace avatar) is never touched.
// Dystopia sets the class model again at every spawn, so this runs after each spawn and every tick.
// Returns true if the model changed.
bool TickSkin(int client, const char[] model)
{
	int want = WantedSkin(client);
	if (want >= 0 && !SkinLive(want))
		want = -1;
	int wearing = SkinOfModel(model);
	if (wearing == want)
		return false;
	if (wearing >= 0)
	{
		if (want >= 0 && SameModel(g_SkinBase[wearing], g_SkinBase[want]))
			return SetPlayerModel(client, g_SkinModel[want], g_SkinId[want]);
		return SetPlayerModel(client, g_SkinBase[wearing], "skin off");
	}
	if (SameModel(model, g_SkinBase[want]))
		return SetPlayerModel(client, g_SkinModel[want], g_SkinId[want]);
	return false;
}

public void Frame_SpawnSkin(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) < 2 || Camouflage(client) > 0)
		return;
	char model[PLATFORM_MAX_PATH];
	GetClientModel(client, model, sizeof(model));
	TickSkin(client, model);
}

bool InCyberspace(int client, const char[] model)
{
	if (StrContains(model, "player/cyber", false) != -1)
		return true;
	return HasEntProp(client, Prop_Send, "m_bIsCyberSpace") && GetEntProp(client, Prop_Send, "m_bIsCyberSpace") != 0;
}

int Camouflage(int client)
{
	return HasEntProp(client, Prop_Send, "m_iCamouflageAmount") ? GetEntProp(client, Prop_Send, "m_iCamouflageAmount") : 0;
}

public void Event_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0)
		return;
	g_SpawnTime[client] = GetGameTime();
	if (IsFakeClient(client) && g_HatCount > 0)
		g_BotHat[client] = GetRandomInt(0, g_HatCount - 1);
	g_HatWorn[client] = -1;  // the class model may have changed: re-attach on the next tick
	g_PlushOnModel[client][0] = '\0';
	// the spawn sets the stock class model: put the skin back on one frame later (the tick catches a later reset)
	if (g_SkinCount > 0)
		RequestFrame(Frame_SpawnSkin, GetClientUserId(client));
}

public void Event_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0)
		return;
	int hat = EntRefToEntIndex(g_HatRef[client]);
	if (hat > 0 && g_cvDrop.BoolValue && (GetEntProp(hat, Prop_Send, "m_fEffects") & EF_NODRAW) == 0)
		DropHat(client, g_HatWorn[client]);
	RemoveHat(client, "death");
	int plush = EntRefToEntIndex(g_PlushRef[client]);
	if (plush > 0 && g_cvDrop.BoolValue && (GetEntProp(plush, Prop_Send, "m_fEffects") & EF_NODRAW) == 0)
		DropPlush(client);
	RemovePlush(client, "death");
}

public void Event_Team(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		RemoveHat(client, "team");
		RemovePlush(client, "team");
	}
}

public Action Timer_Tick(Handle timer)
{
	bool enabled = g_cvEnabled.BoolValue;
	float now = GetGameTime();
	char model[PLATFORM_MAX_PATH];
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;
		bool playing = IsPlayerAlive(client) && GetClientTeam(client) >= 2;
		model[0] = '\0';
		if (playing)
			GetClientModel(client, model, sizeof(model));
		bool settled = now - g_SpawnTime[client] >= 0.2;  // let the spawn set the class model first
		bool hide = playing && Camouflage(client) > 0;     // nothing may give a cloaked player away
		// the player skin first (not while cloaked), so hats and plush attach to the model the player really has
		if (playing && settled && !hide && g_SkinCount > 0 && TickSkin(client, model))
			GetClientModel(client, model, sizeof(model));
		bool cyber = playing && InCyberspace(client, model);
		TickHat(client, enabled ? WantedHat(client) : -1, playing, cyber, settled, hide, model);
		TickPlush(client, enabled && WantsPlush(client), playing, cyber, settled, hide, model);
	}
	return Plugin_Continue;
}

void TickHat(int client, int want, bool playing, bool cyber, bool settled, bool hide, const char[] model)
{
	int hat = EntRefToEntIndex(g_HatRef[client]);
	if (want < 0 || !playing || cyber)
	{
		if (hat > 0)
			RemoveHat(client, want < 0 ? "no hat" : (cyber ? "cyberspace" : "not playing"));
		return;
	}
	if (hat <= 0 || g_HatWorn[client] != want || !StrEqual(model, g_WornOnModel[client]))
	{
		if (!settled)
			return;
		hat = EquipHat(client, want, model);
		if (hat <= 0)
			return;
	}
	SetHidden(client, hat, hide, "hat");
	int fb = EntRefToEntIndex(g_FallbackRef[client]);
	if (fb > 0)
		SetHidden(client, fb, hide, "hat stand-in");
}

void TickPlush(int client, bool want, bool playing, bool cyber, bool settled, bool hide, const char[] model)
{
	int plush = EntRefToEntIndex(g_PlushRef[client]);
	int slot = (want && playing) ? PlushSlotFor(model) : -1;
	if (slot < 0 || cyber)
	{
		if (plush > 0)
			RemovePlush(client, !want ? "off" : (cyber ? "cyberspace" : "not playing"));
		return;
	}
	if (plush <= 0 || !StrEqual(model, g_PlushOnModel[client]))
	{
		if (!settled)
			return;
		plush = EquipPlush(client, slot, model);
		if (plush <= 0)
			return;
	}
	SetHidden(client, plush, hide, "plush");
}

void SetHidden(int client, int ent, bool hide, const char[] what)
{
	int fx = GetEntProp(ent, Prop_Send, "m_fEffects");
	if (hide == ((fx & EF_NODRAW) != 0))
		return;
	SetEntProp(ent, Prop_Send, "m_fEffects", hide ? (fx | EF_NODRAW) : (fx & ~EF_NODRAW));
	if (g_cvDebug.BoolValue)
		LogMessage("%N: %s %s (camouflage %d)", client, what, hide ? "hidden" : "shown", Camouflage(client));
}

bool WantsPlush(int client)
{
	if (!g_cvPlush.BoolValue || !g_PlushOk)
		return false;
	if (IsFakeClient(client))
		return !IsClientSourceTV(client) && !IsClientReplay(client) && g_cvPlushBots.BoolValue;
	return g_PlushOn[client];
}

// ---------------------------------------------------------------------------------------------
// hat entities

void SetScale(int ent, float scale)
{
	if (scale != 1.0 && HasEntProp(ent, Prop_Send, "m_flModelScale"))
		SetEntPropFloat(ent, Prop_Send, "m_flModelScale", scale);
}

// a non-solid prop parented to the player at an attachment ("" = the player origin), offset by pos / ang
int CreateAttached(int client, const char[] mdl, float scale, const char[] att, const float pos[3], const float ang[3])
{
	int ent = CreateEntityByName("prop_dynamic_override");
	if (ent <= 0)
		return -1;
	DispatchKeyValue(ent, "model", mdl);
	DispatchKeyValue(ent, "solid", "0");
	DispatchKeyValue(ent, "disableshadows", "1");
	if (!DispatchSpawn(ent))
	{
		RemoveEntity(ent);
		return -1;
	}
	SetScale(ent, scale);
	float eye[3];
	GetClientEyePosition(client, eye);
	TeleportEntity(ent, eye, NULL_VECTOR, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(ent, "SetParent", client, ent);
	if (att[0] != '\0')
	{
		SetVariantString(att);
		AcceptEntityInput(ent, "SetParentAttachment", ent, ent);
	}
	// once parented, TeleportEntity sets the offset from the parent / attachment
	TeleportEntity(ent, pos, ang, NULL_VECTOR);
	return ent;
}

// red / blue skin by team for hats that have them
void SetTeamSkin(int ent, int client, int idx)
{
	if (g_HatTeamSkins[idx])
		SetEntProp(ent, Prop_Send, "m_nSkin", GetClientTeam(client) == 3 ? 1 : 0);
}

int CreateHatEntity(int client, int idx)
{
	int ent = CreateAttached(client, g_HatModel[idx], g_HatScale[idx], "eyes", g_HatPos[idx], g_HatAng[idx]);
	if (ent > 0)
		SetTeamSkin(ent, client, idx);
	return ent;
}

int EquipHat(int client, int idx, const char[] model)
{
	RemoveHat(client, "");
	int ent = CreateHatEntity(client, idx);
	if (ent <= 0)
		return -1;
	g_EntOwner[ent] = client;
	g_EntPlush[ent] = false;
	g_EntKind[ent] = g_HatTf2[idx] ? KIND_TF2 : KIND_ANY;
	SDKHookEx(ent, SDKHook_SetTransmit, Hook_SetTransmit);
	g_HatRef[client] = EntIndexToEntRef(ent);
	g_HatWorn[client] = idx;
	if (g_HatTf2[idx])
	{
		// players without the TF2 files would see an ERROR model: they get an HL2 stand-in instead
		int f = FallbackFor(idx);
		int fb = f >= 0 ? CreateHatEntity(client, f) : -1;
		if (fb > 0)
		{
			g_EntOwner[fb] = client;
			g_EntPlush[fb] = false;
			g_EntKind[fb] = KIND_FALLBACK;
			SDKHookEx(fb, SDKHook_SetTransmit, Hook_SetTransmit);
			g_FallbackRef[client] = EntIndexToEntRef(fb);
		}
	}
	strcopy(g_WornOnModel[client], sizeof(g_WornOnModel[]), model);
	if (g_cvDebug.BoolValue)
		LogMessage("%N: wears '%s' (entity %d, model %s)", client, g_HatId[idx], ent, model);
	return ent;
}

void RemoveHat(int client, const char[] why)
{
	int fb = EntRefToEntIndex(g_FallbackRef[client]);
	if (fb > 0)
	{
		g_EntOwner[fb] = 0;
		g_EntKind[fb] = KIND_ANY;
		RemoveEntity(fb);
	}
	g_FallbackRef[client] = INVALID_ENT_REFERENCE;
	int hat = EntRefToEntIndex(g_HatRef[client]);
	if (hat > 0)
	{
		g_EntOwner[hat] = 0;
		g_EntKind[hat] = KIND_ANY;
		RemoveEntity(hat);
		if (why[0] != '\0' && g_cvDebug.BoolValue && IsClientInGame(client))
			LogMessage("%N: hat removed (%s)", client, why);
	}
	g_HatRef[client] = INVALID_ENT_REFERENCE;
	g_HatWorn[client] = -1;
	g_WornOnModel[client][0] = '\0';
}

// a physics copy that falls off and disappears after sm_hats_drop_time (debris: collides with the world only)
int DropProp(const char[] mdl, float scale, const float pos[3], const float ang[3])
{
	int prop = CreateEntityByName("prop_physics_override");
	if (prop <= 0)
		return -1;
	DispatchKeyValue(prop, "model", mdl);
	DispatchKeyValue(prop, "spawnflags", "516");  // 4 debris: no collisions with players, 512: no +use pickup
	DispatchKeyValueVector(prop, "origin", pos);
	DispatchKeyValueVector(prop, "angles", ang);
	if (!DispatchSpawn(prop))
	{
		RemoveEntity(prop);
		return -1;
	}
	SetScale(prop, scale);
	float vel[3];
	vel[0] = GetRandomFloat(-80.0, 80.0);
	vel[1] = GetRandomFloat(-80.0, 80.0);
	vel[2] = GetRandomFloat(160.0, 230.0);
	TeleportEntity(prop, NULL_VECTOR, NULL_VECTOR, vel);
	CreateTimer(g_cvDropTime.FloatValue, Timer_RemoveDrop, EntIndexToEntRef(prop), TIMER_FLAG_NO_MAPCHANGE);
	return prop;
}

void DropHat(int client, int idx, int kind = KIND_ANY)
{
	if (idx < 0 || idx >= g_HatCount)
		return;
	if (g_HatTf2[idx] && kind == KIND_ANY)
	{
		// the TF2 hat for players with the files, its stand-in for everyone else
		DropHat(client, idx, KIND_TF2);
		int f = FallbackFor(idx);
		if (f >= 0)
			DropHat(client, f, KIND_FALLBACK);
		return;
	}
	if (!g_HatHasPhysics[idx])
		return;
	// where the hat sat: its offset from the eyes turned by the view yaw (the model origin of a TF2 hat is ~78 u
	// below it, at the feet of the TF2 character), lifted a little so it pops off the head
	float eye[3], va[3], fwd[3], right[3], up[3], pos[3], ang[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, va);
	va[0] = 0.0;
	va[2] = 0.0;
	GetAngleVectors(va, fwd, right, up);
	for (int k = 0; k < 3; k++)
		pos[k] = eye[k] + fwd[k] * g_HatPos[idx][0] - right[k] * g_HatPos[idx][1] + up[k] * g_HatPos[idx][2];
	pos[2] += 4.0;
	ang[0] = g_HatAng[idx][0];
	ang[1] = va[1] + g_HatAng[idx][1];
	ang[2] = g_HatAng[idx][2];
	int prop = DropProp(g_HatModel[idx], g_HatScale[idx], pos, ang);
	if (prop > 0)
	{
		SetTeamSkin(prop, client, idx);
		g_EntOwner[prop] = 0;
		g_EntPlush[prop] = false;
		g_EntKind[prop] = kind;
		if (kind != KIND_ANY)
			SDKHookEx(prop, SDKHook_SetTransmit, Hook_SetTransmit);
	}
	if (prop > 0 && g_cvDebug.BoolValue)
		LogMessage("%N: hat '%s' fell off (entity %d)", client, g_HatId[idx], prop);
}

void DropPlush(int client)
{
	float pos[3], ang[3];
	GetClientAbsOrigin(client, pos);
	pos[2] += 36.0;
	GetClientEyeAngles(client, ang);
	ang[0] = 0.0;
	ang[2] = 0.0;
	int prop = DropProp(g_PlushModel, g_PlushScale, pos, ang);
	if (prop > 0 && g_cvDebug.BoolValue)
		LogMessage("%N: plush fell off (entity %d)", client, prop);
}

int EquipPlush(int client, int slot, const char[] model)
{
	RemovePlush(client, "");
	int ent = CreateAttached(client, g_PlushModel, g_PlushScale, g_PlushAtt[slot], g_PlushPos[slot], g_PlushAng[slot]);
	if (ent <= 0)
		return -1;
	g_EntOwner[ent] = client;
	g_EntPlush[ent] = true;
	SDKHookEx(ent, SDKHook_SetTransmit, Hook_SetTransmit);
	g_PlushRef[client] = EntIndexToEntRef(ent);
	strcopy(g_PlushOnModel[client], sizeof(g_PlushOnModel[]), model);
	if (g_cvDebug.BoolValue)
		LogMessage("%N: wears the plush (entity %d, model %s, placement '%s')", client, ent, model, g_PlushFor[slot]);
	return ent;
}

void RemovePlush(int client, const char[] why)
{
	int ent = EntRefToEntIndex(g_PlushRef[client]);
	if (ent > 0)
	{
		g_EntOwner[ent] = 0;
		g_EntPlush[ent] = false;
		RemoveEntity(ent);
		if (why[0] != '\0' && g_cvDebug.BoolValue && IsClientInGame(client))
			LogMessage("%N: plush removed (%s)", client, why);
	}
	g_PlushRef[client] = INVALID_ENT_REFERENCE;
	g_PlushOnModel[client][0] = '\0';
}

public Action Timer_RemoveDrop(Handle timer, int ref)
{
	int prop = EntRefToEntIndex(ref);
	if (prop > 0)
	{
		g_EntKind[prop] = KIND_ANY;
		RemoveEntity(prop);
	}
	return Plugin_Stop;
}

public Action Hook_SetTransmit(int entity, int viewer)
{
	g_TransmitCalls++;
	// a TF2 hat goes only to players with the TF2 files, its HL2 stand-in only to everyone else
	int kind = g_EntKind[entity];
	if (kind != KIND_ANY && viewer > 0 && viewer <= MaxClients && (kind == KIND_TF2) != g_ViewerTf2[viewer])
	{
		g_KindBlocked[kind]++;
		return Plugin_Handled;
	}
	int owner = g_EntOwner[entity];
	if (owner <= 0 || !g_cvHideOwn.BoolValue)
		return Plugin_Continue;
	// your own hat sits right above the camera and the plush clips into the view (unless you asked to see them:
	// !hat show / !plush show)
	if (viewer == owner && !(g_EntPlush[entity] ? g_ShowOwnPlush[owner] : g_ShowOwn[owner]))
	{
		g_TransmitHidden++;
		return Plugin_Handled;
	}
	// the same for spectators watching the wearer in first person
	if (viewer > 0 && viewer <= MaxClients && IsClientInGame(viewer) && !IsPlayerAlive(viewer)
		&& GetEntPropEnt(viewer, Prop_Send, "m_hObserverTarget") == owner
		&& GetEntProp(viewer, Prop_Send, "m_iObserverMode") == OBS_MODE_IN_EYE)
	{
		g_TransmitHidden++;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// ---------------------------------------------------------------------------------------------
// commands

void ShowHatMenu(int client, int first)
{
	Menu menu = new Menu(Menu_Hat);
	int cur = WantedHat(client);
	menu.SetTitle("Pick a hat (now: %s)", cur >= 0 ? g_HatName[cur] : "none");
	menu.AddItem("none", "No hat", cur < 0 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	for (int i = 0; i < g_HatCount; i++)
		menu.AddItem(g_HatId[i], g_HatName[i], i == cur ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.DisplayAt(client, first, MENU_TIME_FOREVER);
}

public int Menu_Hat(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char id[32];
		menu.GetItem(item, id, sizeof(id));
		SetChoice(client, id);
		ShowHatMenu(client, GetMenuSelectionPosition());  // stay on the page to try the next one
	}
	else if (action == MenuAction_End)
		delete menu;
	return 0;
}

void SetChoice(int client, const char[] id)
{
	int choice;
	if (StrEqual(id, "none", false) || StrEqual(id, "off", false))
		choice = CHOICE_NONE;
	else if (StrEqual(id, "default", false))
		choice = CHOICE_DEFAULT;
	else
	{
		choice = FindHat(id);
		if (choice < 0)
		{
			PrintToChat(client, "%s Unknown hat '%s'. Type !hat list for the ids.", PREFIX, id);
			return;
		}
	}
	g_Choice[client] = choice;
	if (g_Cookie != null && AreClientCookiesCached(client))
		SetClientCookie(client, g_Cookie, choice == CHOICE_NONE ? "none" : (choice == CHOICE_DEFAULT ? "default" : g_HatId[choice]));
	int now = WantedHat(client);
	if (now < 0)
		PrintToChat(client, "%s No hat.", PREFIX);
	else if (IsPlayerAlive(client))
		PrintToChat(client, "%s You now wear: %s", PREFIX, g_HatName[now]);
	else
		PrintToChat(client, "%s You will wear: %s", PREFIX, g_HatName[now]);
	if (now >= 0 && g_HatTf2[now])
	{
		int f = FallbackFor(now);
		PrintToChat(client, "%s Players with the TF2 hats installed see it; everyone else sees: %s.%s", PREFIX,
			f >= 0 ? g_HatName[f] : "no hat", g_ViewerTf2[client] ? "" : " Type !hat tf2 to see TF2 hats yourself.");
	}
}

void PrintTf2Help(int client)
{
	int n = 0;
	for (int i = 0; i < g_HatCount; i++)
	{
		if (g_HatTf2[i])
			n++;
	}
	if (n == 0)
	{
		PrintToChat(client, "%s This server has no TF2 hats.", PREFIX);
		return;
	}
	PrintToChat(client, "%s This server has %d TF2 hats. You %s.", PREFIX, n,
		g_ViewerTf2[client] ? "see them (dys_tf2hats 1)" : "see HL2 stand-ins for them");
	if (!g_ViewerTf2[client])
	{
		PrintToChat(client, "%s To see them: install Team Fortress 2 (free), run tf2_hats.py from github.com/atomy/dys_hat once", PREFIX);
		PrintToChat(client, "%s (it copies the hats from your TF2 into dystopia/download), then put  setinfo dys_tf2hats 1  in cfg/autoexec.cfg.", PREFIX);
	}
}

public Action Cmd_Hat(int client, int args)
{
	// on a listen server the host's console runs commands as the server: treat them as the host's
	if (client == 0 && !IsDedicatedServer() && IsClientInGame(1) && !IsFakeClient(1))
		client = 1;
	if (client <= 0 || !IsClientInGame(client))
	{
		ReplyToCommand(client, "[Hats] This command is for players in the game.");
		return Plugin_Handled;
	}
	if (!g_cvEnabled.BoolValue)
	{
		ReplyToCommand(client, "[Hats] Hats are switched off on this server.");
		return Plugin_Handled;
	}
	if (g_HatCount == 0)
	{
		ReplyToCommand(client, "[Hats] No hats configured.");
		return Plugin_Handled;
	}
	if (args < 1)
	{
		ShowHatMenu(client, 0);
		return Plugin_Handled;
	}
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if (StrEqual(arg, "show", false) || StrEqual(arg, "hide", false))
	{
		g_ShowOwn[client] = StrEqual(arg, "show", false);
		PrintToChat(client, "%s %s", PREFIX, g_ShowOwn[client]
			? "You see your own hat now (third person: sv_cheats 1; thirdperson). !hat hide to hide it again."
			: "Your own hat is hidden from you again.");
	}
	else if (StrEqual(arg, "tf2", false))
		PrintTf2Help(client);
	else if (StrEqual(arg, "list", false))
	{
		char line[512] = "none";
		for (int i = 0; i < g_HatCount; i++)
			Format(line, sizeof(line), "%s, %s", line, g_HatId[i]);
		PrintToChat(client, "%s !hat <id>: %s", PREFIX, line);
	}
	else if (StrEqual(arg, "next", false))
	{
		int cur = WantedHat(client);
		SetChoice(client, g_HatId[(cur + 1) % g_HatCount]);
	}
	else
		SetChoice(client, arg);
	return Plugin_Handled;
}

public Action Cmd_Plush(int client, int args)
{
	// on a listen server the host's console runs commands as the server: treat them as the host's
	if (client == 0 && !IsDedicatedServer() && IsClientInGame(1) && !IsFakeClient(1))
		client = 1;
	if (client <= 0 || !IsClientInGame(client))
	{
		ReplyToCommand(client, "[Hats] This command is for players in the game.");
		return Plugin_Handled;
	}
	if (!g_cvEnabled.BoolValue || !g_cvPlush.BoolValue || !g_PlushOk)
	{
		ReplyToCommand(client, "[Hats] The plush backpack is switched off on this server.");
		return Plugin_Handled;
	}
	bool on = !g_PlushOn[client];
	if (args >= 1)
	{
		char arg[8];
		GetCmdArg(1, arg, sizeof(arg));
		if (StrEqual(arg, "show", false) || StrEqual(arg, "hide", false))
		{
			g_ShowOwnPlush[client] = StrEqual(arg, "show", false);
			PrintToChat(client, "%s %s", PREFIX, g_ShowOwnPlush[client]
				? "You see your own plush now (third person: sv_cheats 1; thirdperson). !plush hide to hide it again."
				: "Your own plush is hidden from you again.");
			return Plugin_Handled;
		}
		if (StrEqual(arg, "on", false) || StrEqual(arg, "1"))
			on = true;
		else if (StrEqual(arg, "off", false) || StrEqual(arg, "0"))
			on = false;
	}
	g_PlushOn[client] = on;
	if (g_PlushCookie != null && AreClientCookiesCached(client))
		SetClientCookie(client, g_PlushCookie, on ? "1" : "0");
	PrintToChat(client, "%s Plush backpack %s.", PREFIX, on ? "on" : "off");
	return Plugin_Handled;
}

// "Pink Light Punk (Punk Light)"
void SkinLabel(int idx, char[] buf, int maxlen)
{
	if (g_SkinClass[idx][0] != '\0')
		Format(buf, maxlen, "%s (%s)", g_SkinName[idx], g_SkinClass[idx]);
	else
		strcopy(buf, maxlen, g_SkinName[idx]);
}

void ShowSkinMenu(int client)
{
	Menu menu = new Menu(Menu_Skin);
	int cur = WantedSkin(client);
	menu.SetTitle("Player model (now: %s)", cur >= 0 ? g_SkinName[cur] : "stock");
	menu.AddItem("none", "Stock model", cur < 0 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	char label[128];
	for (int i = 0; i < g_SkinCount; i++)
	{
		SkinLabel(i, label, sizeof(label));
		menu.AddItem(g_SkinId[i], label, i == cur ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Skin(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char id[32];
		menu.GetItem(item, id, sizeof(id));
		SetSkinChoice(client, id);
	}
	else if (action == MenuAction_End)
		delete menu;
	return 0;
}

void SetSkinChoice(int client, const char[] id)
{
	char choice[32];
	if (StrEqual(id, "none", false) || StrEqual(id, "off", false))
		strcopy(choice, sizeof(choice), "none");
	else if (!StrEqual(id, "default", false))
	{
		int idx = FindSkin(id);
		if (idx < 0)
		{
			PrintToChat(client, "%s Unknown skin '%s'. Type !skin list for the ids.", PREFIX, id);
			return;
		}
		strcopy(choice, sizeof(choice), g_SkinId[idx]);
	}
	strcopy(g_SkinChoice[client], sizeof(g_SkinChoice[]), choice);
	g_SkinForce[client][0] = '\0';  // the player's own pick ends an admin's sm_skin_force
	if (g_SkinCookie != null && AreClientCookiesCached(client))
		SetClientCookie(client, g_SkinCookie, choice[0] != '\0' ? choice : "default");
	int now = WantedSkin(client);
	if (now < 0)
	{
		PrintToChat(client, "%s Stock player model.", PREFIX);
		return;
	}
	char label[128], model[PLATFORM_MAX_PATH];
	SkinLabel(now, label, sizeof(label));
	if (!SkinLive(now))
	{
		PrintToChat(client, "%s You get %s from the next map on (the server has just added it).", PREFIX, g_SkinName[now]);
		return;
	}
	bool fits = false;
	if (IsPlayerAlive(client))
	{
		GetClientModel(client, model, sizeof(model));
		fits = SameModel(model, g_SkinBase[now]) || SkinOfModel(model) >= 0;
	}
	if (fits)
		PrintToChat(client, "%s You now look like: %s.", PREFIX, label);
	else if (g_SkinClass[now][0] != '\0')
		PrintToChat(client, "%s Your skin: %s. It shows while you play %s.", PREFIX, g_SkinName[now], g_SkinClass[now]);
	else
		PrintToChat(client, "%s Your skin: %s. It shows while your player model is %s.", PREFIX, g_SkinName[now], g_SkinBase[now]);
}

// on a listen server the host's console runs commands as the server: treat them as the host's
int SkinCommandClient(int client)
{
	if (client == 0 && !IsDedicatedServer() && IsClientInGame(1) && !IsFakeClient(1))
		client = 1;
	if (client <= 0 || !IsClientInGame(client))
	{
		ReplyToCommand(client, "[Hats] This command is for players in the game.");
		return 0;
	}
	if (!g_cvSkins.BoolValue || g_SkinCount == 0)
	{
		ReplyToCommand(client, "[Hats] This server has no player skins.");
		return 0;
	}
	return client;
}

public Action Cmd_Skin(int client, int args)
{
	client = SkinCommandClient(client);
	if (client == 0)
		return Plugin_Handled;
	if (args < 1)
	{
		ShowSkinMenu(client);
		return Plugin_Handled;
	}
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if (StrEqual(arg, "list", false))
	{
		char line[512] = "off", label[128];
		for (int i = 0; i < g_SkinCount; i++)
		{
			SkinLabel(i, label, sizeof(label));
			Format(line, sizeof(line), "%s, %s = %s", line, g_SkinId[i], label);
		}
		PrintToChat(client, "%s !skin <id>: %s", PREFIX, line);
	}
	else
		SetSkinChoice(client, arg);
	return Plugin_Handled;
}

public Action Cmd_Pink(int client, int args)
{
	client = SkinCommandClient(client);
	if (client == 0)
		return Plugin_Handled;
	int pink = FindSkin("pink");
	if (pink < 0)
	{
		ReplyToCommand(client, "[Hats] This server has no pink skin.");
		return Plugin_Handled;
	}
	SetSkinChoice(client, WantedSkin(client) == pink ? "none" : "pink");
	return Plugin_Handled;
}

public Action Cmd_SkinForce(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[Hats] usage: sm_skin_force <target> <skin id | off | reset>  (reset = the player's own choice again)");
		return Plugin_Handled;
	}
	char target[MAX_TARGET_LENGTH], id[32], force[32];
	GetCmdArg(1, target, sizeof(target));
	GetCmdArg(2, id, sizeof(id));
	if (StrEqual(id, "off", false) || StrEqual(id, "none", false))
		strcopy(force, sizeof(force), "none");
	else if (!StrEqual(id, "reset", false))
	{
		int idx = FindSkin(id);
		if (idx < 0)
		{
			ReplyToCommand(client, "[Hats] unknown skin '%s' (%d skin(s) on this server)", id, g_SkinCount);
			return Plugin_Handled;
		}
		strcopy(force, sizeof(force), g_SkinId[idx]);
	}
	int targets[MAXPLAYERS];
	char targetName[MAX_TARGET_LENGTH];
	bool ml;
	int n = ProcessTargetString(target, client, targets, sizeof(targets), 0, targetName, sizeof(targetName), ml);
	if (n <= 0)
	{
		ReplyToTargetError(client, n);
		return Plugin_Handled;
	}
	for (int i = 0; i < n; i++)
		strcopy(g_SkinForce[targets[i]], sizeof(g_SkinForce[]), force);
	ReplyToCommand(client, "[Hats] skin of %s: %s%s", targetName, force[0] != '\0' ? force : "their own choice",
		g_cvSkins.BoolValue ? "" : " (but sm_hats_skins is 0)");
	return Plugin_Handled;
}

public Action Cmd_PlushTune(int client, int args)
{
	char who[PLATFORM_MAX_PATH], what[16], a[16];
	GetCmdArg(1, who, sizeof(who));
	GetCmdArg(2, what, sizeof(what));
	if (args < 3)
	{
		ReplyToCommand(client, "[Hats] usage: sm_plush_tune <player model, e.g. light_punk | default> pos <x> <y> <z> | ang <p> <y> <r> | att <attachment> ; sm_plush_tune all scale <s>");
		return Plugin_Handled;
	}
	if (StrEqual(what, "scale", false))
	{
		GetCmdArg(3, a, sizeof(a));
		g_PlushScale = StringToFloat(a) > 0.0 ? StringToFloat(a) : 1.0;
		for (int c = 1; c <= MaxClients; c++)
			g_PlushOnModel[c][0] = '\0';
		ReplyToCommand(client, "[Hats] for the \"plush\" block: \"scale\" \"%.2f\"", g_PlushScale);
		return Plugin_Handled;
	}
	if (!StrEqual(who, "default", false) && StrContains(who, "/") == -1)
		Format(who, sizeof(who), "models/player/%s.mdl", who);  // short form: light_punk
	int i = FindPlushEntry(who);
	if (i < 0)
	{
		int d = FindPlushEntry("default");
		if (d >= 0)
			AddPlushModel(who, g_PlushAtt[d], g_PlushPos[d][0], g_PlushPos[d][1], g_PlushPos[d][2], g_PlushAng[d][0], g_PlushAng[d][1], g_PlushAng[d][2]);
		else
			AddPlushModel(who, "eyes", -24.0, 0.0, -30.5, 0.0, 0.0, 0.0);
		i = FindPlushEntry(who);
		if (i < 0)
		{
			ReplyToCommand(client, "[Hats] too many plush placements");
			return Plugin_Handled;
		}
	}
	if (StrEqual(what, "att", false))
		GetCmdArg(3, g_PlushAtt[i], sizeof(g_PlushAtt[]));
	else if (args >= 5 && (StrEqual(what, "pos", false) || StrEqual(what, "ang", false)))
	{
		for (int k = 0; k < 3; k++)
		{
			GetCmdArg(3 + k, a, sizeof(a));
			if (StrEqual(what, "pos", false))
				g_PlushPos[i][k] = StringToFloat(a);
			else
				g_PlushAng[i][k] = StringToFloat(a);
		}
	}
	else
	{
		ReplyToCommand(client, "[Hats] usage: sm_plush_tune <player model, e.g. light_punk | default> pos <x> <y> <z> | ang <p> <y> <r> | att <attachment>");
		return Plugin_Handled;
	}
	for (int c = 1; c <= MaxClients; c++)
		g_PlushOnModel[c][0] = '\0';  // re-attach with the new values
	ReplyToCommand(client, "[Hats] for the \"plush\" block: \"%s\" { \"attachment\" \"%s\" \"pos\" \"%.1f %.1f %.1f\" \"ang\" \"%.0f %.0f %.0f\" }",
		g_PlushFor[i], g_PlushAtt[i], g_PlushPos[i][0], g_PlushPos[i][1], g_PlushPos[i][2], g_PlushAng[i][0], g_PlushAng[i][1], g_PlushAng[i][2]);
	return Plugin_Handled;
}

public Action Cmd_Reload(int client, int args)
{
	LoadConfig();
	PrecacheHats();
	RegisterSkins(false);
	ReplyToCommand(client, "[Hats] %d hat(s) and %d skin(s) loaded.", g_HatCount, g_SkinCount);
	return Plugin_Handled;
}

public Action Cmd_Tune(int client, int args)
{
	char id[32], what[16], a[16];
	GetCmdArg(1, id, sizeof(id));
	GetCmdArg(2, what, sizeof(what));
	int idx = FindHat(id);
	if (idx < 0 || args < 3)
	{
		ReplyToCommand(client, "[Hats] usage: sm_hats_tune <id> pos <fwd> <left> <up> | ang <pitch> <yaw> <roll> | scale <s>");
		return Plugin_Handled;
	}
	if (StrEqual(what, "scale", false))
	{
		GetCmdArg(3, a, sizeof(a));
		g_HatScale[idx] = StringToFloat(a) > 0.0 ? StringToFloat(a) : 1.0;
	}
	else if (args >= 5 && (StrEqual(what, "pos", false) || StrEqual(what, "ang", false)))
	{
		for (int k = 0; k < 3; k++)
		{
			GetCmdArg(3 + k, a, sizeof(a));
			if (StrEqual(what, "pos", false))
				g_HatPos[idx][k] = StringToFloat(a);
			else
				g_HatAng[idx][k] = StringToFloat(a);
		}
	}
	else
	{
		ReplyToCommand(client, "[Hats] usage: sm_hats_tune <id> pos <fwd> <left> <up> | ang <pitch> <yaw> <roll> | scale <s>");
		return Plugin_Handled;
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_HatWorn[i] == idx)
			g_HatWorn[i] = -1;  // re-attach with the new values
	}
	ReplyToCommand(client, "[Hats] for configs/dys_hats.cfg: \"%s\" { \"pos\" \"%.1f %.1f %.1f\" \"ang\" \"%.0f %.0f %.0f\" \"scale\" \"%.2f\" }",
		g_HatId[idx], g_HatPos[idx][0], g_HatPos[idx][1], g_HatPos[idx][2],
		g_HatAng[idx][0], g_HatAng[idx][1], g_HatAng[idx][2], g_HatScale[idx]);
	return Plugin_Handled;
}

// Where does an offset from the "eyes" attachment end up in the world? A probe entity is attached
// like a hat and then unparented: unparenting keeps the world position in m_vecOrigin.
bool ProbeOffset(int client, const float local[3], const float lang[3], float pos[3], float ang[3])
{
	int ent = CreateEntityByName("prop_dynamic_override");
	if (ent <= 0)
		return false;
	DispatchKeyValue(ent, "model", g_HatModel[0]);
	DispatchKeyValue(ent, "solid", "0");
	DispatchSpawn(ent);
	SetVariantString("!activator");
	AcceptEntityInput(ent, "SetParent", client, ent);
	SetVariantString("eyes");
	AcceptEntityInput(ent, "SetParentAttachment", ent, ent);
	TeleportEntity(ent, local, lang, NULL_VECTOR);
	AcceptEntityInput(ent, "ClearParent");
	GetEntPropVector(ent, Prop_Data, "m_vecOrigin", pos);
	GetEntPropVector(ent, Prop_Data, "m_angRotation", ang);
	RemoveEntity(ent);
	return true;
}

// world point -> forward / left / up of the player's view (pitch ignored), relative to the eyes
void ToViewFrame(int client, const float p[3], float out[3])
{
	float eye[3], va[3], fwd[3], right[3], up[3], d[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, va);
	va[0] = 0.0;
	va[2] = 0.0;
	GetAngleVectors(va, fwd, right, up);
	SubtractVectors(p, eye, d);
	out[0] = GetVectorDotProduct(d, fwd);
	out[1] = -GetVectorDotProduct(d, right);
	out[2] = GetVectorDotProduct(d, up);
}

public Action Cmd_Tf2View(int client, int args)
{
	char a[8];
	GetCmdArg(1, a, sizeof(a));
	int target = StringToInt(a);
	GetCmdArg(2, a, sizeof(a));
	if (args < 2 || target < 1 || target > MaxClients)  // any slot: SourceMod doesn't count SourceTV as connected
	{
		ReplyToCommand(client, "[Hats] usage: sm_hats_tf2view <client index> <0|1>");
		return Plugin_Handled;
	}
	g_ViewerTf2[target] = StringToInt(a) != 0;
	ReplyToCommand(client, "[Hats] client %d now %s TF2 hats", target, g_ViewerTf2[target] ? "sees" : "does not see");
	return Plugin_Handled;
}

public Action Cmd_Dump(int client, int args)
{
	ReplyToCommand(client, "[Hats] %d hat(s); SetTransmit calls %d, hidden %d; TF2 hats refused %d, stand-ins refused %d",
		g_HatCount, g_TransmitCalls, g_TransmitHidden, g_KindBlocked[KIND_TF2], g_KindBlocked[KIND_FALLBACK]);
	for (int s = 0; s < g_SkinCount; s++)
		ReplyToCommand(client, "[Hats] skin '%s': %s replaces %s, %s, precached %d", g_SkinId[s], g_SkinModel[s], g_SkinBase[s],
			SkinLive(s) ? "live" : "not live (from the next map on)", IsModelPrecached(g_SkinModel[s]));
	char model[PLATFORM_MAX_PATH];
	float zero[3], p[3], a[3], f[3], probe[3], ax[3], az[3], fx[3], fz[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		GetClientModel(i, model, sizeof(model));
		int hat = EntRefToEntIndex(g_HatRef[i]);
		int fb = EntRefToEntIndex(g_FallbackRef[i]);
		ReplyToCommand(client, "[Hats] #%d %N team %d alive %d model %s cyber %d camo %d hat %s ent %d (kind %d) stand-in ent %d; sees TF2 hats %d",
			i, i, GetClientTeam(i), IsPlayerAlive(i), model, InCyberspace(i, model), Camouflage(i),
			g_HatWorn[i] >= 0 ? g_HatId[g_HatWorn[i]] : "-", hat, hat > 0 ? g_EntKind[hat] : -1, fb, g_ViewerTf2[i]);
		int plush = EntRefToEntIndex(g_PlushRef[i]);
		if (plush > 0 || WantsPlush(i))
			ReplyToCommand(client, "[Hats]    plush: wanted %d ent %d on %s", WantsPlush(i), plush, g_PlushOnModel[i]);
		int wears = SkinOfModel(model);
		int wants = WantedSkin(i);
		if (wears >= 0 || wants >= 0 || g_SkinChoice[i][0] != '\0' || g_SkinForce[i][0] != '\0')
			ReplyToCommand(client, "[Hats]    skin: wears %s, wants %s (choice '%s', forced '%s'%s), m_nSkin %d",
				wears >= 0 ? g_SkinId[wears] : "-", wants >= 0 ? g_SkinId[wants] : "-", g_SkinChoice[i], g_SkinForce[i],
				(wants >= 0 && !SkinLive(wants)) ? ", not live until the next map" : "", GetEntProp(i, Prop_Send, "m_nSkin"));
		if (hat <= 0)
			continue;
		int idx = g_HatWorn[i];
		// the attachment itself, a point 10 u along its x axis and one 10 u along its z axis
		ProbeOffset(i, zero, zero, p, a);
		ToViewFrame(i, p, f);
		probe[0] = 10.0;
		ProbeOffset(i, probe, zero, ax, a);
		probe[0] = 0.0;
		probe[2] = 10.0;
		ProbeOffset(i, probe, zero, az, a);
		ToViewFrame(i, ax, fx);
		ToViewFrame(i, az, fz);
		ReplyToCommand(client, "[Hats]    eyes attachment: fwd %.1f left %.1f up %.1f from the eye position; its x axis -> (%.2f %.2f %.2f), z axis -> (%.2f %.2f %.2f) in view fwd/left/up",
			f[0], f[1], f[2], (fx[0] - f[0]) / 10.0, (fx[1] - f[1]) / 10.0, (fx[2] - f[2]) / 10.0,
			(fz[0] - f[0]) / 10.0, (fz[1] - f[1]) / 10.0, (fz[2] - f[2]) / 10.0);
		ProbeOffset(i, g_HatPos[idx], g_HatAng[idx], p, a);
		ToViewFrame(i, p, f);
		ReplyToCommand(client, "[Hats]    hat origin: fwd %.1f left %.1f up %.1f from the eye position, angles %.0f %.0f %.0f",
			f[0], f[1], f[2], a[0], a[1], a[2]);
		if (args > 0)
		{
			float raw[3], loc[3], org[3], eye[3];
			GetEntPropVector(hat, Prop_Data, "m_vecAbsOrigin", raw);
			GetEntPropVector(hat, Prop_Data, "m_vecOrigin", loc);
			GetClientAbsOrigin(i, org);
			GetClientEyePosition(i, eye);
			ReplyToCommand(client, "[Hats]    raw: hat abs (%.1f %.1f %.1f) local (%.1f %.1f %.1f) attachment %d; player origin (%.1f %.1f %.1f) eye (%.1f %.1f %.1f)",
				raw[0], raw[1], raw[2], loc[0], loc[1], loc[2], GetEntProp(hat, Prop_Send, "m_iParentAttachment"),
				org[0], org[1], org[2], eye[0], eye[1], eye[2]);
			// the same probe parented to the player origin (no attachment)
			int ent = CreateEntityByName("prop_dynamic_override");
			DispatchKeyValue(ent, "model", g_HatModel[0]);
			DispatchKeyValue(ent, "solid", "0");
			DispatchSpawn(ent);
			SetVariantString("!activator");
			AcceptEntityInput(ent, "SetParent", i, ent);
			probe[0] = 0.0;
			probe[2] = 10.0;
			TeleportEntity(ent, probe, zero, NULL_VECTOR);
			AcceptEntityInput(ent, "ClearParent");
			GetEntPropVector(ent, Prop_Data, "m_vecOrigin", raw);
			RemoveEntity(ent);
			ReplyToCommand(client, "[Hats]    probe without attachment, 10 u up: (%.1f %.1f %.1f)", raw[0], raw[1], raw[2]);
			char poses[256];
			for (int k = 0; k < 8; k++)
				Format(poses, sizeof(poses), "%s %.2f", poses, GetEntPropFloat(i, Prop_Send, "m_flPoseParameter", k));
			ReplyToCommand(client, "[Hats]    pose parameters:%s; sequence %d cycle %.2f", poses, GetEntProp(i, Prop_Send, "m_nSequence"), GetEntPropFloat(i, Prop_Send, "m_flCycle"));
		}
	}
	return Plugin_Handled;
}
