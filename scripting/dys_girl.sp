/**
 * dys_girl - the Pink Light Punk player model for Dystopia (SourceMod plugin).
 *
 * A player skin is a custom player model that stands in for ONE stock class model (its "base") for the players who
 * pick it. The one in this repo is the Pink Light Punk (models/player/light_punk_pink.mdl): a female light punk on
 * the stock light_punk skeleton, animations, attachments and hitboxes. Nobody gets it by default.
 *
 *   !pink            switch the Pink Light Punk on / off (it shows while you play Punk Light)
 *   !skin            menu (also sm_skin in the console)
 *   !skin <id>       that skin, e.g. !skin pink
 *   !skin off        the stock models
 *   !skin list       print the skin ids
 *
 * Skins are the one thing players download: the server needs the repo's content/ folder in dystopia/, and the plugin
 * puts each skin's model and materials into the download table at every map start. A player is switched only while
 * their current model is the skin's base model; other classes and the cyberspace avatar are never touched.
 *
 * Needs SDKTools' SetEntityModel to work on Dystopia, i.e. the corrected offsets of this repo
 * (gamedata/sdktools.games/custom/game.dystopia.txt, the same file dys_hats needs).
 * The skins list lives in addons/sourcemod/configs/dys_girl.cfg.
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
#undef REQUIRE_EXTENSIONS
#include <clientprefs>
#define REQUIRE_EXTENSIONS

#define PLUGIN_VERSION "1.0.0"
#define MAX_SKINS 16
#define PREFIX "\x04[Skin]\x01"

public Plugin myinfo =
{
	name = "Dystopia Girl",
	author = "atomy",
	description = "Opt-in player skins: !pink switches to the Pink Light Punk, !skin picks one",
	version = PLUGIN_VERSION,
	url = "https://github.com/atomy/dys_hat"
};

ConVar g_cvEnabled;
ConVar g_cvDefault;
ConVar g_cvBots;
ConVar g_cvDebug;

Handle g_Cookie = null;
bool g_Late;

// skins (the "skins" block of configs/dys_girl.cfg, or the built-in pink one); only skins whose model exists
char g_SkinId[MAX_SKINS][32];
char g_SkinName[MAX_SKINS][64];
char g_SkinClass[MAX_SKINS][32];                         // shown to players, e.g. "Punk Light"
char g_SkinModel[MAX_SKINS][PLATFORM_MAX_PATH];
char g_SkinBase[MAX_SKINS][PLATFORM_MAX_PATH];           // the stock model it stands in for (and only that one)
char g_SkinMaterials[MAX_SKINS][PLATFORM_MAX_PATH];      // folder whose files go to the download table
int g_SkinCount;
StringMap g_LiveModels;   // skin models that were in the download table when this map started (lowercase path)
bool g_Blocked;           // late load with players in the game: they have no skin files until the next map
char g_ModelExt[][] = { ".vvd", ".dx90.vtx", ".dx80.vtx", ".sw.vtx", ".phy" };

// per player
char g_Choice[MAXPLAYERS + 1][32];                      // "" = sm_girl_default, "none" or a skin id (also unknown ones)
char g_Force[MAXPLAYERS + 1][32];                       // sm_skin_force: "" = no override, "none" or a skin id
float g_SpawnTime[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_Late = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_girl_version", PLUGIN_VERSION, "Dystopia Girl version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_girl_enabled", "1", "1 = players may use player skins (!pink, !skin); the skin files go to the download table", _, true, 0.0, true, 1.0);
	g_cvDefault = CreateConVar("sm_girl_default", "none", "Skin id for players who never picked one (\"none\" = the stock models)");
	g_cvBots = CreateConVar("sm_girl_bots", "0", "Bots: 0 = never a skin, 1 = the default skin (sm_girl_default)", _, true, 0.0, true, 1.0);
	g_cvDebug = CreateConVar("sm_girl_debug", "0", "1 = log every model switch and the download table", _, true, 0.0, true, 1.0);
	g_LiveModels = new StringMap();

	RegConsoleCmd("sm_skin", Cmd_Skin, "!skin: player skin menu; !skin <id> | off | list");
	RegConsoleCmd("sm_pink", Cmd_Pink, "!pink: switch the Pink Light Punk on / off");
	RegAdminCmd("sm_skin_force", Cmd_Force, ADMFLAG_CONFIG, "sm_skin_force <target> <id|off|reset>: set the skin of any player, bots too (test what others see)");
	RegAdminCmd("sm_girl_reload", Cmd_Reload, ADMFLAG_CONFIG, "Reload configs/dys_girl.cfg");
	RegAdminCmd("sm_girl_dump", Cmd_Dump, ADMFLAG_CONFIG, "Print every player's model, skin and wanted skin (debug)");

	HookEventEx("player_spawn", Event_Spawn);

	if (GetExtensionFileStatus("clientprefs.ext") == 1)
		g_Cookie = RegClientCookie("dys_girl_skin", "Dystopia Girl: chosen player skin", CookieAccess_Protected);

	for (int i = 1; i <= MaxClients; i++)
		ResetClient(i);

	LoadConfig();
	CreateTimer(0.2, Timer_Tick, _, TIMER_REPEAT);

	if (g_Late)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientConnected(i))
				continue;
			if (IsClientInGame(i) && g_Cookie != null && AreClientCookiesCached(i))
				OnClientCookiesCached(i);
			if (!IsFakeClient(i))
				g_Blocked = true;
		}
		if (g_Blocked && g_SkinCount > 0)
			LogMessage("Loaded during a map with players in the game: player skins start at the next map (they need the download first)");
	}
}

public void OnPluginEnd()
{
	// nobody keeps a skin the plugin no longer manages
	char model[PLATFORM_MAX_PATH];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		GetClientModel(i, model, sizeof(model));
		int s = SkinOfModel(model);
		if (s >= 0)
			SetPlayerModel(i, g_SkinBase[s], "unload");
	}
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
		g_SpawnTime[i] = 0.0;
	RegisterSkins(true);
}

public void OnMapEnd()
{
	g_Blocked = false;  // everyone reconnects for the next map and downloads the skins then
}

public void OnConfigsExecuted()
{
	// the settings in configs/dys_girl.cfg win over server.cfg (it runs before SourceMod loads plugins)
	LoadConfig();
	RegisterSkins(true);
	// server.cfg has run by now
	ConVar allow = FindConVar("sv_allowdownload");
	ConVar url = FindConVar("sv_downloadurl");
	char dl[8];
	if (url != null)
		url.GetString(dl, sizeof(dl));
	if (g_cvEnabled.BoolValue && g_SkinCount > 0 && allow != null && !allow.BoolValue && dl[0] == '\0')
		LogError("sv_allowdownload is 0 and there is no sv_downloadurl: players can't download the player skins (they would see an ERROR model)");
}

// ---------------------------------------------------------------------------------------------
// config

int FindSkin(const char[] id)
{
	for (int i = 0; i < g_SkinCount; i++)
	{
		if (StrEqual(g_SkinId[i], id, false))
			return i;
	}
	return -1;
}

void AddSkin(const char[] id, const char[] name, const char[] cls, const char[] model, const char[] base, const char[] materials)
{
	if (g_SkinCount >= MAX_SKINS)
		return;
	if (StrEqual(id, "none", false) || StrEqual(id, "off", false) || StrEqual(id, "default", false) || StrEqual(id, "list", false)
		|| StrEqual(id, "reset", false))
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
		// skins switched off: a missing model is not worth an error
		if (g_cvEnabled.BoolValue)
			LogError("skin '%s': model %s not found (copy the content/ folder of the dys_hat repo into dystopia/), skipped", id, model);
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

// The same as the "skins" block of configs/dys_girl.cfg, used when the config has none.
void AddBuiltinSkins()
{
	AddSkin("pink", "Pink Light Punk", "Punk Light", "models/player/light_punk_pink.mdl", "models/player/light_punk.mdl",
		"materials/models/player/light_punk_pink");
}

// the "skins" block of the config (kv at its root); false = there is none
bool ReadSkins(KeyValues kv)
{
	if (!kv.JumpToKey("skins"))
		return false;
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
			AddSkin(id, name, cls, model, base, materials);
		} while (kv.GotoNextKey());
		kv.GoBack();
	}
	kv.GoBack();
	return true;
}

void LoadConfig()
{
	g_SkinCount = 0;
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/dys_girl.cfg");
	KeyValues kv = new KeyValues("DysGirl");
	if (!kv.ImportFromFile(path))
	{
		delete kv;
		AddBuiltinSkins();
		LogMessage("configs/dys_girl.cfg not found, using the %d built-in skin(s)", g_SkinCount);
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
				if (StrContains(key, "sm_girl_", false) != 0 || StrEqual(key, "sm_girl_version", false))
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

	bool found = ReadSkins(kv);
	delete kv;
	if (!found)
		AddBuiltinSkins();
	LogMessage("Read %d skin(s) and %d setting(s) from configs/dys_girl.cfg", g_SkinCount, settings);
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
// and after sm_girl_reload. Only a map-start registration makes a skin live: players who are in the game already when a
// skin shows up mid-map (late load, reload, sm_girl_enabled 0 -> 1) never downloaded it and would see an ERROR model.
void RegisterSkins(bool mapStart)
{
	if (mapStart)
		g_LiveModels.Clear();
	if (!g_cvEnabled.BoolValue || g_SkinCount == 0)
		return;
	char key[PLATFORM_MAX_PATH];
	for (int i = 0; i < g_SkinCount; i++)
	{
		int files = AddSkinDownloads(i);
		PrecacheModel(g_SkinModel[i], true);
		if (mapStart && !g_Blocked)
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
		for (int k = 0; k < sizeof(g_ModelExt); k++)
		{
			Format(path, sizeof(path), "%s%s", base, g_ModelExt[k]);
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

// ---------------------------------------------------------------------------------------------
// players

void ResetClient(int client)
{
	g_Choice[client][0] = '\0';
	g_Force[client][0] = '\0';
	g_SpawnTime[client] = 0.0;
}

public void OnClientConnected(int client)
{
	ResetClient(client);
}

public void OnClientCookiesCached(int client)
{
	if (g_Cookie == null || IsFakeClient(client))
		return;
	// "none" or a skin id; an id this server doesn't have is kept (it may come back) and means no skin meanwhile
	char id[32];
	GetClientCookie(client, g_Cookie, id, sizeof(id));
	TrimString(id);
	if (StrEqual(id, "default", false))
		id[0] = '\0';
	strcopy(g_Choice[client], sizeof(g_Choice[]), id);
}

// the skin this player should have (-1 = the stock model): sm_skin_force, else bots per sm_girl_bots, else the
// player's !skin choice ("" = sm_girl_default)
int WantedSkin(int client)
{
	if (!g_cvEnabled.BoolValue)
		return -1;
	char id[32];
	if (g_Force[client][0] != '\0')
		strcopy(id, sizeof(id), g_Force[client]);
	else if (IsFakeClient(client))
	{
		if (IsClientSourceTV(client) || IsClientReplay(client) || !g_cvBots.BoolValue)
			return -1;
		g_cvDefault.GetString(id, sizeof(id));
	}
	else if (g_Choice[client][0] == '\0')
		g_cvDefault.GetString(id, sizeof(id));
	else
		strcopy(id, sizeof(id), g_Choice[client]);
	return FindSkin(id);  // "none" or an unknown id: -1
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
// Dystopia sets the class model again at every spawn, so this runs after each spawn and on every tick.
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

// a living player in a team, not cloaked (nothing may give a stealther away), not jacked into cyberspace
void CheckClient(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) < 2 || Camouflage(client) > 0)
		return;
	char model[PLATFORM_MAX_PATH];
	GetClientModel(client, model, sizeof(model));
	if (!InCyberspace(client, model))
		TickSkin(client, model);
}

public void Event_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0)
		return;
	g_SpawnTime[client] = GetGameTime();
	// the spawn sets the stock class model: put the skin back on one frame later (the tick catches a later reset)
	if (g_SkinCount > 0)
		RequestFrame(Frame_Spawn, GetClientUserId(client));
}

public void Frame_Spawn(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0)
		CheckClient(client);
}

public Action Timer_Tick(Handle timer)
{
	if (g_SkinCount == 0)
		return Plugin_Continue;
	float now = GetGameTime();
	for (int client = 1; client <= MaxClients; client++)
	{
		// let the spawn set the class model first (the frame after the spawn handles that)
		if (IsClientInGame(client) && now - g_SpawnTime[client] >= 0.2)
			CheckClient(client);
	}
	return Plugin_Continue;
}

// ---------------------------------------------------------------------------------------------
// commands

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
		SetChoice(client, id);
	}
	else if (action == MenuAction_End)
		delete menu;
	return 0;
}

void SetChoice(int client, const char[] id)
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
	strcopy(g_Choice[client], sizeof(g_Choice[]), choice);
	g_Force[client][0] = '\0';  // the player's own pick ends an admin's sm_skin_force
	if (g_Cookie != null && AreClientCookiesCached(client))
		SetClientCookie(client, g_Cookie, choice[0] != '\0' ? choice : "default");
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
		ReplyToCommand(client, "[Skin] This command is for players in the game.");
		return 0;
	}
	if (!g_cvEnabled.BoolValue || g_SkinCount == 0)
	{
		ReplyToCommand(client, "[Skin] This server has no player skins.");
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
		SetChoice(client, arg);
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
		ReplyToCommand(client, "[Skin] This server has no pink skin.");
		return Plugin_Handled;
	}
	SetChoice(client, WantedSkin(client) == pink ? "none" : "pink");
	return Plugin_Handled;
}

public Action Cmd_Force(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[Skin] usage: sm_skin_force <target> <skin id | off | reset>  (reset = the player's own choice again)");
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
			ReplyToCommand(client, "[Skin] unknown skin '%s' (%d skin(s) on this server)", id, g_SkinCount);
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
		strcopy(g_Force[targets[i]], sizeof(g_Force[]), force);
	ReplyToCommand(client, "[Skin] skin of %s: %s%s", targetName, force[0] != '\0' ? force : "their own choice",
		g_cvEnabled.BoolValue ? "" : " (but sm_girl_enabled is 0)");
	return Plugin_Handled;
}

public Action Cmd_Reload(int client, int args)
{
	// a skin the new config drops would stay on its wearers until they respawn: they get its base model back
	StringMap old = new StringMap();
	char key[PLATFORM_MAX_PATH], model[PLATFORM_MAX_PATH], base[PLATFORM_MAX_PATH];
	for (int s = 0; s < g_SkinCount; s++)
	{
		ModelKey(g_SkinModel[s], key, sizeof(key));
		old.SetString(key, g_SkinBase[s]);
	}
	LoadConfig();
	RegisterSkins(false);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		GetClientModel(i, model, sizeof(model));
		ModelKey(model, key, sizeof(key));
		if (SkinOfModel(model) < 0 && old.GetString(key, base, sizeof(base)))
			SetPlayerModel(i, base, "skin dropped by sm_girl_reload");
	}
	delete old;
	ReplyToCommand(client, "[Skin] %d skin(s) loaded.", g_SkinCount);
	return Plugin_Handled;
}

public Action Cmd_Dump(int client, int args)
{
	ReplyToCommand(client, "[Skin] %d skin(s), sm_girl_enabled %d, late load waiting for the next map %d",
		g_SkinCount, g_cvEnabled.IntValue, g_Blocked);
	for (int s = 0; s < g_SkinCount; s++)
		ReplyToCommand(client, "[Skin] skin '%s': %s replaces %s, %s, precached %d", g_SkinId[s], g_SkinModel[s], g_SkinBase[s],
			SkinLive(s) ? "live" : "not live (from the next map on)", IsModelPrecached(g_SkinModel[s]));
	char model[PLATFORM_MAX_PATH];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		GetClientModel(i, model, sizeof(model));
		int wears = SkinOfModel(model);
		int wants = WantedSkin(i);
		ReplyToCommand(client, "[Skin] #%d %N team %d alive %d model %s: wears %s, wants %s (choice '%s', forced '%s'%s), m_nSkin %d, camo %d, cyber %d",
			i, i, GetClientTeam(i), IsPlayerAlive(i), model, wears >= 0 ? g_SkinId[wears] : "-", wants >= 0 ? g_SkinId[wants] : "-",
			g_Choice[i], g_Force[i], (wants >= 0 && !SkinLive(wants)) ? ", not live until the next map" : "",
			GetEntProp(i, Prop_Send, "m_nSkin"), Camouflage(i), InCyberspace(i, model));
	}
	return Plugin_Handled;
}
