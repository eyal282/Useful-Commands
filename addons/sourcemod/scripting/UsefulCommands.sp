// To do: Add weapon stats comparison based on what I used with Big Bertha

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include <emitsoundany>

#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude <cURL>
#tryinclude <socket>
#tryinclude <steamtools>
#tryinclude <SteamWorks>
#tryinclude <updater>  // Comment out this line to remove updater support by force.
#tryinclude <autoexecconfig>
#define REQUIRE_PLUGIN
#define REQUIRE_EXTENSIONS

#pragma newdecls required

#define PLUGIN_VERSION "6.1"

public Plugin myinfo = 
{
	name = "Useful commands",
	author = "Eyal282",
	description = "Useful commands",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?p=2617618"
}


enum Collision_Group_t
{
    COLLISION_GROUP_NONE  = 0,
    COLLISION_GROUP_DEBRIS,            // Collides with nothing but world and static stuff
    COLLISION_GROUP_DEBRIS_TRIGGER, // Same as debris, but hits triggers
    COLLISION_GROUP_INTERACTIVE_DEBRIS,    // Collides with everything except other interactive debris or debris
    COLLISION_GROUP_INTERACTIVE,    // Collides with everything except interactive debris or debris
    COLLISION_GROUP_PLAYER,
    COLLISION_GROUP_BREAKABLE_GLASS,
    COLLISION_GROUP_VEHICLE,
    COLLISION_GROUP_PLAYER_MOVEMENT,  // For HL2, same as Collision_Group_Player, for
                                        // TF2, this filters out other players and CBaseObjects
    COLLISION_GROUP_NPC,            // Generic NPC group
    COLLISION_GROUP_IN_VEHICLE,        // for any entity inside a vehicle
    COLLISION_GROUP_WEAPON,            // for any weapons that need collision detection
    COLLISION_GROUP_VEHICLE_CLIP,    // vehicle clip brush to restrict vehicle movement
    COLLISION_GROUP_PROJECTILE,        // Projectiles!
    COLLISION_GROUP_DOOR_BLOCKER,    // Blocks entities not permitted to get near moving doors
    COLLISION_GROUP_PASSABLE_DOOR,    // Doors that the player shouldn't collide with
    COLLISION_GROUP_DISSOLVING,        // Things that are dissolving are in this group
    COLLISION_GROUP_PUSHAWAY,        // Nonsolid on client and server, pushaway in player code

    COLLISION_GROUP_NPC_ACTOR,        // Used so NPCs in scripts ignore the player.
    COLLISION_GROUP_NPC_SCRIPTED,    // USed for NPCs in scripts that should not collide with each other

    LAST_SHARED_COLLISION_GROUP
}; 

#define FPERM_ULTIMATE (FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC|FPERM_G_READ|FPERM_G_WRITE|FPERM_G_EXEC|FPERM_O_READ|FPERM_O_WRITE|FPERM_O_EXEC)

#define MAX_CSGO_LEVEL 40

#define ITEMS_GAME_PATH "scripts/items/items_game.txt"
#define CACHE_ITEMS_GAME_PATH "data/UsefulCommands"

#define MAX_INTEGER 2147483647
#define MIN_FLOAT -2147483647.0 // I think -2147483648 is lowest but meh, same thing.

#define CHRISTMASS_PRESENT_BODYINDEX 1

#define MAX_POSSIBLE_HP 32767
#define MAX_POSSIBLE_MONEY 65535
// I'll redefine these if needed. I doubt they'll change.

#define HEADSHOT_MULTIPLIER 4.0
#define STOMACHE_MULTIPLIER 1.25
#define CHEST_MULTIPLIER 1.0
#define LEGS_MULTIPLIER 0.75 // Also legs are immune to kevlar and yes, bizon is stronger on legs than kevlar chest.

#define HUD_PRINTCENTER        4 

#define GAME_RULES_CVARS_PATH "gamerulescvars.txt"

#define UPDATE_URL    "https://raw.githubusercontent.com/eyal282/Useful-Commands/master/addons/sourcemod/updatefile.txt"

#define COMMAND_FILTER_NONE 0

#define MAX_HUG_DISTANCE 100.0

#define GLOW_WALLHACK 0
#define GLOW_FULLBODY 1
#define GLOW_SURROUNDPLAYER 2
#define GLOW_SURROUNDPLAYER_BLINKING 3 

#define EF_BONEMERGE                (1 << 0)
#define EF_NOSHADOW                 (1 << 4)
#define EF_NORECEIVESHADOW          (1 << 6)
#define EF_PARENT_ANIMATES          (1 << 9)

#define PARTYMODE_NONE 0
#define PARTYMODE_DEFUSE (1<<0)
#define PARTYMODE_ZEUS (1<<1)

#define CURL_AVAILABLE()		(GetFeatureStatus(FeatureType_Native, "curl_easy_init") == FeatureStatus_Available)
#define SOCKET_AVAILABLE()		(GetFeatureStatus(FeatureType_Native, "SocketCreate") == FeatureStatus_Available)
#define STEAMTOOLS_AVAILABLE()	(GetFeatureStatus(FeatureType_Native, "Steam_CreateHTTPRequest") == FeatureStatus_Available)
#define STEAMWORKS_AVAILABLE()	(GetFeatureStatus(FeatureType_Native, "SteamWorks_WriteHTTPResponseBodyToFile") == FeatureStatus_Available)

#define EXTENSION_ERROR		"This plugin requires one of the cURL, Socket, SteamTools, or SteamWorks extensions to function."

char UCTag[65];

int ChickenOriginPosition;

char Colors[][] = 
{
	"{NORMAL}", "{RED}", "{GREEN}", "{LIGHTGREEN}", "{OLIVE}", "{LIGHTRED}", "{GRAY}", "{YELLOW}", "{ORANGE}", "{BLUE}", "{PINK}"
}

char ColorEquivalents[][] =
{
	"\x01", "\x02", "\x03", "\x04", "\x05", "\x06", "\x07", "\x08", "\x09", "\x10", "\x0C", "\x0E"
}

enum FX
{
	FxNone = 0,
	FxPulseFast,
	FxPulseSlowWide,
	FxPulseFastWide,
	FxFadeSlow,
	FxFadeFast,
	FxSolidSlow,
	FxSolidFast,
	FxStrobeSlow,
	FxStrobeFast,
	FxStrobeFaster,
	FxFlickerSlow,
	FxFlickerFast,
	FxNoDissipation,
	FxDistort,               // Distort/scale/translate flicker
	FxHologram,              // kRenderFxDistort + distance fade
	FxExplode,               // Scale up really big!
	FxGlowShell,             // Glowing Shell
	FxClampMinScale,         // Keep this sprite from getting very small (SPRITES only!)
	FxEnvRain,               // for environmental rendermode, make rain
	FxEnvSnow,               //  "        "            "    , make snow
	FxSpotlight,     
	FxRagdoll,
	FxPulseFastWider,
};

enum Render
{
	Normal = 0, 		// src
	TransColor, 		// c*a+dest*(1-a)
	TransTexture,		// src*a+dest*(1-a)
	Glow,				// src*a+dest -- No Z buffer checks -- Fixed size in screen space
	TransAlpha,			// src*srca+dest*(1-srca)
	TransAdd,			// src*a+dest
	Environmental,		// not drawn, used for environmental effects
	TransAddFrameBlend,	// use a fractional frame value to blend between animation frames
	TransAlphaAdd,		// src + dest*(1-a)
	WorldGlow,			// Same as kRenderGlow but not fixed size in screen space
	None,				// Don't render.
};

char PartySound[] = "weapons/party_horn_01.wav";
char ItemPickUpSound[] = "items/pickup_weapon_02.wav";

float DeathOrigin[MAXPLAYERS+1][3];

bool UberSlapped[MAXPLAYERS+1];
int TotalSlaps[MAXPLAYERS+1];

//new LastHolidayCvar = 0;

Handle Trie_UCCommands = INVALID_HANDLE;
Handle Trie_CoinLevelValues = INVALID_HANDLE;

Handle hcv_PartyMode = INVALID_HANDLE;
Handle hcv_mpAnyoneCanPickupC4 = INVALID_HANDLE;
Handle hcv_SolidTeammates = INVALID_HANDLE;
Handle hcv_mpRespawnOnDeathT = INVALID_HANDLE;
Handle hcv_mpRespawnOnDeathCT = INVALID_HANDLE;
Handle hcv_mpRoundTime = INVALID_HANDLE;
//new Handle:hcv_svCheats = INVALID_HANDLE;
//new svCheatsFlags = 0;

Handle hcv_ucSpecialC4Rules = INVALID_HANDLE;
Handle hcv_ucTeleportBomb = INVALID_HANDLE;
Handle hcv_ucUseBombPickup = INVALID_HANDLE;
Handle hcv_ucAcePriority = INVALID_HANDLE;
Handle hcv_ucMaxChickens = INVALID_HANDLE;
Handle hcv_ucMinChickenTime = INVALID_HANDLE;
Handle hcv_ucMaxChickenTime = INVALID_HANDLE;
Handle hcv_ucPartyMode = INVALID_HANDLE;
Handle hcv_ucPartyModeDefault = INVALID_HANDLE;
Handle hcv_ucAnnouncePlugin = INVALID_HANDLE;
Handle hcv_ucReviveOnTeamChange = INVALID_HANDLE;
Handle hcv_ucPacketNotifyCvars = INVALID_HANDLE;
Handle hcv_ucGlowType = INVALID_HANDLE;
Handle hcv_ucTag = INVALID_HANDLE;
Handle hcv_ucRestartRoundOnMapStart = INVALID_HANDLE;
Handle hcv_ucIgnoreRoundWinConditions = INVALID_HANDLE;

Handle hCookie_EnablePM = INVALID_HANDLE;
Handle hCookie_AceFunFact = INVALID_HANDLE;

Handle TIMER_UBERSLAP[MAXPLAYERS+1] = INVALID_HANDLE;
Handle TIMER_LIFTOFF[MAXPLAYERS+1] = INVALID_HANDLE;
Handle TIMER_ROCKETCHECK[MAXPLAYERS+1] = INVALID_HANDLE;
Handle TIMER_LASTC4[MAXPLAYERS+1] = INVALID_HANDLE;
Handle TIMER_ANNOUNCEPLUGIN[MAXPLAYERS+1] = INVALID_HANDLE;

int AceCandidate[7]; // IDK How many teams there are...

int LastC4Ref[MAXPLAYERS+1] = INVALID_ENT_REFERENCE;

bool MapStarted = false;
char MapName[128];

int RoundNumber = 0;

Handle TeleportsArray = INVALID_HANDLE;
Handle BombResetsArray = INVALID_HANDLE;
Handle ChickenOriginArray = INVALID_HANDLE;

Handle fw_ucCountServerRestart = INVALID_HANDLE;
Handle fw_ucNotifyServerRestart = INVALID_HANDLE;
Handle fw_ucServerRestartAborted = INVALID_HANDLE;
Handle fw_ucAce = INVALID_HANDLE;
Handle fw_ucAcePost = INVALID_HANDLE;
Handle fw_ucWeaponStatsRetrievedPost = INVALID_HANDLE;

bool AceSent = false;
int TrueTeam[MAXPLAYERS+1];

bool g_bCursed[MAXPLAYERS + 1];

Database dbLocal, dbClientPrefs;

bool FullInGame[MAXPLAYERS+1];

char LastAuthStr[MAXPLAYERS+1][64];

float LastHeight[MAXPLAYERS+1];

Handle hRestartTimer = INVALID_HANDLE;
Handle hNotifyRestartTimer = INVALID_HANDLE;
Handle hRRTimer = INVALID_HANDLE;

bool RestartNR = false;
int RestartTimestamp = 0;

Handle hcv_TagScale = INVALID_HANDLE;

bool UCEdit[MAXPLAYERS+1];

int ClientGlow[MAXPLAYERS+1];

int RoundKills[MAXPLAYERS+1];

bool isHugged[MAXPLAYERS+1];

EngineVersion GameName;

bool isLateLoaded = false;

bool show_timer_defend, show_timer_attack;
int timer_time, final_event;
char funfact_token[256];
int funfact_player, funfact_data1, funfact_data2, funfact_data3;
bool BlockedWinPanel;

enum struct enGlow
{
	char GlowName[50];
	int GlowColorR;
	int GlowColorG;
	int GlowColorB;
}
enGlow GlowData[] =
{
	{ "Red", 255, 0, 0 },
	{ "Blue", 0, 0, 255 },
	{ "TAGrenade", 154, 50, 50 },
	{ "White", 255, 255, 255 } // White won't work in CSS.
};

enum struct enWepStatsList
{
	int wepStatsDamage;
	int wepStatsFireRate;
	float wepStatsArmorPenetration;
	int wepStatsKillAward;
	float wepStatsWallPenetration;
	int wepStatsDamageDropoff;
	int wepStatsMaxDamageRange;
	int wepStatsPalletsPerShot; // For shotguns
	int wepStatsDamagePerPallet;
	int wepStatsTapDistanceNoArmor;
	int wepStatsTapDistanceArmor;
	bool wepStatsIsAutomatic;
	int wepStatsDamagePerSecondNoArmor;
	int wepStatsDamagePerSecondArmor;
}

enWepStatsList wepStatsList[CSWeapon_MAX_WEAPONS_NO_KNIFES];

CSWeaponID wepStatsIgnore[] =
{
	CSWeapon_C4,
	CSWeapon_KNIFE,
	CSWeapon_SHIELD,
	CSWeapon_KEVLAR,
	CSWeapon_ASSAULTSUIT,
	CSWeapon_NIGHTVISION,
	CSWeapon_KNIFE_GG,
	CSWeapon_DEFUSER,
	CSWeapon_HEAVYASSAULTSUIT,
	CSWeapon_CUTTERS,
	CSWeapon_HEALTHSHOT,
	CSWeapon_KNIFE_T,
	CSWeapon_HEGRENADE,
	CSWeapon_TAGGRENADE,
	CSWeapon_FLASHBANG,
	CSWeapon_DECOY,
	CSWeapon_SMOKEGRENADE,
	CSWeapon_INCGRENADE,
	CSWeapon_MOLOTOV
}
public APLRes AskPluginLoad2(Handle myself, bool bLate, char[] error, int length)
{
	isLateLoaded = bLate;
	
	CreateNative("UsefulCommands_GetWeaponStats", Native_GetWeaponStatsList);
	CreateNative("UsefulCommands_ApproximateClientRank", Native_ApproximateClientRank);
	CreateNative("UsefulCommands_IsServerRestartScheduled", Native_IsServerRestartScheduled);
}

// native int UsefulCommands_GetWeaponStats(CSWeaponID WeaponID, int StatsList[])

public any Native_GetWeaponStatsList(Handle caller, int numParams)
{
	CSWeaponID WeaponID = GetNativeCell(1);
		
	if(!CS_IsValidWeaponID(WeaponID))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid weapon ID %i", WeaponID);
		return false;
	}
	
	SetNativeArray(2, wepStatsList[WeaponID], sizeof(wepStatsList[]));
	return true;
}

// native int UsefulCommands_ApproximateClientRank(int client);

// returns approximate rank.
// Note: if client has no service medals, returns exact rank.
// Note: if client has one medal, returns exact rank ONLY if it's equipped.
// Note: if client has more than one medal, does not return exact rank, however if you wanna filter out newbies, will work fine.
// Note: if you kick a client based on his rank, you should ask him to temporarily equip a service medal if he reset his rank recently, and you should cache that his steam ID is an acceptable rank.
// Note: don't use this on Counter-Strike: Source lol.

public int Native_ApproximateClientRank(Handle caller, int numParams)
{	
	int PlayerResourceEnt = GetPlayerResourceEntity();
	
	int client = GetNativeCell(1);
	
	if(!IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %i", client);
		return -1;
	}
	
	char sCoin[64], value, rank = GetEntProp(PlayerResourceEnt, Prop_Send, "m_nPersonaDataPublicLevel", _, client);
	IntToString(GetEntProp(PlayerResourceEnt, Prop_Send, "m_nActiveCoinRank", _, client), sCoin, sizeof(sCoin));
	
	if(rank == -1)
		rank = 0;
		
	if(GetTrieValue(Trie_CoinLevelValues, sCoin, value))
		rank += value;
	
	return rank;
}

// native bool UsefulCommands_IsServerRestartScheduled();
public int Native_IsServerRestartScheduled(Handle caller, int numParams)
{
	if(hRestartTimer != INVALID_HANDLE || RestartNR)
		return true;
		
	return false;
}

/*
* This forward is fired when an admin uses !restart [seconds]

* @return  					Amount of seconds your plugin demands waiting before restart is made. If returning more than the time input by !restart, it will fail.
*
*
* @notes					!restart defaults to 5 seconds. Returning more than that may burden the admins.
* @notes					While a completely bad practice, to stop all restarts you can workaround returning the biggest integer possible, 2147483647
*/

forward int UsefulCommands_OnCountServerRestart();

/*
* This forward is fired x seconds before restart, x being the highest returned value from the forward UsefulCommands_OnCountServerRestart
*
* @param SecondsLeft		Amount of seconds left before the restart, or -1 if the restart is scheduled to next round.
*
* @noreturn 
*
*
* @notes					This is called immediately on a next round based server restart
*/

forward void UsefulCommands_OnNotifyServerRestart(int SecondsLeft);

/*
* This forward is fired when an admin stops the server restart.
*
* @noreturn 
*/

forward void UsefulCommands_OnServerRestartAborted();
	
/*
* On Player Ace
*
* @param client				client index.
* @param FunFact			Fun Fact that appears on top of the screen.
* @param Kills				Kills done this round.

* @return  					Plugin_Continue to ignore, Plugin_Changed when changing a parameter, Plugin_Handled to block fun fact change,
							Plugin_Stop to stop both fun fact change and the post forward.
*
*
* @notes					Note: this forward may call more than once during a single ace.
*/

forward Action UsefulCommands_OnPlayerAce(int &client, char[] FunFact, int Kills);

	
/*
* On Player Ace Post
*
* @param client				client index.
* @param FunFact			Fun Fact that appears on top of the screen.
* @param Kills				Kills done this round.

* @noreturn
*
*
* @notes					Although the pre ace forward may call more than once in a single ace, this forward will only call once per ace.
*/

forward void UsefulCommands_OnPlayerAcePost(int client, const char[] FunFact, int Kills);



/*
* Called when the weapon stats natives can be used.
*
* @noreturn
*/

forward void UsefulCommands_OnWeaponStatsRetrievedPost();






public void UsefulCommands_OnPlayerAcePost(int client, const char[] FunFact, int Kills)
{
	if(GetConVarInt(hcv_ucAcePriority) > 0)
	{
		UC_PrintToChatAll("%s%t", UCTag, "Scored an Ace", client);
	}
}
	


public void OnPluginStart()
{
	TeleportsArray = CreateArray(1);
			
	BombResetsArray = CreateArray(1);
	
	GameName = GetEngineVersion();
	
	#if defined _autoexecconfig_included
	
	AutoExecConfig_SetFile("UsefulCommands");
	
	#endif
	
	Trie_UCCommands = CreateTrie();
	Trie_CoinLevelValues = CreateTrie();
	
	LoadTranslations("UsefulCommands.phrases");
	LoadTranslations("common.phrases");
	LoadTranslations("clientprefs.phrases");
	
	fw_ucCountServerRestart = CreateGlobalForward("UsefulCommands_OnCountServerRestart", ET_Event);
	fw_ucNotifyServerRestart = CreateGlobalForward("UsefulCommands_OnNotifyServerRestart", ET_Ignore, Param_Cell);
	fw_ucServerRestartAborted = CreateGlobalForward("UsefulCommands_OnServerRestartAborted", ET_Ignore);
	fw_ucAce = CreateGlobalForward("UsefulCommands_OnPlayerAce", ET_Event, Param_CellByRef, Param_String, Param_CellByRef);
	fw_ucAcePost = CreateGlobalForward("UsefulCommands_OnPlayerAcePost", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	fw_ucWeaponStatsRetrievedPost = CreateGlobalForward("UsefulCommands_OnWeaponStatsRetrievedPost", ET_Ignore);

	
	hcv_mpRespawnOnDeathT = FindConVar("mp_respawn_on_death_t");
	hcv_mpRespawnOnDeathCT = FindConVar("mp_respawn_on_death_ct");
	hcv_mpRoundTime = FindConVar("mp_roundtime");
	
	//svCheatsFlags = GetConVarFlags(hcv_svCheats);
	
	
	hcv_ucTag = UC_CreateConVar("uc_tag", "[{RED}UC{NORMAL}] {NORMAL}", _, FCVAR_PROTECTED);
	hcv_TagScale = UC_CreateConVar("uc_bullet_tagging_scale", "1.0", "5000000.0 is more than enough to disable tagging completely. Below 1.0 makes tagging stronger. 1.0 for default game behaviour", FCVAR_NOTIFY, true, 0.0);
	hcv_ucSpecialC4Rules = UC_CreateConVar("uc_special_bomb_rules", "0", "If 1, CT can pick-up C4 but can't abuse it in any way ( e.g dropping it in unreachable spots ) and can't get rid of it unless to another player.", FCVAR_NOTIFY);
	hcv_ucAcePriority = UC_CreateConVar("uc_ace_priority", "2", "Prioritize Ace over all other fun facts of a round's end and print a message when a player makes an ace. Set to 2 if you want players to have a custom fun fact on ace.");
	hcv_ucReviveOnTeamChange = UC_CreateConVar("uc_revive_on_team_change", "1", "When an admin set a player's team: 0 - Slay player. 1 = Revive player. 2 = Just switch.");
	hcv_ucRestartRoundOnMapStart = UC_CreateConVar("uc_restart_round_on_map_start", "1", "Restart the round when the map starts to block bug where round_start is never called on the first round.");
	hcv_ucIgnoreRoundWinConditions = UC_CreateConVar("uc_ignore_round_win_conditions", "0", "Should rounds be infinite? Cvar doesn't support toggles, just pick a constant value.");
	hcv_ucAnnouncePlugin = UC_CreateConVar("uc_announce_plugin", "36.5", "Announces to joining players that the best utility plugin is running, this cvar's value when after a player joins he'll get the message. 0 to disable.");
	
	GetConVarString(hcv_ucTag, UCTag, sizeof(UCTag));
	HookConVarChange(hcv_ucTag, hcvChange_ucTag);
	HookConVarChange(hcv_ucIgnoreRoundWinConditions, hcvChange_ucIgnoreRoundWinConditions);
	
	if(isCSGO())
	{
		
		hcv_ucTeleportBomb = UC_CreateConVar("uc_teleport_bomb", "1", "If 1, All trigger_teleport entities will have a trigger_bomb_reset attached to them so bombs never get stuck outside of reach in the game. Set to -1 to destroy this mechanism completely to reserve in entity count.", FCVAR_NOTIFY);
		
		hcv_ucUseBombPickup = UC_CreateConVar("uc_use_bomb", "1", "If 1, Terrorists can pick up C4 by pressing E on it.", FCVAR_NOTIFY);
		
		hcv_ucPacketNotifyCvars = UC_CreateConVar("uc_packet_notify_cvars", "2", "If 2, acts like 1 but also deletes the gamerulescvars.txt file before doing it. If 1, UC will put all FCVAR_NOTIFY cvars in gamerulescvars.txt", FCVAR_NOTIFY);
		
		hcv_ucGlowType = UC_CreateConVar("uc_glow_type", "1", "0 = Wallhack, 1 = Fullbody, 2 = Surround Player, 3 = Blinking and Surround Player");
		
		HookConVarChange(hcv_ucTeleportBomb, OnTeleportBombChanged);
				
			
		HookEvent("bomb_defused", Event_BombDefused, EventHookMode_Pre);
		HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Pre);
		HookEvent("player_use", Event_PlayerUse, EventHookMode_Post);
		
		SetCookieMenuItem(PartyModeCookieMenu_Handler, 0, "Party Mode");
		
		PrecacheSoundAny(PartySound);
		
		PrecacheSoundAny(ItemPickUpSound);
	}
	
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	//HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("cs_win_panel_round", Event_CsWinPanelRound, EventHookMode_Pre);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
	
	#if defined _updater_included
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	#endif
	
	if(isLateLoaded)
	{
		for(int i=1;i <= MaxClients;i++)
		{	
			if(!IsClientInGame(i))
				continue;
				
			Func_OnClientPutInServer(i);
		}
	}
}

#if defined _updater_included
public int Updater_OnPluginUpdated()
{
	ServerCommand("sm_reload_translations");
	
	ReloadPlugin(INVALID_HANDLE);
}
#endif
public void OnLibraryAdded(const char[] name)
{
	#if defined _updater_included
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	#endif
}

/*
public Action:Test(  int clients[64],
  int &numClients,
  char sample[PLATFORM_MAX_PATH],
  int &entity,
  int &channel,
  float &volume,
  int &level,
  int &pitch,
  int &flags)
 {

 }
*/
public void OnAllPluginsLoaded()
{
	
	if(!CommandExists("sm_revive"))
		UC_RegAdminCmd("sm_revive", Command_Revive, ADMFLAG_BAN, "Respawns a player from the dead");
		
	if(!CommandExists("sm_respawn"))
		UC_RegAdminCmd("sm_respawn", Command_Revive, ADMFLAG_BAN, "Respawns a player from the dead");

	if(!CommandExists("sm_1up"))
		UC_RegAdminCmd("sm_1up", Command_HardRevive, ADMFLAG_BAN, "Respawns a player from the dead back to his death position");
		
	if(!CommandExists("sm_hrevive"))
		UC_RegAdminCmd("sm_hrevive", Command_HardRevive, ADMFLAG_BAN, "Respawns a player from the dead back to his death position");
		
	if(!CommandExists("sm_bury"))
		UC_RegAdminCmd("sm_bury", Command_Bury, ADMFLAG_BAN, "Buries a player underground");	
		
	if(!CommandExists("sm_unbury"))
		UC_RegAdminCmd("sm_unbury", Command_Unbury, ADMFLAG_BAN, "unburies a player from the ground");	
		
	if(!CommandExists("sm_uberslap"))
		UC_RegAdminCmd("sm_uberslap", Command_UberSlap, ADMFLAG_BAN, "Slaps a player 100 times, leaving him with 1 hp");	
	
	if(!CommandExists("sm_heal"))
		UC_RegAdminCmd("sm_heal", Command_Heal, ADMFLAG_BAN, "Allows to either heal a player, give him armor or a helmet.");
		
	if(!CommandExists("sm_hp"))
		UC_RegAdminCmd("sm_hp", Command_Heal, ADMFLAG_BAN, "Allows to either heal a player, give him armor or a helmet.");
		
	if(!CommandExists("sm_give"))
		UC_RegAdminCmd("sm_give", Command_Give, ADMFLAG_CHEATS, "Give a weapon for a player.");
		
	if(!CommandExists("sm_rr"))
		UC_RegAdminCmd("sm_rr", Command_RestartRound, ADMFLAG_CHANGEMAP, "Restarts the round.");
		
	if(!CommandExists("sm_restartround"))
		UC_RegAdminCmd("sm_restartround", Command_RestartRound, ADMFLAG_CHANGEMAP, "Restarts the round.");
		
	if(!CommandExists("sm_rg"))
		UC_RegAdminCmd("sm_rg", Command_RestartGame, ADMFLAG_CHANGEMAP, "Restarts the game.");
		
	if(!CommandExists("sm_restartgame"))
		UC_RegAdminCmd("sm_restartgame", Command_RestartGame, ADMFLAG_CHANGEMAP, "Restarts the game.");
		
	if(!CommandExists("sm_restart"))
		UC_RegAdminCmd("sm_restart", Command_RestartServer, ADMFLAG_CHANGEMAP, "Restarts the server after 5 seconds. Type again to abort restart.");
		
	if(!CommandExists("sm_restartserver"))
		UC_RegAdminCmd("sm_restartserver", Command_RestartServer, ADMFLAG_CHANGEMAP, "Restarts the server after 5 seconds. Type again to abort restart.");
		
	if(!CommandExists("sm_glow"))
		UC_RegAdminCmd("sm_glow", Command_Glow, ADMFLAG_BAN, "Puts glow on a player for all to see.");
		
	if(!CommandExists("sm_blink"))
		UC_RegAdminCmd("sm_blink", Command_Blink, ADMFLAG_BAN, "Teleports the player to where you are aiming");
		
	if(!CommandExists("sm_bring"))
		UC_RegAdminCmd("sm_bring", Command_Blink, ADMFLAG_BAN, "Teleports the player to where you are aiming");
		
	if(!CommandExists("sm_goto"))
		UC_RegAdminCmd("sm_goto", Command_GoTo, ADMFLAG_BAN, "Teleports you to the given target");
		
	if(!CommandExists("sm_godmode"))
		UC_RegAdminCmd("sm_godmode", Command_Godmode, ADMFLAG_BAN, "Makes player immune to damage, not necessarily to death.");
		
	if(!CommandExists("sm_god"))
		UC_RegAdminCmd("sm_god", Command_Godmode, ADMFLAG_BAN, "Makes player immune to damage, not necessarily to death.");
		
	if(!CommandExists("sm_rocket"))
		UC_RegAdminCmd("sm_rocket", Command_Rocket, ADMFLAG_BAN, "The more handsome sm_slay command");
		
	if(!CommandExists("sm_disarm"))
		UC_RegAdminCmd("sm_disarm", Command_Disarm, ADMFLAG_BAN, "Strips all of the player's weapons");	
	
	if(!CommandExists("sm_ertest"))
		UC_RegAdminCmd("sm_ertest", Command_EarRapeTest, ADMFLAG_CHAT, "Mutes all players except target. Mutes are for the admin himself only to secretly find who's making earrape when 5 players talk simulatenously");
		
	if(!CommandExists("sm_curse"))
		UC_RegAdminCmd("sm_curse", Command_Curse, ADMFLAG_CHEATS, "Curses a player, inverting their movement.");
		
	//if(!CommandExists("sm_cheat"))
		//UC_RegAdminCmd("sm_cheat", Command_Cheat, ADMFLAG_CHEATS, "Writes a command bypassing its cheat flag.");	
		
	if(!CommandExists("sm_last"))
	{
		UC_RegAdminCmd("sm_last", Command_Last, ADMFLAG_BAN, "sm_last [steamid/name/ip] Shows a full list of every single player that ever visited");
		RegAdminCmd("sm_uc_last_showip", Command_Last, ADMFLAG_ROOT);
	}	
	if(!CommandExists("sm_exec"))
		UC_RegAdminCmd("sm_exec", Command_Exec, ADMFLAG_BAN, "Makes a player execute a command. Use !fakeexec if doesn't work.");
		
	if(!CommandExists("sm_fakeexec"))
		UC_RegAdminCmd("sm_fakeexec", Command_FakeExec, ADMFLAG_BAN, "Makes a player execute a command. Use !exec if doesn't work.");
	
	if(!CommandExists("sm_brutexec"))
		UC_RegAdminCmd("sm_brutexec", Command_BruteExec, ADMFLAG_BAN, "Makes a player execute a command with !fakeexec but letting him have admin flags to accomplish the action. Use !exec if doesn't work.");
		
	if(!CommandExists("sm_bruteexec"))
		UC_RegAdminCmd("sm_bruteexec", Command_BruteExec, ADMFLAG_BAN, "Makes a player execute a command with !fakeexec but letting him have admin flags to accomplish the action. Use !exec if doesn't work.");
		
	if(!CommandExists("sm_money"))
		UC_RegAdminCmd("sm_money", Command_Money, ADMFLAG_GENERIC, "Sets a player's money.");
		
	if(!CommandExists("sm_team"))
		UC_RegAdminCmd("sm_team", Command_Team, ADMFLAG_GENERIC, "Sets a player's team.");
		
	if(!CommandExists("sm_swap"))
		UC_RegAdminCmd("sm_swap", Command_Swap, ADMFLAG_GENERIC, "Swaps a player to the opposite team.");
		
	if(!CommandExists("sm_spec"))
		UC_RegAdminCmd("sm_spec", Command_Spec, ADMFLAG_GENERIC, "Moves a player to spectator team.");
		
	if(!CommandExists("sm_xyz"))
		UC_RegAdminCmd("sm_xyz", Command_XYZ, ADMFLAG_GENERIC, "Prints your origin.");	
		
	if(!CommandExists("sm_silentcvar"))
		UC_RegAdminCmd("sm_silentcvar", Command_SilentCvar, ADMFLAG_ROOT, "Changes cvar without in-game notification."); // I cannot afford to allow less than Root as I cannot monitor protected cvars. Changing access flag means the admin can get rcon_password.
		
	if(!CommandExists("sm_acookies"))
		UC_RegAdminCmd("sm_acookies", Command_AdminCookies, ADMFLAG_ROOT, "Powerful cookie editing abilities");
		
	if(!CommandExists("sm_admincookies"))
		UC_RegAdminCmd("sm_admincookies", Command_AdminCookies, ADMFLAG_ROOT, "Powerful cookie editing abilities");
	
	if(!CommandExists("sm_findcvar"))
		UC_RegAdminCmd("sm_findcvar", Command_FindCvar, ADMFLAG_ROOT, "Finds a cvar, even if it's hidden. Searches for commands as well.");
	
	if(!CommandExists("sm_cc"))	
		UC_RegAdminCmd("sm_cc", Command_ClearChat, ADMFLAG_CHAT, "Clears the chat");


	if(!CommandExists("sm_clear"))	
		UC_RegAdminCmd("sm_clear", Command_ClearChat, ADMFLAG_CHAT, "Clears the chat");
		
	if(!CommandExists("sm_hug"))
		UC_RegConsoleCmd("sm_hug", Command_Hug, "Hugs a dead player.");
	
	UC_RegConsoleCmd("sm_uc", Command_UC, "Shows a list of UC commands.");
	
	if(isCSGO())
	{
		if(!CommandExists("sm_customace"))
			UC_RegConsoleCmd("sm_customace", Command_CustomAce, "Allows you to set a custom fun fact for ace.");
			
		hcv_PartyMode = FindConVar("sv_party_mode");
		
		hcv_ucPartyMode = UC_CreateConVar("uc_party_mode", "2", "0 = Nobody can access party mode. 1 = You can choose to participate in party mode. 2 = Zeus will cost 100$ as tradition", FCVAR_NOTIFY);
		hcv_ucPartyModeDefault = UC_CreateConVar("uc_party_mode_default", "3", "Party mode cookie to set for int comers. 0 = Disabled, 1 = Defuse balloons only, 2 = Zeus only, 3 = Both.");
	
		hCookie_EnablePM = RegClientCookie("UsefulCommands_PartyMode", "Party Mode flags. 0 = Disabled, 1 = Defuse balloons only, 2 = Zeus only, 3 = Both.", CookieAccess_Public);
		hCookie_AceFunFact = RegClientCookie("UsefulCommands_AceFunFact", "When you make an ace, this will be the fun fact to send to the server. $name -> your name. $team -> your team. $opteam -> your opponent team.", CookieAccess_Public);	
		
		hcv_mpAnyoneCanPickupC4 = FindConVar("mp_anyone_can_pickup_c4");
		hcv_SolidTeammates = FindConVar("mp_solid_teammates");
		
		HookConVarChange(hcv_ucSpecialC4Rules, OnSpecialC4RulesChanged);
			
		if(!CommandExists("sm_chicken"))
		{
			UC_RegAdminCmd("sm_chicken", Command_Chicken, ADMFLAG_BAN, "Allows you to set up the map's chicken spawns.");	
			UC_RegAdminCmd("sm_ucedit", Command_UCEdit, ADMFLAG_BAN, "Allows you to teleport to the chicken spawner prior to delete.");
			hcv_ucMaxChickens = UC_CreateConVar("uc_max_chickens", "5", "Maximum amount of chickens UC will generate.");
			hcv_ucMinChickenTime = UC_CreateConVar("uc_min_chicken_time", "5.0", "Minimum amount of time between a chicken's death and the recreation.");
			hcv_ucMaxChickenTime = UC_CreateConVar("uc_max_chicken_time", "10.0", "Maximum amount of time between a chicken's death and the recreation.");
		}
		
		if(!CommandExists("sm_wepstats"))
			UC_RegConsoleCmd("sm_wepstats", Command_WepStats, "Shows the stats of all weapons");
			
		if(!CommandExists("sm_weaponstats"))
			UC_RegConsoleCmd("sm_weaponstats", Command_WepStats, "Shows the stats of all weapons");
			
		//if(!CommandExists("sm_wepstatsvs"))
			//UC_RegConsoleCmd("sm_wepstatsvs", Command_WepStatsVS, "Compares the stats of 2 weapons");
			
		//if(!CommandExists("sm_weaponstatsvs"))
			//UC_RegConsoleCmd("sm_weaponstatsvs", Command_WepStatsVS, "Compares the stats of 2 weapons");
			
		
	}	
	
	
	#if defined _autoexecconfig_included
	
	AutoExecConfig_ExecuteFile();

	AutoExecConfig_CleanFile();
	
	#endif
}

public void hcvChange_ucTag(Handle convar, const char[] oldValue, const char[] newValue)
{
	FormatEx(UCTag, sizeof(UCTag), newValue);
}

public void hcvChange_ucIgnoreRoundWinConditions(Handle convar, const char[] oldValue, const char[] newValue)
{
	if(StringToInt(newValue) != 0)
	{
		ServerCommand("mp_ignore_round_win_conditions 1");
		SetConVarFloat(hcv_mpRoundTime, 60.0);
	}
	
}

public void ConnectToDatabase()
{		
	char Error[256];
	if((dbLocal = SQLite_UseDatabase("sourcemod-local", Error, sizeof(Error))) == INVALID_HANDLE)
		LogError(Error);
	
	else
	{ 
		dbLocal.Query(SQLCB_Error, "CREATE TABLE IF NOT EXISTS UsefulCommands_LastPlayers (AuthId VARCHAR(32) NOT NULL UNIQUE, LastConnect INT(11) NOT NULL, IPAddress VARCHAR(32) NOT NULL, Name VARCHAR(64) NOT NULL)", DBPrio_High); 
		
		if(isCSGO())
		{
			dbLocal.Query(SQLCB_Error, "CREATE TABLE IF NOT EXISTS UsefulCommands_Chickens (ChickenOrigin VARCHAR(50) NOT NULL, ChickenMap VARCHAR(128), ChickenCreateDate INT(11) NOT NULL, UNIQUE(ChickenOrigin, ChickenMap))", DBPrio_High);		
				
			LoadChickenSpawns();
		}
	}
	
	Database.Connect(SQLConnectCB_ClientPrefsConnected, "clientprefs");
}

public void SQLConnectCB_ClientPrefsConnected(Database db, const char[] error, any data)
{
	if (db == null)
	{
	    LogError("Database failure: %s", error);
	    
	    return;
	}

	dbClientPrefs = db;
}

public void SQLCB_Error(Handle db, Handle hndl, const char[] sError, int data)
{
	if(hndl == null)
		ThrowError(sError);
}


void LoadChickenSpawns()
{
	char sQuery[256];
	dbLocal.Format(sQuery, sizeof(sQuery), "SELECT * FROM UsefulCommands_Chickens WHERE ChickenMap = \"%s\"", MapName);
	dbLocal.Query(SQLCB_LoadChickenSpawns, sQuery);
}
public void SQLCB_LoadChickenSpawns(Handle db, Handle hndl, const char[] sError, int data)
{
	if(hndl == null)
		ThrowError(sError);

	ClearArray(ChickenOriginArray);
	
	while(SQL_FetchRow(hndl))
	{
		char sOrigin[50];
		SQL_FetchString(hndl, 0, sOrigin, sizeof(sOrigin));
		
		CreateChickenSpawner(sOrigin);
	}
}

public void OnEntityCreated(int entity, const char[] Classname)
{
	if(StrEqual(Classname, "trigger_teleport", true))
		SDKHook(entity, SDKHook_SpawnPost, Event_TeleportSpawnPost);
	
}
	
public void Event_TeleportSpawnPost(int entity)
{
	if(!MapStarted)
	{
		if(TeleportsArray == INVALID_HANDLE)
			TeleportsArray = CreateArray(1);
			
		PushArrayCell(TeleportsArray, EntIndexToEntRef(entity));
		return;
	}
	int bombReset = CreateEntityByName("trigger_bomb_reset");
	
	if(bombReset == -1)
		return;

	char Model[PLATFORM_MAX_PATH];
	
	GetEntPropString(entity, Prop_Data, "m_ModelName", Model, sizeof(Model));
	
	DispatchKeyValue(bombReset, "model", Model);
	DispatchKeyValue(bombReset, "targetname", "trigger_bomb_reset");
	DispatchKeyValue(bombReset, "StartDisabled", "0");
	DispatchKeyValue(bombReset, "spawnflags", "64");
	float Origin[3], Mins[3], Maxs[3];

	GetEntPropVector(entity, Prop_Send, "m_vecMins", Mins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", Maxs);
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", Origin);
	
	TeleportEntity(bombReset, Origin, NULL_VECTOR, NULL_VECTOR);
	
	DispatchSpawn(bombReset);
	
	ActivateEntity(bombReset);
	
	SetEntPropVector(bombReset, Prop_Send, "m_vecMins", Mins);
	SetEntPropVector(bombReset, Prop_Send, "m_vecMaxs", Maxs);
	
	SetEntProp(bombReset, Prop_Send, "m_nSolidType", 1);
	SetEntProp(bombReset, Prop_Send, "m_usSolidFlags", 524);
	
	SetEntProp(bombReset, Prop_Send, "m_fEffects", GetEntProp(bombReset, Prop_Send, "m_fEffects") | 32);
	
	PushArrayCell(BombResetsArray, EntIndexToEntRef(bombReset));
	
	if(!GetConVarBool(hcv_ucTeleportBomb))
		AcceptEntityInput(bombReset, "Disable");
}

public void OnConfigsExecuted()
{
	SetConVarString(CreateConVar("uc_version", PLUGIN_VERSION, _, FCVAR_NOTIFY), PLUGIN_VERSION); // Last resort due to past mistake.
	
	if(!isCSGO())
		return;
	
	if(GetConVarBool(hcv_ucIgnoreRoundWinConditions))
	{
		ServerCommand("mp_ignore_round_win_conditions 1");
		SetConVarFloat(hcv_mpRoundTime, 60.0);
	}
	bool Exists = FileExists(GAME_RULES_CVARS_PATH);
	
	int ucPacketNotifyCvars = GetConVarInt(hcv_ucPacketNotifyCvars);
	if( ucPacketNotifyCvars != 0 && ( !Exists || ( Exists && ucPacketNotifyCvars == 2 ) ) )
	{
		
		Handle SortArray = CreateArray(128);
		Handle keyValues = CreateKeyValues("NotifyRulesCvars");
		
		char CvarName[128];
		int flags;
		bool bCommand;
		Handle iterator = FindFirstConCommand(CvarName, sizeof(CvarName), bCommand, flags)
		
		if(iterator != INVALID_HANDLE)
		{
			if(!bCommand && (flags & FCVAR_NOTIFY) && !(flags & FCVAR_PROTECTED))
				PushArrayString(SortArray, CvarName);
				
			while(FindNextConCommand(iterator, CvarName, sizeof(CvarName), bCommand, flags))
			{
				if(bCommand)
					continue;
					
				else if(flags & FCVAR_NOTIFY && !(flags & FCVAR_PROTECTED))
					PushArrayString(SortArray, CvarName);
			}
			
			CloseHandle(iterator);
			
			SortADTArray(SortArray, Sort_Ascending, Sort_String);
			
			int size = GetArraySize(SortArray);
			
			for(int i=0;i < size;i++)
			{
				GetArrayString(SortArray, i, CvarName, sizeof(CvarName));
					
				KvSetNum(keyValues, CvarName, 1);
			}
			
			KvRewind(keyValues);
			
			KeyValuesToFile(keyValues, GAME_RULES_CVARS_PATH);
		}
		
		CloseHandle(SortArray);
	}	
	if(GetConVarBool(hcv_ucSpecialC4Rules))
		SetConVarBool(hcv_mpAnyoneCanPickupC4, true);
	
	KeyValues keyValues = CreateKeyValues("items_game");
	KeyValues CacheKeyValues = CreateKeyValues("items_game");
	
	char CachePath[256];
	BuildPath(Path_SM, CachePath, sizeof(CachePath), CACHE_ITEMS_GAME_PATH);
	
	CreateDirectory(CachePath, FPERM_ULTIMATE);
	
	SetFilePermissions(CachePath, FPERM_ULTIMATE); // Actually allow us to enter.
	
	Format(CachePath, sizeof(CachePath), "%s/items_game.txt", CachePath);
	
	bool ShouldCache = true;
	
	if(!FileExists(CachePath))
		ShouldCache = false;
	
	int CacheLastEdited = GetFileTime(CachePath, FileTime_LastChange);
	
	if(CacheLastEdited == -1)
		ShouldCache = false;
		
	int LastEdited = GetFileTime(ITEMS_GAME_PATH, FileTime_LastChange);
	
	if(LastEdited == -1)
		return;

	if(LastEdited > CacheLastEdited)
		ShouldCache = false;
		
	if(ShouldCache)
	{
		if(!FileToKeyValues(keyValues, CachePath))
		{
			if(!FileToKeyValues(keyValues, ITEMS_GAME_PATH))
				return;
			
			DeleteFile(CachePath);
			
			UC_CreateEmptyFile(CachePath);
			
			ShouldCache = false;
		}
	}
	else
	{		
		if(!FileToKeyValues(keyValues, ITEMS_GAME_PATH))
			return;
		
		DeleteFile(CachePath);
		
		UC_CreateEmptyFile(CachePath);
	}
	
	if(!KvGotoFirstSubKey(keyValues))
		return;

	char buffer[64], levelValue[64];
	
	KvSavePosition(keyValues);
	
	if(!ShouldCache)
		KvSavePosition(CacheKeyValues);
		
	do
	{
		KvGetSectionName(keyValues, buffer, sizeof(buffer));
		
		if(StrEqual(buffer, "items"))
		{
			KvGotoFirstSubKey(keyValues);
			
			if(!ShouldCache)
				KvJumpToKey(CacheKeyValues, "items", true);
				
			break;
		}
	}
	while(KvGotoNextKey(keyValues))
	
	do
	{
		KvGetSectionName(keyValues, buffer, sizeof(buffer));
		
		if(UC_IsStringNumber(buffer))
		{
			KvGetString(keyValues, "name", levelValue, sizeof(levelValue));
			
			int position = StrContains(levelValue, "prestige", false);
			
			if(position != -1 && !ShouldCache)
			{	
				UC_KvCopyChildren(keyValues, CacheKeyValues, buffer);
			}	
			if(position == -1)
				SetTrieValue(Trie_CoinLevelValues, buffer, 0);
				
			else if((position = StrContains(levelValue, "level", false)) == -1)
			{
				IntToString(MAX_CSGO_LEVEL, levelValue, sizeof(levelValue));
				SetTrieValue(Trie_CoinLevelValues, buffer, StringToInt(levelValue));
			}
			else
			{
				SetTrieValue(Trie_CoinLevelValues, buffer, StringToInt(levelValue[position]));
			}
		}
	}
	while(KvGotoNextKey(keyValues))
	
	KvRewind(keyValues);
	KvGotoFirstSubKey(keyValues);
	
	if(!ShouldCache)
	{
		KvRewind(CacheKeyValues);
		KvGotoFirstSubKey(keyValues);
	}

	int WepNone = view_as<int>(CSWeapon_NONE);
	
	do
	{
		KvGetSectionName(keyValues, buffer, sizeof(buffer));
		
		if(StrEqual(buffer, "prefabs"))
		{
			KvGotoFirstSubKey(keyValues);
			
			if(!ShouldCache)
				KvJumpToKey(CacheKeyValues, "prefabs", true);
				
			break;
		}
	}
	while(KvGotoNextKey(keyValues))
	
	// Now we save position of prefabs and find all default values for damage, fire rate, and etc.
	
	KvSavePosition(keyValues);
	
	if(!ShouldCache)
		KvSavePosition(CacheKeyValues);

	do
	{
		KvGetSectionName(keyValues, buffer, sizeof(buffer));
		
		if(StrEqual(buffer, "statted_item_base"))
		{
			KvGotoFirstSubKey(keyValues);
			
			if(!ShouldCache)
			{
				KvJumpToKey(CacheKeyValues, "statted_item_base", true);
			}	
			break;
		}
	}
	while(KvGotoNextKey(keyValues))
	
	do
	{
		KvGetSectionName(keyValues, buffer, sizeof(buffer));
	
		if(StrEqual(buffer, "attributes"))
		{
			KvGotoFirstSubKey(keyValues);
				
			if(!ShouldCache)
			{
				UC_KvCopyChildren(keyValues, CacheKeyValues, "attributes");
			}	
			
			break;
		}
	}
	while(KvGotoNextKey(keyValues))
	
	// Default values.
	wepStatsList[WepNone].wepStatsFireRate = RoundFloat((1.0 / KvGetFloat(keyValues, "cycletime", -1.0)) * 60.0); // By RPM = Rounds per Minute. Note: NEVER ALLOW DEFAULT VALUE 0.0 WHEN DIVIDING IT!!!
	wepStatsList[WepNone].wepStatsArmorPenetration = KvGetFloat(keyValues, "armor ratio") * 50.0; // It maxes at 2.000 to be 100% armor penetration.
	wepStatsList[WepNone].wepStatsKillAward = KvGetNum(keyValues, "kill award");
	wepStatsList[WepNone].wepStatsWallPenetration = KvGetFloat(keyValues, "penetration");
	wepStatsList[WepNone].wepStatsDamageDropoff = RoundFloat(100.0 - KvGetFloat(keyValues, "range modifier") * 100.0);
	wepStatsList[WepNone].wepStatsMaxDamageRange = KvGetNum(keyValues, "range");
	wepStatsList[WepNone].wepStatsPalletsPerShot = KvGetNum(keyValues, "bullets");
	wepStatsList[WepNone].wepStatsDamage = KvGetNum(keyValues, "damage");
	wepStatsList[WepNone].wepStatsIsAutomatic = view_as<bool>(KvGetNum(keyValues, "is full auto"));
	
	KvGoBack(keyValues);
	
	if(!ShouldCache)
		KvGoBack(CacheKeyValues);

	char CompareBuffer[64], Alias[64];
	do
	{
		KvGetSectionName(keyValues, buffer, sizeof(buffer));

		if(StrContains(buffer, "_prefab") != -1 && strncmp(buffer, "weapon_", 7) == 0)
		{
			CSWeaponID i
			for(i=CSWeapon_NONE;i < CSWeapon_MAX_WEAPONS_NO_KNIFES;i++) // Loop all weapons.
			{
				if(CS_IsValidWeaponID(i)) // I don't like using continue in two loops.
				{
					if(CS_WeaponIDToAlias(i, Alias, sizeof(Alias)) != 0) // iDunno...
					{
						Format(CompareBuffer, sizeof(CompareBuffer), "weapon_%s_prefab", Alias);
				
						if(StrEqual(buffer, CompareBuffer)) // We got a match!
						{
							KvSavePosition(keyValues); // Save our position.
							KvGotoFirstSubKey(keyValues);
							
							if(!ShouldCache)
								KvJumpToKey(CacheKeyValues, buffer, true);
							
							bool bBreak = false;
							do
							{
								KvGetSectionName(keyValues, buffer, sizeof(buffer)); // We can overwrite the last buffer we took, it's irrelevant now :D
	
								if(StrEqual(buffer, "attributes"))
								{
									KvGotoFirstSubKey(keyValues);
									bBreak = true;
								}
							}
							while(!bBreak && KvGotoNextKey(keyValues)) // Find them attributes.
						
							float cycletime;
							wepStatsList[i].wepStatsFireRate = RoundFloat((1.0 / (cycletime=KvGetFloat(keyValues, "cycletime", -1.0))) * 60.0); // By RPM = Rounds per Minute. Note: NEVER ALLOW DEFAULT VALUE 0.0 WHEN DIVIDING IT!!!
							
							if(wepStatsList[i].wepStatsFireRate == -60)
							{
								wepStatsList[i].wepStatsFireRate = wepStatsList[WepNone].wepStatsFireRate;
								cycletime = (1.0 / (wepStatsList[i].wepStatsFireRate / 60.0));
							}
							wepStatsList[i].wepStatsArmorPenetration = KvGetFloat(keyValues, "armor ratio", -1.0) * 50.0; // It maxes at 2.000 to be 100% armor penetration.
							
							if(wepStatsList[i].wepStatsArmorPenetration == -50.0)
								wepStatsList[i].wepStatsArmorPenetration = wepStatsList[WepNone].wepStatsArmorPenetration;
								
							wepStatsList[i].wepStatsKillAward = KvGetNum(keyValues, "kill award", wepStatsList[WepNone].wepStatsKillAward); // It maxes at 2.000 to be 100% armor penetration.
							
							wepStatsList[i].wepStatsWallPenetration = KvGetFloat(keyValues, "penetration", wepStatsList[WepNone].wepStatsWallPenetration);
							
							float Range;
							wepStatsList[i].wepStatsDamageDropoff = RoundFloat(100.0 - (Range=KvGetFloat(keyValues, "range modifier")) * 100.0);
							
							if(Range == 0.0)
							{
								wepStatsList[i].wepStatsDamageDropoff = wepStatsList[WepNone].wepStatsDamageDropoff;
								Range = (100.0 - float(wepStatsList[i].wepStatsDamageDropoff)) / 100.0;
							}
								
							wepStatsList[i].wepStatsMaxDamageRange = KvGetNum(keyValues, "range", wepStatsList[WepNone].wepStatsMaxDamageRange);
							wepStatsList[i].wepStatsPalletsPerShot = KvGetNum(keyValues, "bullets", wepStatsList[WepNone].wepStatsPalletsPerShot);
							wepStatsList[i].wepStatsDamage = (wepStatsList[i].wepStatsDamagePerPallet = KvGetNum(keyValues, "damage", wepStatsList[WepNone].wepStatsDamage)) * wepStatsList[i].wepStatsPalletsPerShot;
							
							wepStatsList[i].wepStatsIsAutomatic = view_as<bool>(KvGetNum(keyValues, "is full auto", wepStatsList[WepNone].wepStatsIsAutomatic));
							// Now we calculate one tap distance. 
							
							if(FloatCompare(Range, 0.0) == 0 || FloatCompare(Range, 1.0) == 0)
								Range = 0.000001; // Close to zero but nyeahhhh
								
							if(float(wepStatsList[i].wepStatsDamage) * HEADSHOT_MULTIPLIER < 100.0) // IMPOSSIBLE!!!
								wepStatsList[i].wepStatsTapDistanceNoArmor = 0; // -1 = impossible to 1 tap.
								
							else
								wepStatsList[i].wepStatsTapDistanceNoArmor = RoundFloat(Logarithm((100.0 / (wepStatsList[i].wepStatsDamage * HEADSHOT_MULTIPLIER)) , Range)*500.0);
							
							if(wepStatsList[i].wepStatsTapDistanceNoArmor > wepStatsList[i].wepStatsMaxDamageRange)
								wepStatsList[i].wepStatsTapDistanceNoArmor = wepStatsList[i].wepStatsMaxDamageRange;
								
							if(float(wepStatsList[i].wepStatsDamage) * HEADSHOT_MULTIPLIER * (wepStatsList[i].wepStatsArmorPenetration / 100.0) < 100.0) // IMPOSSIBLE!!!
								wepStatsList[i].wepStatsTapDistanceArmor = 0; // -1 = impossible to 1 tap.
								
							else
								wepStatsList[i].wepStatsTapDistanceArmor = RoundFloat(Logarithm((100.0 / (wepStatsList[i].wepStatsDamage * HEADSHOT_MULTIPLIER * (wepStatsList[i].wepStatsArmorPenetration / 100.0))) , Range)*500.0);
								
							if(wepStatsList[i].wepStatsTapDistanceArmor > wepStatsList[i].wepStatsMaxDamageRange)
								wepStatsList[i].wepStatsTapDistanceArmor = wepStatsList[i].wepStatsMaxDamageRange;
							
							wepStatsList[i].wepStatsDamagePerSecondNoArmor = RoundFloat((1.0 / cycletime) * wepStatsList[i].wepStatsDamage);
							wepStatsList[i].wepStatsDamagePerSecondArmor = RoundFloat((1.0 / cycletime) * wepStatsList[i].wepStatsDamage * (wepStatsList[i].wepStatsArmorPenetration/100));
							
							if(!ShouldCache)
							{
								UC_KvCopyChildren(keyValues, CacheKeyValues, "attributes");
								KvGoBack(CacheKeyValues);
							}
							KvGoBack(keyValues);
							
							
							
							i = CSWeapon_MAX_WEAPONS; // Equivalent of break.
						}
					}
				}
			}
		}
	}
	while(KvGotoNextKey(keyValues))

	if(!ShouldCache)
	{	
		KvRewind(CacheKeyValues);
		KeyValuesToFile(CacheKeyValues, CachePath); // Note to self: KvRewind always when using KeyValuesToFile because it uses current position.
	}	
	
	CloseHandle(keyValues);
	CloseHandle(CacheKeyValues);
	
	Call_StartForward(fw_ucWeaponStatsRetrievedPost);
	
	Call_Finish(keyValues); // keyValues was already disposed.

}
	
public void OnSpecialC4RulesChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	SetConVarString(hcv_mpAnyoneCanPickupC4, newValue);
}

public void OnTeleportBombChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	if(StringToInt(oldValue) == -1)
		return;
		
	int iValue = StringToInt(newValue);
	if(iValue == 1)
	{
		for(int i=0; i < GetArraySize(BombResetsArray);i++)
		{
			int entity = EntRefToEntIndex(GetArrayCell(BombResetsArray, i));
			
			if(entity == INVALID_ENT_REFERENCE)
			{
				RemoveFromArray(BombResetsArray, i--);
				continue;
			}
			
			AcceptEntityInput(entity, "Enable");
		}
	}
	else if(iValue == -1)
	{
		for(int i=0; i < GetArraySize(BombResetsArray);i++)
		{
			int entity = EntRefToEntIndex(GetArrayCell(BombResetsArray, i));
			
			if(entity == INVALID_ENT_REFERENCE)
			{
				RemoveFromArray(BombResetsArray, i--);
				continue;
			}
			
			AcceptEntityInput(entity, "Disable");
			AcceptEntityInput(entity, "Kill");
		}
		
		CloseHandle(BombResetsArray);
		BombResetsArray = INVALID_HANDLE;
	}
	else
	{
		for(int i=0; i < GetArraySize(BombResetsArray);i++)
		{
			int entity = EntRefToEntIndex(GetArrayCell(BombResetsArray, i));
			
			if(entity == INVALID_ENT_REFERENCE)
			{
				RemoveFromArray(BombResetsArray, i--);
				continue;
			}
			
			AcceptEntityInput(entity, "Disable");
		}
	}
}

public Action CS_OnGetWeaponPrice(int client, const char[] weapon, int &price)
{
	if(StrEqual(weapon, "taser", true) && GetConVarInt(hcv_ucPartyMode) == 2)
	{
		price = 100;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	Action ret = Plugin_Continue;
	
	if(g_bCursed[client])
	{
		vel[0] = -vel[0];
		vel[1] = -vel[1];
		
		ret = Plugin_Changed;
	}
	if(!GetConVarBool(hcv_ucSpecialC4Rules))
		return ret;
		
	else if(!(buttons & IN_ATTACK) && !(buttons & IN_USE))
		return ret;
	
	else if(!GetEntProp(client, Prop_Send, "m_bInBombZone"))
		return ret;
		
	else if(GetClientTeam(client) != CS_TEAM_CT)
		return ret;
		
	int curWeapon;
	if((curWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon")) == -1)
		return ret;
		
	char Classname[50];
	GetEdictClassname(curWeapon, Classname, sizeof(Classname));
	
	if(!StrEqual(Classname, "weapon_c4", true))
		return ret;
	
	buttons &= ~IN_ATTACK;
	buttons &= ~IN_USE;
	
	return Plugin_Changed;
}

/*
public Action:SoundHook_PartyMode(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags) // Fucking prediction...
{	
	if(!StrEqual(sample, PartySound))
		return Plugin_Continue;

	UC_PrintToChatAll("b");
	new numClientsToUse = 0;
	new clientsToUse[64];
	
	for(new i=0;i < numClients;i++)
	{
		new client = clients[i];
		
		if(!IsClientInGame(client))
			continue;
			
		if(!GetClientPartyMode(client))
			continue;
		
		clientsToUse[numClientsToUse++] = client;
	}
	
	if(numClientsToUse != 0)
	{
		clients = clientsToUse;
		numClients = numClientsToUse;
		
		return Plugin_Changed;
	}
	
	return Plugin_Stop;
}
*/
public Action Event_BombDefused(Handle hEvent, const char[] Name, bool dontBroadcast)
{	
	if(!GetConVarBool(hcv_ucPartyMode))	
		return;
		
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	SetConVarBool(hcv_PartyMode, false);
	
	CreateDefuseBalloons(client);
	
	float Origin[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
	
	int[] clients = new int[MaxClients+1];
	int total = 0;
	
	for (int i=1; i<=MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if(GetClientPartyMode(i) & PARTYMODE_DEFUSE)
			{
				clients[total++] = i;
			}
		}
	}
	
	if (!total)
	{
		return;
	}
	
	EmitSoundAny(clients, total, PartySound, client, 6, 79, _, 1.0, 100, _, Origin, _, _, _);
	
	
}

public Action Event_WeaponFire(Handle hEvent, const char[] Name, bool dontBroadcast)
{	
	if(!GetConVarBool(hcv_ucPartyMode))	
		return;
		
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
		
	char WeaponName[50];
	GetEventString(hEvent, "weapon", WeaponName, sizeof(WeaponName));
	
	if(!StrEqual(WeaponName, "weapon_taser", true))
		return;
	
	SetConVarBool(hcv_PartyMode, false); // This will stop client prediction issues.
	
	float Origin[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
	
	int[] clients = new int[MaxClients+1];
	int total = 0;
	
	for (int i=1; i<=MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if(GetClientPartyMode(i) & PARTYMODE_ZEUS)
			{
				clients[total++] = i;
			}
		}
	}
		
	if(total)
		EmitSoundAny(clients, total, PartySound, client, 6, 79, _, 1.0, 100, _, Origin, _, _, _);
		
	CreateZeusConfetti(client);

}

public Action Event_PlayerUse(Handle hEvent, const char[] Name, bool dontBroadcast)
{
	if(!GetConVarBool(hcv_ucUseBombPickup))
		return;
		
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if(client == 0)
		return;
		
	else if(!IsPlayerAlive(client))
		return;
	
	int entity = GetEventInt(hEvent, "entity");
	
	if(!IsValidEntity(entity))
		return;
		
	char Classname[50];
	GetEntityClassname(entity, Classname, sizeof(Classname));
	
	if(!StrEqual(Classname, "weapon_c4", true))
		return;
		
	else if(GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") != -1)
		return;
		
	int Team = GetClientTeam(client);
	if(Team != CS_TEAM_T && !GetConVarBool(hcv_mpAnyoneCanPickupC4))
		return;
	
	AcceptEntityInput(entity, "Kill");
	
	GivePlayerItem(client, "weapon_c4");
	
	/*
	
	for(new i=0;i < GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");i++)
	{
		new ent = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		
		if(!IsValidEntity(ent))
			continue;
			
		GetEdictClassname(ent, Classname, sizeof(Classname));
		
		if(StrEqual(Classname, "weapon_c4", true))
			return;
	}
	
	new Float:Origin[3];
	
	SetEntPropEnt(entity, Prop_Send, "m_hPrevOwner", -1);
	
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
	
	TeleportEntity(entity, Origin, NULL_VECTOR, NULL_VECTOR);
	
	EmitSoundToAllAny(ItemPickUpSound, client, 3, 326, _, 0.5, 100, _, Origin, _, _, _);
	*/
	
}

public Action Event_RoundEnd(Handle hEvent, const char[] Name, bool dontBroadcast)
{
	if(isCSGO())
		return Plugin_Continue;
	
	else if(!BlockedWinPanel)	
		return Plugin_Continue;
		
	int WinningTeam = GetEventInt(hEvent, "winner");
	
	Handle hWinEvent = CreateEvent("cs_win_panel_round", true);
	
	SetEventBool(hWinEvent, "show_timer_defend", show_timer_defend);
	SetEventBool(hWinEvent, "show_timer_attack", show_timer_attack);
	SetEventInt(hWinEvent, "timer_time", timer_time);
	SetEventInt(hWinEvent, "final_event", final_event);
	
	SetEventString(hWinEvent, "funfact_token", funfact_token);
	
	SetEventInt(hWinEvent, "funfact_player", funfact_player);
	SetEventInt(hWinEvent, "funfact_data1", funfact_data1);
	SetEventInt(hWinEvent, "funfact_data2", funfact_data2);
	SetEventInt(hWinEvent, "funfact_data3", funfact_data3);
	
	SetEventInt(hWinEvent, "winner", WinningTeam);

	BlockedWinPanel = false;
	
	FireEvent(hWinEvent);
	
	return Plugin_Continue;
	
}

public Action Event_RoundStart(Handle hEvent, const char[] Name, bool dontBroadcast)
{
	if(RestartNR && RestartTimestamp <= GetTime())
	{
		CreateTimer(0.5, RestartServer, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	// AceCandidate is -1 for nobody and -2 for disqualification of the team.
	AceCandidate[CS_TEAM_CT] = -1;
	AceCandidate[CS_TEAM_T] = -1;
	
	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		TrueTeam[i] = 0;
		RoundKills[i] = 0;
	}
	AceSent = false;
	RoundNumber++;

	if(!isCSGO())
		return;
		
	int Chicken = -1;
	while((Chicken = FindEntityByClassname(Chicken, "Chicken")) != -1)
	{
		char TargetName[100];
		GetEntPropString(Chicken, Prop_Data, "m_iName", TargetName, sizeof(TargetName));
		
		if(StrContains(TargetName, "UsefulCommands_Chickens") != -1)
			AcceptEntityInput(Chicken, "Kill");
	}
	
	int Size = GetArraySize(ChickenOriginArray);
	
	int MaxChickens = GetConVarInt(hcv_ucMaxChickens);
	if(Size <= MaxChickens)
	{
		for(int i=0;i < Size;i++)
		{	
			char sOrigin[50];
			GetArrayString(ChickenOriginArray, i, sOrigin, sizeof(sOrigin));
	
			SpawnChicken(sOrigin);
		}
	}
	else
	{
		Handle TempChickenOriginArray = CloneArray(ChickenOriginArray);
		
		char sOrigin[50];
		int Count = 0;
		while(Count++ < MaxChickens)
		{
			int Winner = GetRandomInt(0, Size-1);
			GetArrayString(TempChickenOriginArray, Winner, sOrigin, sizeof(sOrigin));
	
			RemoveFromArray(TempChickenOriginArray, Winner);
			Size--;
			
			SpawnChicken(sOrigin);
		}
		CloseHandle(TempChickenOriginArray);
	}
	
	if(GetConVarBool(hcv_ucIgnoreRoundWinConditions))
	{
		ServerCommand("mp_ignore_round_win_conditions 1");
		
		SetConVarFloat(hcv_mpRoundTime, 60.0);
		
		GameRules_SetProp("m_iRoundTime", 0);
	}
}


public Action Event_RoundFreezeEnd(Handle hEvent, const char[] Name, bool dontBroadcast)
{
	if(GetConVarBool(hcv_ucIgnoreRoundWinConditions))
	{
		ServerCommand("mp_ignore_round_win_conditions 1");
		
		SetConVarFloat(hcv_mpRoundTime, 60.0);
		
		GameRules_SetProp("m_iRoundTime", 0);
	}
}

public Action Event_PlayerTeam(Handle hEvent, const char[] Name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
		
	int OldTeam = GetEventInt(hEvent, "oldteam");
	
	if(OldTeam <= CS_TEAM_SPECTATOR)	
		return;
		
	TrueTeam[client] = OldTeam;
}

void SpawnChicken(const char[] sOrigin)
{
	int Chicken = CreateEntityByName("chicken");
	
	char TargetName[100];
	Format(TargetName, sizeof(TargetName), "UsefulCommands_Chickens %s", sOrigin);
	SetEntPropString(Chicken, Prop_Data, "m_iName", TargetName);
	
	DispatchSpawn(Chicken);
	
	float Origin[3];
	GetStringVector(sOrigin, Origin);
	TeleportEntity(Chicken, Origin, NULL_VECTOR, NULL_VECTOR);
	
	HookSingleEntityOutput(Chicken, "OnBreak", Event_ChickenKilled, true)
}

public void Event_ChickenKilled(const char[] output, int caller, int activator, float delay)
{
	if(!IsValidEntity(caller))
		return;
		
	// Chicken is dead.
	
	char TargetName[100];
	GetEntPropString(caller, Prop_Data, "m_iName", TargetName, sizeof(TargetName));
	
	
	if(StrContains(TargetName, "UsefulCommands_Chickens") != -1)
	{
		ReplaceStringEx(TargetName, sizeof(TargetName), "UsefulCommands_Chickens ", "");
		
		Handle DP = CreateDataPack();
		
		WritePackCell(DP, RoundNumber);
		
		CreateTimer(GetRandomFloat(GetConVarFloat(hcv_ucMinChickenTime), GetConVarFloat(hcv_ucMaxChickenTime)), RespawnChicken, RoundNumber, TIMER_FLAG_NO_MAPCHANGE);
		
	}
}

public Action RespawnChicken(Handle hTimer, int RoundNum)
{
	/*
	ResetPack(DP);
	
	new RoundNum = ReadPackCell(DP);
	
	*/
	if(RoundNum < RoundNumber)
		return Plugin_Continue;
	/*
	new String:sOrigin[50], Float:Origin[3];
	
	ReadPackString(DP, sOrigin, sizeof(sOrigin));
	
	CloseHandle(DP);
	*/
	
	ChickenOriginPosition++;
	
	if(ChickenOriginPosition >= GetArraySize(ChickenOriginArray))
		ChickenOriginPosition = 0;
		
	char sOrigin[50];
	GetArrayString(ChickenOriginArray, ChickenOriginPosition, sOrigin, sizeof(sOrigin));
	
	SpawnChicken(sOrigin);
	
	return Plugin_Continue;
}

/*
public Action:Event_OnChickenKilled(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if(!IsValidEntity(victim))
		return Plugin_Continue;
		
	// Chicken is dead.
	
	new String:TargetName[100];
	GetEntPropString(victim, Prop_Data, "m_iName", TargetName, sizeof(TargetName));
	
	
	if(StrContains(TargetName, "UsefulCommands_Chickens") != -1)
	{
		ReplaceStringEx(TargetName, sizeof(TargetName), "UsefulCommands_Chickens ", "");
		
		new Float:Origin[3];
		GetStringVector(TargetName, Origin);
		
		SpawnChicken(Origin);
	}
	
	return Plugin_Continue;
}
*/
public int PartyModeCookieMenu_Handler(int client, CookieMenuAction action, int info, char[] buffer, int maxlen)
{
	if(action != CookieMenuAction_SelectOption)
		return;
		
	if(!GetConVarBool(hcv_ucPartyMode))	
	{
		ShowCookieMenu(client);
		UC_PrintToChat(client, "%T", "Party Mode is Disabled", client);
		return;
	}	
	ShowPartyModeMenu(client);
} 
public void ShowPartyModeMenu(int client)
{
	Handle hMenu = CreateMenu(PartyModeMenu_Handler);
	
	char TempFormat[64];
	switch(GetClientPartyMode(client))
	{
		case PARTYMODE_DEFUSE:
		{
			Format(TempFormat, sizeof(TempFormat), "%T", "Party Mode Cookie Menu: Defuse Only", client);
			AddMenuItem(hMenu, "", TempFormat);	
		}	
		
		case PARTYMODE_ZEUS:
		{
			Format(TempFormat, sizeof(TempFormat), "%T", "Party Mode Cookie Menu: Zeus Only", client);
			AddMenuItem(hMenu, "", TempFormat);	
		}
		
		case PARTYMODE_DEFUSE|PARTYMODE_ZEUS:
		{
			Format(TempFormat, sizeof(TempFormat), "%T", "Party Mode Cookie Menu: Enabled", client);
			AddMenuItem(hMenu, "", TempFormat);
		}
		
		default:
		{
			Format(TempFormat, sizeof(TempFormat), "%T", "Party Mode Cookie Menu: Disabled", client);
			AddMenuItem(hMenu, "", TempFormat);
		}
	}


	SetMenuExitBackButton(hMenu, true);
	SetMenuExitButton(hMenu, true);
	DisplayMenu(hMenu, client, 30);
}


public int PartyModeMenu_Handler(Handle hMenu, MenuAction action, int client, int item)
{
	if(action == MenuAction_DrawItem)
	{
		return ITEMDRAW_DEFAULT;
	}
	else if(action == MenuAction_Cancel && item == MenuCancel_ExitBack)
	{
		ShowCookieMenu(client);
	}
	else if(action == MenuAction_Select)
	{
		if(item == 0)
		{
			if(GetClientPartyMode(client) >= PARTYMODE_DEFUSE|PARTYMODE_ZEUS)
				SetClientPartyMode(client, PARTYMODE_NONE);
				
			else if(GetClientPartyMode(client) == PARTYMODE_NONE)
				SetClientPartyMode(client, PARTYMODE_DEFUSE);
				
			else if(GetClientPartyMode(client) == PARTYMODE_DEFUSE)
				SetClientPartyMode(client, PARTYMODE_ZEUS);
				
			else if(GetClientPartyMode(client) == PARTYMODE_ZEUS)
				SetClientPartyMode(client, PARTYMODE_DEFUSE|PARTYMODE_ZEUS);
		}
		
		ShowPartyModeMenu(client);
	}
	return 0;
}


public Action Event_PlayerSpawn(Handle hEvent, const char[] Name, bool dontBroadcast)
{	
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	g_bCursed[client] = false;
	
	//SetEntityFlags(client, GetEntityFlags(client) & ~FL_INWATER);
	UberSlapped[client] = false;
	RequestFrame(ResetTrueTeam, GetClientUserId(client));
	if(TIMER_UBERSLAP[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_UBERSLAP[client]);
		TIMER_UBERSLAP[client] = INVALID_HANDLE;
	}
	isHugged[client] = false;
	UC_TryDestroyGlow(client);
}

public void ResetTrueTeam(int UserId)
{
	TrueTeam[GetClientOfUserId(UserId)] = 0;
}

public Action Event_PlayerDeath(Handle hEvent, const char[] Name, bool dontBroadcast)
{	
	int clientUserId = GetEventInt(hEvent, "userid");
	
	int client = GetClientOfUserId(clientUserId);

	if(client == 0)
		return;
		
	int attackerUserId = GetEventInt(hEvent, "attacker");
	int attacker = GetClientOfUserId(attackerUserId);
	
	RoundKills[attacker]++;
	
	int Team = GetClientTrueTeam(client);
	
	if(Team != CS_TEAM_CT && Team != CS_TEAM_T)
		return;
		
	int candidateCT = 0;
	
	if(AceCandidate[CS_TEAM_CT] > 0)
		candidateCT = GetClientOfUserId(AceCandidate[CS_TEAM_CT])
		
	int candidateT = 0;

	if(AceCandidate[CS_TEAM_T] > 0)
		candidateT = GetClientOfUserId(AceCandidate[CS_TEAM_T])

	
	if(attacker == 0)
	{
		if(candidateT > 0 && Team == CS_TEAM_CT)
			AceCandidate[CS_TEAM_T] = -2; // Forbid possibility of Ace for the attacker's team.
			
		if(candidateCT > 0 && Team == CS_TEAM_T)
			AceCandidate[CS_TEAM_CT] = -2; // Forbid possibility of Ace for the attacker's team.
	}
	else
	{
		int attackerTeam = GetClientTeam(attacker);
	
		if(candidateT != 0)
		{
			if(candidateT != attacker && Team == CS_TEAM_CT)
			{
				AceCandidate[CS_TEAM_T] = -2; // Forbid possibility of Ace for the attacker's team.
			}
		}
		else if(attackerTeam == CS_TEAM_T && AceCandidate[CS_TEAM_T] == -1)
			AceCandidate[CS_TEAM_T] = attackerUserId; // Ace Candidate is only fullfilled in case all opponents are dead at time of victory.
			
		if(candidateCT != 0)
		{
			if(candidateCT != attacker && Team == CS_TEAM_T)
				AceCandidate[CS_TEAM_CT] = -2; // Forbid possibility of Ace for the attacker's team.
		}
		else if(attackerTeam == CS_TEAM_CT && AceCandidate[CS_TEAM_CT] == -1)
			AceCandidate[CS_TEAM_CT] = attackerUserId; // Ace Candidate is only fullfilled in case all opponents are dead at time of victory.
	}		
	UberSlapped[client] = false;
	if(TIMER_UBERSLAP[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_UBERSLAP[client]);
		TIMER_UBERSLAP[client] = INVALID_HANDLE;
	}

	if(TIMER_LASTC4[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_LASTC4[client]);
		TIMER_LASTC4[client] = INVALID_HANDLE;
	}
	
	if(LastC4Ref[client] != INVALID_ENT_REFERENCE)
	{
		int LastC4 = EntRefToEntIndex(LastC4Ref[client]);
		
		if(LastC4 != INVALID_ENT_REFERENCE)
		{
			char Classname[50];
			GetEdictClassname(LastC4, Classname, sizeof(Classname));
			
			if(StrEqual(Classname, "weapon_c4", true))
			{
				int Winner = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
					
				if(Winner == 0 ||	Winner != 0 && (client == Winner || GetClientTeam(Winner) != CS_TEAM_T) || !IsPlayerAlive(Winner))
					Winner = GetClientOfUserId(GetEventInt(hEvent, "assister"));
					
				if(Winner == 0 || Winner != 0 && (client == Winner || GetClientTeam(Winner) != CS_TEAM_T) || !IsPlayerAlive(Winner))
				{
					int[] players = new int[MaxClients+1];
					int count;
					
					Winner = 0;
					for(int i=1;i <= MaxClients;i++)
					{
						if(i == client)
							continue;
							
						else if(!IsClientInGame(i))
							continue;
							
						else if(!IsPlayerAlive(i))
							continue;
							
						else if(GetClientTeam(i) != CS_TEAM_T)
							continue;
							
						
						players[count++] = i;
					}
					
					Winner = players[GetRandomInt(0, count-1)];
				}
				
				if(Winner != 0)
				{
					AcceptEntityInput(LastC4, "Kill");
	
					GivePlayerItem(Winner, "weapon_c4");
				}
			}
		}
		
		LastC4Ref[client] = INVALID_ENT_REFERENCE;
	}
	UC_TryDestroyGlow(client);
	
	TrueTeam[client] = 0;
}

public Action Event_CsWinPanelRound(Handle hEvent, const char[] Name, bool dontBroadcast)
{
	if(GetConVarInt(hcv_ucAcePriority) == 0)
		return Plugin_Continue;

	int WinningTeam = -1;
	if(isCSGO())
		WinningTeam = GameRules_GetProp("m_iRoundWinStatus");
	
	else
	{
		WinningTeam = GetEventInt(hEvent, "winner", -1);
		
		if(WinningTeam == -1)
		{	
			show_timer_defend = GetEventBool(hEvent, "show_timer_defend");
			show_timer_attack = GetEventBool(hEvent, "show_timer_attack");
			timer_time = GetEventInt(hEvent, "timer_time");
			final_event = GetEventInt(hEvent, "final_event");
			
			GetEventString(hEvent, "funfact_token", funfact_token, sizeof(funfact_token));
			funfact_player = GetEventInt(hEvent, "funfact_player");
			funfact_data1 = GetEventInt(hEvent, "funfact_data1");
			funfact_data2 = GetEventInt(hEvent, "funfact_data2");
			funfact_data3 = GetEventInt(hEvent, "funfact_data3");

			BlockedWinPanel = true;
			return Plugin_Handled;
		}
	}

	int Winner = GetClientOfUserId(AceCandidate[WinningTeam]);
	
	if(Winner == 0 || RoundKills[Winner] == 0)
		return Plugin_Continue;
	
	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(!IsPlayerAlive(i))
			continue;
			
		if(GetClientTeam(i) != WinningTeam)
			return Plugin_Continue;
	}	
	
	Call_StartForward(fw_ucAce);
	
	char TokenToUse[100];
	GetClientAceFunFact(Winner, TokenToUse, sizeof(TokenToUse));
	Call_PushCellRef(Winner);
	Call_PushStringEx(TokenToUse, sizeof(TokenToUse), SM_PARAM_STRING_COPY|SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
	Call_PushCellRef(RoundKills[Winner]);
	
	Action Result;
	Call_Finish(Result);
	
	if(Result == Plugin_Stop)
		return Plugin_Continue;
	
	if(Result != Plugin_Changed)
	{
		Winner = GetClientOfUserId(AceCandidate[WinningTeam]);
		GetClientAceFunFact(Winner, TokenToUse, sizeof(TokenToUse));
	}
	
	if(Result != Plugin_Handled)
	{
		SetEventInt(hEvent, "funfact_player", Winner);
		
		SetEventString(hEvent, "funfact_token", TokenToUse);
		
		if(isCSGO())
			SetEventInt(hEvent, "funfact_data1", 420); // The percent of players killed ( in theory always 100 in ace but !revive can push it further. )
		
		else
			SetEventInt(hEvent, "funfact_data1", 100); // The percent of players killed ( in theory always 100 in ace but !revive can push it further. )
	}
	if(!AceSent)
	{
		AceSent = true;
		
		Call_StartForward(fw_ucAcePost);
		
		Call_PushCell(Winner);
		Call_PushString(TokenToUse);
		Call_PushCell(RoundKills[Winner]);
		
		Call_Finish();
	}
	return Plugin_Changed;
}

public void OnClientPutInServer(int client)
{
	Func_OnClientPutInServer(client);
}

public void Func_OnClientPutInServer(int client)
{
	DeathOrigin[client] = NULL_VECTOR;
	UberSlapped[client] = false;
	isHugged[client] = true;
	
	UCEdit[client] = false;
	FullInGame[client] = true;
	
	if(TIMER_ANNOUNCEPLUGIN[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_ANNOUNCEPLUGIN[client]);
		TIMER_ANNOUNCEPLUGIN[client] = INVALID_HANDLE;
	}
	
	float AnnounceTimer = GetConVarFloat(hcv_ucAnnouncePlugin);
	
	if(AnnounceTimer != 0.0)
		TIMER_ANNOUNCEPLUGIN[client] = CreateTimer(AnnounceTimer, Timer_AnnounceUCPlugin, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		
	SDKHook(client, SDKHook_WeaponDropPost, Event_WeaponDropPost);
	SDKHook(client, SDKHook_WeaponEquipPost, Event_WeaponPickupPost);
	SDKHook(client, SDKHook_OnTakeDamagePost, Event_OnTakeDamagePost);
}


public Action Timer_AnnounceUCPlugin(Handle hTimer, int UserId)
{
	int client = GetClientOfUserId(UserId);
	
	if(client == 0)
		return Plugin_Continue;

	TIMER_ANNOUNCEPLUGIN[client] = INVALID_HANDLE;
	UC_PrintToChat(client, "%t", "UC Advertise");
	UC_PrintToChat(client, "%t", "UC Advertise 2");
	return Plugin_Continue;
}

public void Event_WeaponPickupPost(int client, int weapon)
{
	if(!GetConVarBool(hcv_ucSpecialC4Rules))
		return;
	
	else if(weapon == -1)
		return;
		
	char Classname[50];
	GetEdictClassname(weapon, Classname, sizeof(Classname));
	
	if(!StrEqual(Classname, "weapon_c4", true))
		return;
		
	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(!IsPlayerAlive(i))
			continue;
			
		if(EntRefToEntIndex(LastC4Ref[i]) == weapon)
		{
			LastC4Ref[i] = INVALID_ENT_REFERENCE;
			
			if(TIMER_LASTC4[i] != INVALID_HANDLE)
			{
				CloseHandle(TIMER_LASTC4[i]);
				TIMER_LASTC4[i] = INVALID_HANDLE;
			}
		}
	}
	
	if(GetClientTeam(client) == CS_TEAM_CT)
		LastC4Ref[client] = EntIndexToEntRef(weapon);
}
public void Event_WeaponDropPost(int client, int weapon)
{
	if(!GetConVarBool(hcv_ucSpecialC4Rules))
		return;
		
	else if(GetClientTeam(client) != CS_TEAM_CT)
		return;
	
	else if(weapon == -1)
		return;
		
	char Classname[50];
	GetEdictClassname(weapon, Classname, sizeof(Classname));
	
	if(!StrEqual(Classname, "weapon_c4", true))
		return;
		
	LastC4Ref[client] = EntIndexToEntRef(weapon);
	
	if(TIMER_LASTC4[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_LASTC4[client]);
		TIMER_LASTC4[client] = INVALID_HANDLE;
	}	
	TIMER_LASTC4[client] = CreateTimer(5.0, GiveC4Back, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action GiveC4Back(Handle hTimer, int UserId)
{
	int client = GetClientOfUserId(UserId);
	
	if(client == 0)
		return;
	
	TIMER_LASTC4[client] = INVALID_HANDLE;
	
	if(LastC4Ref[client] == INVALID_ENT_REFERENCE)
		return;
	
	int LastC4 = EntRefToEntIndex(LastC4Ref[client]);
	
	if(!IsValidEntity(LastC4))
	{
		LastC4Ref[client] = INVALID_ENT_REFERENCE;
		return;
	}	
	
	
	AcceptEntityInput(LastC4, "Kill");
	
	GivePlayerItem(client, "weapon_c4");
	
	LastC4Ref[client] = INVALID_ENT_REFERENCE;
}

public void Event_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	float Scale = GetConVarFloat(hcv_TagScale);
	
	if(Scale == 1.0)
		return;
		
	float TotalVelocity = GetEntPropFloat(victim, Prop_Send, "m_flVelocityModifier") * Scale;
	
	if(TotalVelocity > 1.0)
		TotalVelocity = 1.0;
		
	SetEntPropFloat(victim, Prop_Send, "m_flVelocityModifier", TotalVelocity);
	
	return;
}

public void OnClientDisconnect(int client)
{
	int candidateCT = 0;
	int candidateT = 0;
	
	if(AceCandidate[CS_TEAM_CT] > 0)
		candidateCT = GetClientOfUserId(AceCandidate[CS_TEAM_CT]);
		
	if(AceCandidate[CS_TEAM_T] > 0)
		candidateT = GetClientOfUserId(AceCandidate[CS_TEAM_T]);
		
	if(candidateT == client)
		AceCandidate[CS_TEAM_T] = -2; // Forbid possibility of Ace for the leaver's team.
	
	if(candidateCT == client)
		AceCandidate[CS_TEAM_CT] = -2; // Forbid possibility of Ace for the leaver's team.
		
	if(TIMER_UBERSLAP[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_UBERSLAP[client]);
		TIMER_UBERSLAP[client] = INVALID_HANDLE;
	}

	if(TIMER_LIFTOFF[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_LIFTOFF[client]);
		TIMER_LIFTOFF[client] = INVALID_HANDLE;
	}
	if(TIMER_ROCKETCHECK[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_ROCKETCHECK[client]);
		TIMER_ROCKETCHECK[client] = INVALID_HANDLE;
	}
	if(TIMER_LASTC4[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_LASTC4[client]);
		TIMER_LASTC4[client] = INVALID_HANDLE;
	}	
	if(TIMER_ANNOUNCEPLUGIN[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_ANNOUNCEPLUGIN[client]);
		TIMER_ANNOUNCEPLUGIN[client] = INVALID_HANDLE;
	}
	char AuthId[32];
	if(!IsFakeClient(client) && GetClientAuthId(client, AuthId_Engine, AuthId, sizeof(AuthId)))
	{
		char sQuery[256];
		
		char Name[32], IPAddress[32], CurrentTime = GetTime();
		GetClientName(client, Name, sizeof(Name));
		GetClientIP(client, IPAddress, sizeof(IPAddress));
		dbLocal.Format(sQuery, sizeof(sQuery), "INSERT OR IGNORE INTO UsefulCommands_LastPlayers (AuthId, IPAddress, Name, LastConnect) VALUES ('%s', '%s', '%s', %i)", AuthId, IPAddress, Name, CurrentTime);
		dbLocal.Query(SQLCB_Error, sQuery, _, DBPrio_High);
		
		dbLocal.Format(sQuery, sizeof(sQuery), "UPDATE UsefulCommands_LastPlayers SET IPAddress = '%s', Name = '%s', LastConnect = %i WHERE AuthId = '%s'", IPAddress, Name, CurrentTime, AuthId);
		dbLocal.Query(SQLCB_Error, sQuery, _, DBPrio_Normal);
	}
}

public void OnClientDisconnect_Post(int client)
{
	FullInGame[client] = false;
	DeathOrigin[client] = NULL_VECTOR;
	if(TIMER_UBERSLAP[client] != INVALID_HANDLE)
	{
		CloseHandle(TIMER_UBERSLAP[client]);
		TIMER_UBERSLAP[client] = INVALID_HANDLE;
	}
	
	if(LastC4Ref[client] != INVALID_ENT_REFERENCE)
	{
		int LastC4 = EntRefToEntIndex(LastC4Ref[client]);
		
		if(LastC4 != INVALID_ENT_REFERENCE)
		{
			char Classname[50];
			GetEdictClassname(LastC4, Classname, sizeof(Classname));
			
			if(StrEqual(Classname, "weapon_c4", true))
			{
				int[] players = new int[MaxClients+1];
				int count, Winner = 0;
				
				for(int i=1;i <= MaxClients;i++)
				{
					if(!IsClientInGame(i))
						continue;
							
					else if(!IsPlayerAlive(i))
						continue;
							
					else if(GetClientTeam(i) != CS_TEAM_T)
						continue;
					
					players[count++] = i;
				}
					
				Winner = players[GetRandomInt(0, count-1)];
				
				if(Winner != 0)
				{
					AcceptEntityInput(LastC4, "Kill");
		
					GivePlayerItem(Winner, "weapon_c4");
				}
			}
		}
	}
	UberSlapped[client] = false;
	isHugged[client] = true;
	UC_TryDestroyGlow(client);
	UC_SetClientRocket(client, false);
}

public void OnPluginEnd()
{
	for(int i=1;i < MAXPLAYERS+1;i++)
	{
		UC_TryDestroyGlow(i);
	}
}

public void OnMapEnd()
{
	MapStarted = false;

	if(BombResetsArray != INVALID_HANDLE)
	{
		CloseHandle(BombResetsArray);
		BombResetsArray = INVALID_HANDLE;
	}
}

public void OnMapStart()
{
	RestartNR = true;
	RoundNumber++;
	GetCurrentMap(MapName, sizeof(MapName));
	
	if(isCSGO())
	{
		PrecacheModel("models/chicken/chicken.mdl");
		MapStarted = true;
		
		if(BombResetsArray != INVALID_HANDLE)
		{
			CloseHandle(BombResetsArray);
			BombResetsArray = INVALID_HANDLE;
		}

		BombResetsArray = CreateArray(1);
		
		if(ChickenOriginArray != INVALID_HANDLE)
		{
			CloseHandle(ChickenOriginArray);
			ChickenOriginArray = INVALID_HANDLE;
		}
		ChickenOriginArray = CreateArray(50);
		
		if(TeleportsArray != INVALID_HANDLE)
		{
			for(int i=0; i < GetArraySize(TeleportsArray);i++)
			{
				int entity = EntRefToEntIndex(GetArrayCell(TeleportsArray, i));
				
				if(entity == INVALID_ENT_REFERENCE)
				{
					RemoveFromArray(TeleportsArray, i--);
					continue;
				}
					
				Event_TeleportSpawnPost(entity);
			}
			
			CloseHandle(TeleportsArray);
		
			TeleportsArray = INVALID_HANDLE;
		}
		PrecacheSoundAny(PartySound);
	
		PrecacheSoundAny(ItemPickUpSound);
	}
	
	ConnectToDatabase();
	
	for(int i=1;i < MAXPLAYERS+1;i++)
	{
		TIMER_UBERSLAP[i] = INVALID_HANDLE;
		TIMER_LIFTOFF[i] = INVALID_HANDLE;
		TIMER_ROCKETCHECK[i] = INVALID_HANDLE;
		TIMER_LASTC4[i] = INVALID_HANDLE;
		TIMER_ANNOUNCEPLUGIN[i] = INVALID_HANDLE;
	}
	
	hRestartTimer = INVALID_HANDLE;
	hNotifyRestartTimer = INVALID_HANDLE;
	hRRTimer = INVALID_HANDLE;
	RestartNR = false;
	
	RequestFrame(RestartRoundOnMapStart);
	
	if(isCSGO)
		TriggerTimer(CreateTimer(3600.0, Timer_FromMapStart_PerHour, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT), true);
}

public Action Timer_FromMapStart_PerHour(Handle hTimer)
{
	if(hRestartTimer == INVALID_HANDLE && GetConVarBool(hcv_ucIgnoreRoundWinConditions))
	{
		GameRules_SetPropFloat("m_flGameStartTime", GetGameTime());
		GameRules_SetPropFloat("m_fRoundStartTime", GetGameTime());
	}
		
}
public void RestartRoundOnMapStart()
{
	if(!isLateLoaded && GetConVarBool(hcv_ucRestartRoundOnMapStart))
		CS_TerminateRound(0.1, CSRoundEnd_Draw, true);
}

public void OnGameFrame()
{
	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(!IsPlayerAlive(i))
			continue;
			
		GetEntPropVector(i, Prop_Data, "m_vecOrigin", DeathOrigin[i]);	
	}
}

public Action Command_Revive(int client, int args)
{	
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target", arg0);
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));

	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_NONE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		if(UC_IsValidTeam(target))
		{
			if( (GetConVarBool(hcv_mpRespawnOnDeathCT) && GetClientTeam(target) == CS_TEAM_CT) || (GetConVarBool(hcv_mpRespawnOnDeathT) && GetClientTeam(target) == CS_TEAM_T) )
				continue;
				
			UC_RespawnPlayer(target);
		}
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Respawned", target_name);
	
	return Plugin_Handled;
}

public Action Command_HardRevive(int client, int args)
{	
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target", arg0);
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));

	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_NONE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		bool isAlive = IsPlayerAlive(target); // Was he alive before the 1up?
		
		if( isAlive || (GetConVarBool(hcv_mpRespawnOnDeathCT) && GetClientTeam(target) == CS_TEAM_CT) || (GetConVarBool(hcv_mpRespawnOnDeathT) && GetClientTeam(target) == CS_TEAM_T) )
			continue;
				
		UC_RespawnPlayer(target);
		
		if(!UC_IsNullVector(DeathOrigin[target]) && !isAlive)
			TeleportEntity(target, DeathOrigin[target], NULL_VECTOR, NULL_VECTOR);
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Hard Respawned", target_name);
	
	return Plugin_Handled;
}


public Action Command_Bury(int client, int args)
{	
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target Toggle", arg0);
		return Plugin_Handled;
	}

	char arg[65], arg2[5];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));

	if(StrEqual(arg2, ""))
		arg2 = "1";
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	bool bury = (StringToInt(arg2) != 0);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		if(bury)
		{
			if(IsPlayerStuck(target) && target_count == 1)
			{
				UC_ReplyToCommand(client, "%s%t", UCTag, "Already Buried", target);
				return Plugin_Handled;
			}	
			UC_BuryPlayer(target);
		}
		else
		{
			if(!IsPlayerStuck(target))
			{
				if(target_count == 1)
				{
					UC_ReplyToCommand(client, "%s%t", UCTag, "Already Not Buried", target);
					return Plugin_Handled;
				}
				
				continue;
			}
			UC_UnburyPlayer(target);
		}
	}
	
	if(bury)
		UC_ShowActivity2(client, UCTag, "%t", "Player Buried", target_name);
		
	else
		UC_ShowActivity2(client, UCTag, "%t", "Player Unburied", target_name);
		
	return Plugin_Handled;
}

public Action Command_Unbury(int client, int args)
{	
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target", arg0);
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;

	}
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		if(!IsPlayerStuck(target))
		{
			if(target_count == 1)
			{
				UC_ReplyToCommand(client, "%s%t", UCTag, "Already Not Buried", target);
				return Plugin_Handled;
			}
			
			continue;
		}
		UC_UnburyPlayer(target);
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Unburied", target_name);
	return Plugin_Handled;
}
public Action Command_UberSlap(int client, int args)
{
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target Toggle", arg0);
		return Plugin_Handled;
	}

	char arg[65], arg2[5];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));

	if(StrEqual(arg2, ""))
		arg2 = "1";
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	bool slap = (StringToInt(arg2) != 0);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		if(slap)
		{
			if(UberSlapped[target])
			{
				if(target_count == 1)
				{
					UC_ReplyToCommand(client, "%s%t", UCTag, "Player Already Uberslapped", target);
					return Plugin_Handled;
				}
				
				continue;
			}
			UberSlapped[target] = true;
			TotalSlaps[target] = 0;
			
			TeleportEntity(target, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 10.0}));
			TriggerTimer(TIMER_UBERSLAP[target] = CreateTimer(0.1, Timer_UberSlap, GetClientUserId(target), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE), true);
		}
		else
		{
			if(!UberSlapped[target])
			{
				if(target_count == 1)
				{
					UC_ReplyToCommand(client, "%s%t", UCTag, "Player Already Not Uberslapped", target);
					return Plugin_Handled;
				}
				
				continue;
			}
			UberSlapped[target] = false;
			if(TIMER_UBERSLAP[target] != INVALID_HANDLE)
			{
				CloseHandle(TIMER_UBERSLAP[target]);
				TIMER_UBERSLAP[target] = INVALID_HANDLE;
			}
		}
		
		if(slap)
			UC_ShowActivity2(client, UCTag, "%t", "Player Uberslapped", target_name);
			
		else
			UC_ShowActivity2(client, UCTag, "%t", "Player Stop Uberslap", target_name);
	}
	return Plugin_Handled;
}

public Action Timer_UberSlap(Handle hTimer, int UserId)
{
	int client = GetClientOfUserId(UserId);
	
	if(client == 0)
		return Plugin_Stop;

	else if(!UberSlapped[client])
	{
		TIMER_UBERSLAP[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
		
	TotalSlaps[client]++;
	if(TotalSlaps[client] >= 100 || (UC_UnlethalSlap(client, 1) && TotalSlaps[client] >= 10))
	{
		UberSlapped[client] = false;
		TIMER_UBERSLAP[client] = INVALID_HANDLE;
		UC_PrintToChat(client, "%s\x02Uberslap has ended.\x04 Prepare your landing!", UCTag);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}


public Action Command_Heal(int client, int args)
{
	if (args < 1)
	{
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Heal");
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Note Heal");
		return Plugin_Handled;
	}

	char arg[65], arg2[11], arg3[11], arg4[3];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));
	GetCmdArg(3, arg3, sizeof(arg3));
	GetCmdArg(4, arg4, sizeof(arg4));
	StripQuotes(arg2);
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	if(args == 1)
		arg2 = "max";
		
	int health = UC_IsStringNumber(arg2) ? StringToInt(arg2) : -1;

	if(health > MAX_POSSIBLE_HP)
		health = MAX_POSSIBLE_HP;
		
	int armor = UC_IsStringNumber(arg3) ? StringToInt(arg3) : -1;
	
	if(armor > 255 || StrEqual(arg3, "max"))
		armor = 255;
		
	int helmet = UC_IsStringNumber(arg4) ? StringToInt(arg4) : -1;
	
	char ActivityBuffer[256];
	
	if(StrEqual(arg4, "max"))
		helmet = 1
		
	else if(helmet > 1) // The helmet will never be a negative.
		helmet = -1;

	bool bHelmet = view_as<bool>(helmet);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		if(StrEqual(arg2, "max"))
			health = GetEntProp(target, Prop_Data, "m_iMaxHealth");
			
		if(health != -1)
		{
			SetEntityHealth(target, health);
		}
		if(armor != -1)
		{
			SetClientArmor(target, armor);
		}
		if(helmet != -1)
		{
			SetClientHelmet(target, bHelmet);
		}	
	}
	
	Format(ActivityBuffer, sizeof(ActivityBuffer), "%t", "Heal Admin Set", target_name);
	
	if(health != -1)
	{
		Format(ActivityBuffer, sizeof(ActivityBuffer), "%s%t", ActivityBuffer, "Heal Admin Set Health", health);
	}
	if(armor != -1)
	{
		Format(ActivityBuffer, sizeof(ActivityBuffer), "%s%t", ActivityBuffer, "Heal Admin Set Armor", armor);
	}
	if(helmet != -1)
	{
		Format(ActivityBuffer, sizeof(ActivityBuffer), "%s%t", ActivityBuffer, "Heal Admin Set Helmet", helmet);
	}
	
	int length = strlen(ActivityBuffer);
	ActivityBuffer[length-2] = '.';
	ActivityBuffer[length-1] = EOS;
	UC_ShowActivity2(client, UCTag, ActivityBuffer); 
	
	return Plugin_Handled;
}

public Action Command_Give(int client, int args)
{
	if (args < 2)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Give", arg0);
		return Plugin_Handled;
	}

	char arg[65], arg2[65];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	char WeaponName[65];
	
	if(StrContains(arg2, "weapon_", false) == -1)
	{
		Format(WeaponName, sizeof(WeaponName), "weapon_%s", arg2);
		Format(arg2, sizeof(arg2), WeaponName);
	}
	else
		Format(WeaponName, sizeof(WeaponName), arg2);
	
	int length = strlen(WeaponName);
	
	for(int a=0;a < length;a++)
	{
		WeaponName[a] = CharToLower(WeaponName[a]);
		
		if(WeaponName[a] == '_')
		{
			char TempWeaponName[65];
			Format(TempWeaponName, a+2, WeaponName);
			ReplaceStringEx(WeaponName, sizeof(WeaponName), TempWeaponName, "");
			break;
		}
	}
	
	ReplaceString(arg2, sizeof(arg2), "zeus", "taser");
	ReplaceString(WeaponName, sizeof(WeaponName), "zeus", "taser");
	
	ReplaceString(arg2, sizeof(arg2), "bomb", "c4");
	ReplaceString(WeaponName, sizeof(WeaponName), "bomb", "c4");
	
	ReplaceString(arg2, sizeof(arg2), "kit", "defuser");
	ReplaceString(WeaponName, sizeof(WeaponName), "kit", "defuser");
	
	int weapon = -1;
	
	for(int count=0;count < target_count;count++)
	{
		int target = target_list[count];
		
		if((weapon = GivePlayerItem(target, arg2)) == -1)
		{
			ReplaceStringEx(arg2, sizeof(arg2), "weapon_", "item_");
			
			if((weapon = GivePlayerItem(target, arg2)) == -1)
			{
				UC_ReplyToCommand(client, "%s%t", UCTag, "Command Give Invalid Weapon", WeaponName);
			
				return Plugin_Handled;
			}
		}
		
		if(weapon != -1)
		{
			RemovePlayerItem(target, weapon);
			
			AcceptEntityInput(weapon, "Kill");
		}
		
		if(StrEqual(arg2, "weapon_c4"))
		{
			if(GetClientTeam(target) == CS_TEAM_CT)
			{	
				
				if(isCSGO())
				{
					char OldValue[32];
					GetConVarString(hcv_mpAnyoneCanPickupC4, OldValue, sizeof(OldValue));
					
					if(!GetConVarBool(hcv_mpAnyoneCanPickupC4))
					{
						SetConVarString(hcv_mpAnyoneCanPickupC4, "1UsefulCommands1");
					
						Handle DP = CreateDataPack();
						
						WritePackCell(DP, target);
						WritePackString(DP, OldValue);
						RequestFrame(EquipBombToPlayer, DP);
					}
					else
						GivePlayerItem(target, "weapon_c4");
				}
				else
				{
				
					SetEntProp(target, Prop_Send, "m_iTeamNum", CS_TEAM_T);
					
					GivePlayerItem(target, "weapon_c4");
					
					SetEntProp(target, Prop_Send, "m_iTeamNum", CS_TEAM_CT);
				}
			}
			else
				weapon = GivePlayerItem(target, arg2);
		}
		else
		{
			weapon = CreateEntityByName("game_player_equip");
		
			DispatchKeyValue(weapon, arg2, "0");
			
			DispatchKeyValue(weapon, "spawnflags", "1");
			
			AcceptEntityInput(weapon, "use", target);
			
			AcceptEntityInput(weapon, "Kill");
			
			weapon = -1;
		}
		
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Given Weapon", WeaponName, target_name); 

	return Plugin_Handled;
}

public void EquipBombToPlayer(Handle DP)
{
	ResetPack(DP);
	
	int target = ReadPackCell(DP);
	
	char OldValue[32];
	ReadPackString(DP, OldValue, sizeof(OldValue));
	
	CloseHandle(DP);
	GivePlayerItem(target, "weapon_c4");
	
	SetConVarString(hcv_mpAnyoneCanPickupC4, OldValue);
}

public Action Command_RestartRound(int client, int args)
{
	if(hRRTimer != INVALID_HANDLE)
	{
		CloseHandle(hRestartTimer);
		hRestartTimer = INVALID_HANDLE;
	}
	
	float SecondsBeforeRestart;
	char Arg[15];
	if(args > 0)
	{
		GetCmdArg(1, Arg, sizeof(Arg));
	
		SecondsBeforeRestart = StringToFloat(Arg);
	}
	else
		SecondsBeforeRestart = 1.0;
		
	
	if(SecondsBeforeRestart > 0.3)
	{
		int iSecondsBeforeRestart = RoundFloat(SecondsBeforeRestart);
		
		char strSecondsBeforeRestart[11];
		IntToString(iSecondsBeforeRestart, strSecondsBeforeRestart, sizeof(strSecondsBeforeRestart));
		
		switch(isCSGO())
		{
			case true:
			{
				if(iSecondsBeforeRestart == 1)
					Format(Arg, sizeof(Arg), "#SFUI_Second");
					
				else 
					Format(Arg, sizeof(Arg), "#SFUI_Seconds");
			}
			case false:
			{
				if(iSecondsBeforeRestart == 1)
					Format(Arg, sizeof(Arg), "SECOND"); // It won't even translate the word "seconds" lmao.
					
				else 
					Format(Arg, sizeof(Arg), "SECONDS");
			}
		}	
		
		UC_PrintCenterTextAll("#Game_will_restart_in", strSecondsBeforeRestart, Arg);
	
		if(iSecondsBeforeRestart == 1)
			Format(Arg, sizeof(Arg), "Second");
			
		else 
			Format(Arg, sizeof(Arg), "Seconds");

		UC_PrintToChatAll("%s%t", UCTag, "Admin Restart Round", client, iSecondsBeforeRestart, Arg);
		hRRTimer = CreateTimer(SecondsBeforeRestart, RestartRound, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		if(hRRTimer != INVALID_HANDLE)
		{
			CloseHandle(hRRTimer);
			hRRTimer = INVALID_HANDLE;
		}
		UC_PrintToChatAll("%s%t", UCTag, "Admin Stopped Restart Round", client);
	}
	return Plugin_Handled;
}

public Action RestartRound(Handle hTimer)
{
	hRRTimer = INVALID_HANDLE;	
	
	CS_TerminateRound(0.1, CSRoundEnd_Draw, true);
}

public Action Command_RestartGame(int client, int args)
{
	int SecondsBeforeRestart;
	
	char Arg[11];
	
	if(args > 0)
	{
		GetCmdArg(1, Arg, sizeof(Arg));
		
		SecondsBeforeRestart = StringToInt(Arg);
	}
	else
		SecondsBeforeRestart = 1;
	
	ServerCommand("mp_restartgame %i", SecondsBeforeRestart);
	
	if(SecondsBeforeRestart != 0)
	{
		if(SecondsBeforeRestart == 1)
			Format(Arg, sizeof(Arg), "Second");
			
		else 
			Format(Arg, sizeof(Arg), "Seconds");
		
		UC_PrintToChatAll("%s%t", UCTag, "Admin Restart Game", client, SecondsBeforeRestart, Arg);
	}	
	else
	{
		if(isCSGO())
		{
			GameRules_SetProp("m_bGameRestart", 0);
			GameRules_SetPropFloat("m_flRestartRoundTime", 0.0);
		}	
		UC_PrintToChatAll("%s%t", UCTag, "Admin Stopped Restart Game", client);
	}
	return Plugin_Handled;
}

public Action Command_RestartServer(int client, int args)
{
	if(hRestartTimer == INVALID_HANDLE && !RestartNR)
	{
		char Arg[15];

		GetCmdArg(1, Arg, sizeof(Arg));

		int SecondsBeforeRestart;
		if(!StrEqual(Arg, "NR", false) && !StrEqual(Arg, "Next Round", false) && !StrEqual(Arg, "NextRound", false))
		{	
			if(args > 0)
				SecondsBeforeRestart = StringToInt(Arg);

			else
				SecondsBeforeRestart = 5;
			
			if(SecondsBeforeRestart == 0)
				return Plugin_Handled;
			
			int result;
			Call_StartForward(fw_ucCountServerRestart);
			
			Call_Finish(result);
			
			if(result > SecondsBeforeRestart)
			{
				UC_ReplyToCommand(client, "%s%t", UCTag, "Restart Server Blocked By Other Plugin", result);
				return Plugin_Handled;
			}
			
			hNotifyRestartTimer = CreateTimer(float(SecondsBeforeRestart - result), NotifyRestartServer, result, TIMER_FLAG_NO_MAPCHANGE);
			hRestartTimer = CreateTimer(float(SecondsBeforeRestart), RestartServer, _, TIMER_FLAG_NO_MAPCHANGE);
			
			if(isCSGO && GetConVarBool(hcv_ucIgnoreRoundWinConditions))
			{
				GameRules_SetPropFloat("m_flGameStartTime", GetGameTime());
				GameRules_SetPropFloat("m_fRoundStartTime", GetGameTime());
				GameRules_SetProp("m_iRoundTime", SecondsBeforeRestart);
			}
				
			if(SecondsBeforeRestart == 1)
				Format(Arg, sizeof(Arg), "Second");
				
			else 
				Format(Arg, sizeof(Arg), "Seconds");
				
			UC_PrintToChatAll("%s%t", UCTag, "Admin Restart Server", client, SecondsBeforeRestart, Arg);
		}
		else
		{
			RestartTimestamp = 0;
			
			Call_StartForward(fw_ucCountServerRestart);
			
			Call_Finish(RestartTimestamp);
			
			RestartNR = true;
			
			RestartTimestamp += GetTime();
			
			Call_StartForward(fw_ucNotifyServerRestart);
			
			Call_PushCell(-1);
			
			Call_Finish();
			
			UC_PrintToChatAll("%s%t", UCTag, "Admin Restart Server Next Round", client);
		}
	}
	else
	{
		CloseHandle(hRestartTimer);
		hRestartTimer = INVALID_HANDLE;
		
		CloseHandle(hNotifyRestartTimer);
		hNotifyRestartTimer = INVALID_HANDLE;
		
		Call_StartForward(fw_ucServerRestartAborted);
		
		Call_Finish();
		
		if(isCSGO && GetConVarBool(hcv_ucIgnoreRoundWinConditions))
			GameRules_SetProp("m_iRoundTime", 0);
				
		RestartNR = false;
		UC_PrintToChatAll("%s%t", UCTag, "Admin Stopped Restart Server", client);
	}
	
	return Plugin_Handled;
}

public Action NotifyRestartServer(Handle hTimer, int SecondsLeft)
{
	Call_StartForward(fw_ucNotifyServerRestart);
	
	Call_PushCell(SecondsLeft);
	
	Call_Finish();
}
public Action RestartServer(Handle hTimer)
{
	hRestartTimer = INVALID_HANDLE;	
	hNotifyRestartTimer = INVALID_HANDLE;
	
	UC_RestartServer();
}

public Action Command_Glow(int client, int args)
{
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Glow", arg0);
		return Plugin_Handled;
	}
	char arg[65], arg2[50];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));

	if(StrEqual(arg2, "color", false) || StrEqual(arg2, "colors", false))
	{
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Glow List");
		
		for(int i=0;i < sizeof(GlowData);i++)
		{
			bool isWhite = StrEqual(GlowData[i].GlowName, "White", false);
			if(!isWhite || (isWhite && isCSGO()))
				PrintToConsole(client, GlowData[i].GlowName);
		}
		return Plugin_Handled;
	}
	int Color[3];
	
	if(StrEqual(arg2, ""))
	{
		if(isCSGO())
			Format(arg2, sizeof(arg2), GlowData[GetRandomInt(0, sizeof(GlowData)-1)].GlowName);
			
		else
			Format(arg2, sizeof(arg2), GlowData[GetRandomInt(0, sizeof(GlowData)-2)].GlowName);
	}
	
	bool glow = (!StrEqual(arg2, "off", false));
	
	if(glow)
	{
		for(int i=0;i < sizeof(GlowData);i++)
		{
			bool isWhite = StrEqual(GlowData[i].GlowName, "White", false);
			if(StrEqual(arg2, GlowData[i].GlowName, false) && (!isWhite || (isWhite && isCSGO())))
			{
				Color[0] = GlowData[i].GlowColorR;
				Color[1] = GlowData[i].GlowColorG;
				Color[2] = GlowData[i].GlowColorB;
				break;
			}
			else if(i == sizeof(GlowData)-1)
			{
				UC_ReplyToCommand(client, "%s%t", UCTag, "Command Glow Invalid");
				return Plugin_Handled;
			}
		}
	}
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		if(glow)
		{
			UC_TryDestroyGlow(target);
			

			if(!UC_CreateGlow(target, Color) && target_count == 1)
			{
				UC_ReplyToCommand(client, "%s%t", UCTag, "Command Glow Failed to Give");
				return Plugin_Handled;
			}
		}
		else
		{
			if(!UC_TryDestroyGlow(target) && target_count == 1)
			{
				UC_ReplyToCommand(client, "%s%t", UCTag, "Command Glow Failed to Remove", target);
				return Plugin_Handled;
			}	
		}
	}
	
	
	if(glow)
		UC_ShowActivity2(client, UCTag, "%t", "Player Given Glow", target_name); 
		
	else
		UC_ShowActivity2(client, UCTag, "%t", "Player Removed Glow", target_name); 
		
	return Plugin_Handled;
}

public Action Command_Blink(int client, int args)
{
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target", arg0);
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));

	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	bool self = false;
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		if(client == target)
		{
			self = true;
			continue;
		}
		float Origin[3];
		if(!UC_GetAimPositionBySize(client, target, Origin))
		{
			UC_ReplyToCommand(client, "Cannot teleport");
			return Plugin_Handled;
		}
		
		TeleportEntity(target, Origin, NULL_VECTOR, NULL_VECTOR);
	}
	
	if(self)
	{
		float Origin[3];
		if(!UC_GetAimPositionBySize(client, client, Origin))
		{
			UC_ReplyToCommand(client, "Cannot teleport");
			return Plugin_Handled;
		}
		
		TeleportEntity(client, Origin, NULL_VECTOR, NULL_VECTOR);
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Blinked", target_name); 
	
	return Plugin_Handled;
}


public Action Command_GoTo(int client, int args)
{
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target", arg0);
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));

	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE|COMMAND_FILTER_NO_MULTI,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	int target = target_list[0];
		
	if(client == target)
	{
		ReplyToTargetError(client, COMMAND_TARGET_IMMUNE);
		return Plugin_Handled;
	}
	
	float Origin[3];
	
	GetClientAbsOrigin(target, Origin);
	// GetEntPropVector(target, Prop_Data, "m_vecOrigin", Origin);
	
	if(
	(view_as<Collision_Group_t>(GetEntProp(client, Prop_Send, "m_CollisionGroup")) == COLLISION_GROUP_DEBRIS_TRIGGER && view_as<Collision_Group_t>(GetEntProp(target, Prop_Send, "m_CollisionGroup")) == COLLISION_GROUP_DEBRIS_TRIGGER)
	|| (hcv_SolidTeammates != INVALID_HANDLE && GetConVarInt(hcv_SolidTeammates) != 1 && GetClientTeam(client) == GetClientTeam(target))
	|| LibraryExists("Never_Stuck_Inside_Players"))
	{
		TeleportEntity(client, Origin, NULL_VECTOR, NULL_VECTOR);
	}
	else
	{
		float HeightOffset = 73.0;
		
		if(IsPlayerStuck(client, Origin, HeightOffset))
		{
			UC_ReplyToCommand(client, "Cannot teleport");
			return Plugin_Handled;
		}
		
		Origin[2] += HeightOffset;
		
		TeleportEntity(client, Origin, NULL_VECTOR, NULL_VECTOR);
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Teleported to Player", target_name); 
	
	return Plugin_Handled;
}


public Action Command_Godmode(int client, int args)
{
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target Toggle", arg0);
		return Plugin_Handled;
	}

	char arg[65], arg2[5];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));

	if(StrEqual(arg2, ""))
		arg2 = "1";
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	bool god = (StringToInt(arg2) != 0);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		if(god)
		{
			if(UC_GetClientGodmode(target) && target_count == 1)
			{
				UC_ReplyToCommand(client, "%s%t", UCTag, "Already Godmode", target);
				return Plugin_Handled;
			}

			UC_SetClientGodmode(target, true);
		}
		else
		{
			if(!UC_GetClientGodmode(target) && target_count == 1)
			{
				UC_ReplyToCommand(client, "%s%t", UCTag, "Already Not Godmode", target);
				return Plugin_Handled;
			}
			
			UC_SetClientGodmode(target, false);
		}
	}
	
	if(god)
		UC_ShowActivity2(client, UCTag, "%t", "Player Given Godmode", target_name);
		
	else
		UC_ShowActivity2(client, UCTag, "%t", "Player Removed Godmode", target_name);
		
	return Plugin_Handled;
}

public Action Command_Rocket(int client, int args)
{
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target Toggle", arg0);
		return Plugin_Handled;
	}

	char arg[65], arg2[65];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));

	if(StrEqual(arg2, ""))
		arg2 = "1";
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	bool rocket = (StringToInt(arg2) != 0);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		UC_SetClientRocket(target, rocket);
	}
	
	if(rocket)
		UC_ShowActivity2(client, UCTag, "%t", "Player Given Rocket", target_name); 
	
	else 
		UC_ShowActivity2(client, UCTag, "%t", "Player Removed Rocket", target_name);
		
	return Plugin_Handled;
}


public Action Command_Disarm(int client, int args)
{
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target", arg0);
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));

	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		UC_StripPlayerWeapons(target);
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Stripped", target_name);
	
	return Plugin_Handled;
}

/*
public Action Command_MarkOfDeath(int client, int args)
{	
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target Toggle", arg0);
		return Plugin_Handled;
	}

	char arg[65], arg2[5];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));

	if(StrEqual(arg2, ""))
		arg2 = "1";
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	bool mark = (StringToInt(arg2) != 0);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		UC_DeathMarkPlayer(target, mark);
	}
	
	if(mark)
		UC_ShowActivity2(client, UCTag, "%t", "Player Marked", target_name);
		
	else
		UC_ShowActivity2(client, UCTag, "%t", "Player Unmarked", target_name);
		
	return Plugin_Handled;
}
*/
public Action Command_EarRapeTest(int client, int args)
{
	if (args < 1)
	{
		for(int i=1;i <= MaxClients;i++)
		{
			if(!IsClientInGame(i))
				continue;
				
			SetListenOverride(client, i, Listen_Default);
		}
		UC_ReplyToCommand(client, "%s%t", UCTag, "Cleared Ear Rape Test");
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Ear Rape Zero Arg Hint");
		
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_NO_MULTI,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	int target = target_list[0];

	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		SetListenOverride(client, i, i == target ? Listen_Yes : Listen_No);
	}
		
	UC_ShowActivity2(client, UCTag, "%t", "Player Ear Rape Tested", target_name);
	
	return Plugin_Handled;
}


public Action Command_Curse(int client, int args)
{
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Target Toggle", arg0);
		return Plugin_Handled;
	}

	char arg[65], arg2[65];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));

	if(StrEqual(arg2, ""))
		arg2 = "1";
		
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					COMMAND_FILTER_ALIVE,
					target_name,
					sizeof(target_name),
					tn_is_ml);


	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	bool curse = (StringToInt(arg2) != 0);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		UC_SetClientCurse(target, curse);
	}
	
	if(curse)
		UC_ShowActivity2(client, UCTag, "%t", "Player Given Curse", target_name); 
	
	else 
		UC_ShowActivity2(client, UCTag, "%t", "Player Removed Curse", target_name);
		
	return Plugin_Handled;
}

public Action Command_Exec(int client, int args)
{
	if (args < 2)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Execute", arg0);
		return Plugin_Handled;
	}

	char arg[65], ExecCommand[150];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArgString(ExecCommand, sizeof(ExecCommand));
	StripQuotes(ExecCommand);
	
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					0,
					target_name,
					sizeof(target_name),
					tn_is_ml);

					
	Format(arg, sizeof(arg), "%s ", arg); // This nullifies the use of arg any longer.
	ReplaceStringEx(ExecCommand, sizeof(ExecCommand), arg, "");

	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];

		ClientCommand(target, ExecCommand);
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Executed", ExecCommand, target_name);
	LogAction(client, -1, "\"%L\" executed \"%s\" on \"%s\"", client, ExecCommand, target_name);
	
	return Plugin_Handled;
}


public Action Command_FakeExec(int client, int args)
{
	if (args < 2)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Execute", arg0);
		return Plugin_Handled;
	}

	char arg[65], ExecCommand[150];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArgString(ExecCommand, sizeof(ExecCommand));
	StripQuotes(ExecCommand);
	
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					0,
					target_name,
					sizeof(target_name),
					tn_is_ml);

					
	Format(arg, sizeof(arg), "%s ", arg); // This nullifies the use of arg any longer.
	ReplaceStringEx(ExecCommand, sizeof(ExecCommand), arg, "");

	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		FakeClientCommand(target, ExecCommand);
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Executed", ExecCommand, target_name);
	LogAction(client, -1, "\"%L\" executed \"%s\" on \"%s\"", client, ExecCommand, target_name);
	
	return Plugin_Handled;
}

public Action Command_BruteExec(int client, int args)
{
	if (args < 2)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Execute", arg0);
		return Plugin_Handled;
	}

	char arg[65], ExecCommand[150];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArgString(ExecCommand, sizeof(ExecCommand));
	StripQuotes(ExecCommand);
	
	char target_name[MAX_TARGET_LENGTH];
	int[] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					0,
					target_name,
					sizeof(target_name),
					tn_is_ml);

					
	Format(arg, sizeof(arg), "%s ", arg); // This nullifies the use of arg any longer.
	ReplaceStringEx(ExecCommand, sizeof(ExecCommand), arg, "");

	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	int bitsToGive = ADMFLAG_ROOT;
	
	if(client != 0)
		bitsToGive = GetUserFlagBits(client);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		int bits = GetUserFlagBits(target);
		
		AdminId OldAdminId = GetUserAdmin(target);
		
		SetUserFlagBits(target, bitsToGive);
		FakeClientCommand(target, ExecCommand);
		SetUserFlagBits(target, bits);
		
		SetUserAdmin(target, OldAdminId); // This is to remove the client's admin id if he was given one when we gave him the flags
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Brutally Executed", ExecCommand, target_name);
	LogAction(client, -1, "\"%L\" BRUTALLY executed \"%s\" on \"%s\"", client, ExecCommand, target_name);
	
	return Plugin_Handled;
}


public Action Command_Money(int client, int args)
{
	if (args < 2)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Amount", arg0);
		return Plugin_Handled;
	}

	char arg[65], arg2[11];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	char target_name[MAX_TARGET_LENGTH];
	int [] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					0,
					target_name,
					sizeof(target_name),
					tn_is_ml);

	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	int money = StringToInt(arg2);
	
	if(money > MAX_POSSIBLE_MONEY)
		money = MAX_POSSIBLE_MONEY;
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		UC_SetClientMoney(target, money);
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Set Money", target_name, money);
	return Plugin_Handled;
}


public Action Command_Team(int client, int args)
{
	if (args < 2)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Team", arg0);
		return Plugin_Handled;
	}

	char arg[65], arg2[11];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	char target_name[MAX_TARGET_LENGTH];
	int [] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					0,
					target_name,
					sizeof(target_name),
					tn_is_ml);

	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	int TeamToSet;
	if(UC_IsStringNumber(arg2))
	{
		TeamToSet = StringToInt(arg2);
		
		if(TeamToSet > CS_TEAM_CT || TeamToSet < CS_TEAM_SPECTATOR)
		{
			char arg0[65];
			GetCmdArg(0, arg0, sizeof(arg0));
			
			UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Team", arg0);
			return Plugin_Handled;
		}
	}	
	else
	{
		if(StrEqual(arg2, "CT", false))
			TeamToSet = CS_TEAM_CT;
			
		else if(StrEqual(arg2, "T", false) || StrEqual(arg2, "Terrorist", false)) // Terrorists included.
			TeamToSet = CS_TEAM_T;
			
		else if(StrEqual(arg2, "Spec", false) || StrEqual(arg2, "Spectator", false))
			TeamToSet = CS_TEAM_SPECTATOR;
			
		else
		{
			char arg0[65];
			GetCmdArg(0, arg0, sizeof(arg0));
			
			UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Team", arg0);
			return Plugin_Handled;
		}
	}
	
	char TeamName[15];
	
	switch(TeamToSet)
	{
		case CS_TEAM_T: TeamName = "Terrorist";
		case CS_TEAM_CT: TeamName = "CT";
		case CS_TEAM_SPECTATOR: TeamName = "Spectator";
	}
	
	int Revive = GetConVarInt(hcv_ucReviveOnTeamChange);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		if(TeamToSet == CS_TEAM_SPECTATOR)
		{
			UC_StripPlayerWeapons(target); // So he doesn't drop his weapon during the team swap.
			
			ForcePlayerSuicide(target);
			
			ChangeClientTeam(target, TeamToSet); // Boy, I wonder which team...
		}	
		else
		{
			if(Revive == 0)
				ForcePlayerSuicide(target);
				
			CS_SwitchTeam(target, TeamToSet);
			
			if(Revive == 1)
				CS_RespawnPlayer(target);
		}
	}
	
			
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Set Team", target_name, TeamName);
	
	return Plugin_Handled;
}


public Action Command_Swap(int client, int args)
{
	if (args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Swap", arg0);
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	
	char target_name[MAX_TARGET_LENGTH];
	int [] target_list = new int[MaxClients+1];
	int target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
					arg,
					client,
					target_list,
					MaxClients,
					0,
					target_name,
					sizeof(target_name),
					tn_is_ml);

	if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	int TeamToSet;
	
	int Revive = GetConVarInt(hcv_ucReviveOnTeamChange);
	
	for(int i=0;i < target_count;i++)
	{
		int target = target_list[i];
		
		TeamToSet = GetOppositeTeam(GetClientTeam(target));
		
		if(TeamToSet == -1)
		{
			int TCount = UC_CountPlayersByTeam(CS_TEAM_T);
			int CTCount = UC_CountPlayersByTeam(CS_TEAM_CT);
			
			if(TCount > CTCount)
				TeamToSet = CS_TEAM_CT
			
			else if(TCount < CTCount)
				TeamToSet = CS_TEAM_T;
				
			else
				TeamToSet = GetRandomInt(0, 1) == 0 ? CS_TEAM_T : CS_TEAM_CT;
		}
		
		if(Revive == 0)
			ForcePlayerSuicide(target);
			
		CS_SwitchTeam(target, TeamToSet);
		
		if(Revive == 1)
			CS_RespawnPlayer(target);
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Player Swap Team", target_name);
	
	return Plugin_Handled;
}


public Action Command_Spec(int client, int args)
{
	if (args == 0)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Spec", arg0);
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	
	FakeClientCommand(client, "sm_team %s spec", arg);
	
	return Plugin_Handled;
}



public Action Command_UCEdit(int client, int args)
{
	UCEdit[client] = !UCEdit[client];
	
	int Chicken = -1;
	if(UCEdit[client])
	{
		while((Chicken = FindEntityByClassname(Chicken, "Chicken")) != -1)
			AcceptEntityInput(Chicken, "Kill");
			
		for(int i=0;i < GetArraySize(ChickenOriginArray);i++)
		{
			char sOrigin[50];
			GetArrayString(ChickenOriginArray, i, sOrigin, sizeof(sOrigin));
			
			SpawnChicken(sOrigin);
		}
	}

	while((Chicken = FindEntityByClassname(Chicken, "Chicken")) != -1)
	{			
		if(UCEdit[client])
		{
			SetEntProp(Chicken, Prop_Send, "m_bShouldGlow", true, true);
			SetEntProp(Chicken, Prop_Send, "m_nGlowStyle", GLOW_WALLHACK);
			SetEntPropFloat(Chicken, Prop_Send, "m_flGlowMaxDist", 10000.0);
			SetEntityMoveType(Chicken, MOVETYPE_NONE);
		}
		else
		{
			SetEntProp(Chicken, Prop_Send, "m_bShouldGlow", false, true);
			SetEntityMoveType(Chicken, MOVETYPE_FLYGRAVITY);
		}
		
		int VariantColor[4] = {255, 255, 255, 255};
			
		SetVariantColor(VariantColor);
		AcceptEntityInput(Chicken, "SetGlowColor");
	}
	if(UCEdit[client])
	{
		UC_PrintToChat(client, "%s%t", UCTag, "Command UCEdit Enabled");
		UC_PrintToChat(client, "%s%t", UCTag, "Command UCEdit Info");
	}	
	else
		UC_PrintToChat(client, "%s%t", UCTag, "Command UCEdit Disabled");
		
	Command_Chicken(client, 0);
	
	return Plugin_Handled;
}

public Action Command_Chicken(int client, int args)
{
	if(dbLocal == INVALID_HANDLE)
		return Plugin_Handled;
		
	Handle hMenu = CreateMenu(ChickenMenu_Handler);
	
	char TempFormat[64];
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Chicken Create");
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Chicken Delete");
	AddMenuItem(hMenu, "", TempFormat);
	
	if(UCEdit[client])
	{
		Format(TempFormat, sizeof(TempFormat), "%t", "Menu Chicken Delete Aim");
		AddMenuItem(hMenu, "", TempFormat);
	}
	SetMenuTitle(hMenu, "%t", "Menu Chicken Title");
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}


public int ChickenMenu_Handler(Handle hMenu, MenuAction action, int client, int item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
		
	else if(action == MenuAction_Select)
	{
		switch(item)
		{
			case 0:
			{
				CreateChickenSpawn(client);		
				
				Command_Chicken(client, 0);
			}
			
			case 1:
			{
				SetupDeleteChickenSpawnMenu(client);
			}
			
			case 2:
			{
				Command_Chicken(client, 0);
				
				int Chicken = GetClientAimTarget(client, false);
				
				if(Chicken == -1)
				{
					UC_PrintToChat(client, "%s%t", UCTag, "Command Chicken Not Found");
					return;
				}
				
				char Classname[50];
				GetEdictClassname(Chicken, Classname, sizeof(Classname));
				
				if(!StrEqual(Classname, "Chicken", false))
				{
					UC_PrintToChat(client, "%s%t", UCTag, "Command Chicken Not Found");
					return;
				}
				
				char TargetName[100];
				GetEntPropString(Chicken, Prop_Data, "m_iName", TargetName, sizeof(TargetName));
				
				if(StrContains(TargetName, "UsefulCommands_Chickens") == -1)
				{
					UC_PrintToChat(client, "%s%t", UCTag, "Command Chicken Not Found");
					return;
				}
				
				ReplaceStringEx(TargetName, sizeof(TargetName), "UsefulCommands_Chickens ", "");
				
				char sQuery[256];
				
				UC_PrintToChat(client, TargetName);
				dbLocal.Format(sQuery, sizeof(sQuery), "DELETE FROM UsefulCommands_Chickens WHERE ChickenOrigin = '%s' AND ChickenMap = '%s'", TargetName, MapName);
				dbLocal.Query(SQLCB_Error, sQuery);
				
				int Pos = FindStringInArray(ChickenOriginArray, TargetName);
				if(Pos != -1)
					RemoveFromArray(ChickenOriginArray, Pos);
					
				AcceptEntityInput(Chicken, "Kill");
			}
		}
	}
}


void SetupDeleteChickenSpawnMenu(int client)
{
	char sQuery[256];
	dbLocal.Format(sQuery, sizeof(sQuery), "SELECT * FROM UsefulCommands_Chickens WHERE ChickenMap = \"%s\" ORDER BY ChickenCreateDate DESC", MapName);
	dbLocal.Query(SQLCB_DeleteChickenSpawnMenu, sQuery, GetClientUserId(client));
}
public void SQLCB_DeleteChickenSpawnMenu(Handle db, Handle hndl, const char[] sError, int data)
{
	if(hndl == null)
		ThrowError(sError);
	
	int client = GetClientOfUserId(data);
	
	if(client == 0)
		return;
	
	else if(SQL_GetRowCount(hndl) == 0)
	{
		UC_PrintToChat(client, "%s%t", UCTag, "Command Chicken No Spawners");
		return;
	}
	
	Handle hMenu = CreateMenu(DeleteChickenSpawnMenu_Handler);
	
	while(SQL_FetchRow(hndl))
	{
		char sOrigin[50];
		SQL_FetchString(hndl, 0, sOrigin, sizeof(sOrigin));
		
		AddMenuItem(hMenu, "", sOrigin);
	}
	
	SetMenuTitle(hMenu, "%t", "Menu Chicken Delete Info");
	
	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}


public int DeleteChickenSpawnMenu_Handler(Handle hMenu, MenuAction action, int client, int item)
{
	if(action == MenuAction_DrawItem)
	{
		return ITEMDRAW_DEFAULT;
	}
	else if(action == MenuAction_Cancel && item == MenuCancel_ExitBack)
	{
		Command_Chicken(client, 0);
		return ITEMDRAW_DEFAULT;
	}
	if(action == MenuAction_End)
		CloseHandle(hMenu);
		
	else if(action == MenuAction_Select)
	{	
		char sOrigin[50], sIgnore[1];
		int iIgnore;
		
		GetMenuItem(hMenu, item, sIgnore, sizeof(sIgnore), iIgnore, sOrigin, sizeof(sOrigin));
		
		CreateConfirmDeleteMenu(client, sOrigin);
	}
	
	return ITEMDRAW_DEFAULT;
}

void CreateConfirmDeleteMenu(int client, char[] sOrigin)
{
	Handle hMenu = CreateMenu(ConfirmDeleteChickenSpawnMenu_Handler);
	
	char TempFormat[128];
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Yes");
	AddMenuItem(hMenu, sOrigin, TempFormat);

	Format(TempFormat, sizeof(TempFormat), "%t", "Menu No");
	AddMenuItem(hMenu, sOrigin, TempFormat);
	
	SetMenuTitle(hMenu, "%t", "Menu Chicken Delete Confirm", sOrigin);

	SetMenuExitBackButton(hMenu, true);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	
	if(UCEdit[client])
	{	
		float Origin[3];
		GetStringVector(sOrigin, Origin);
		TeleportEntity(client, Origin, NULL_VECTOR, NULL_VECTOR);
	}
}
public int ConfirmDeleteChickenSpawnMenu_Handler(Handle hMenu, MenuAction action, int client, int item)
{
	if(action == MenuAction_DrawItem)
	{
		return ITEMDRAW_DEFAULT;
	}
	else if(action == MenuAction_Cancel && item == MenuCancel_ExitBack)
	{
		SetupDeleteChickenSpawnMenu(client);
		return ITEMDRAW_DEFAULT;
	}
	if(action == MenuAction_End)
		CloseHandle(hMenu);
		
	else if(action == MenuAction_Select)
	{
		if(item == 0)
		{
			char sOrigin[50], sIgnore[1];
			int iIgnore;
			GetMenuItem(hMenu, item, sOrigin, sizeof(sOrigin), iIgnore, sIgnore, sizeof(sIgnore));
			
			char sQuery[256];
			dbLocal.Format(sQuery, sizeof(sQuery), "DELETE FROM UsefulCommands_Chickens WHERE ChickenOrigin = \"%s\" AND ChickenMap = \"%s\"", sOrigin, MapName);
			dbLocal.Query(SQLCB_ChickenSpawnDeleted, sQuery, GetClientUserId(client));
		}
		else
			SetupDeleteChickenSpawnMenu(client);
	}
	
	return ITEMDRAW_DEFAULT;
}


public void SQLCB_ChickenSpawnDeleted(Handle db, Handle hndl, const char[] sError, int data)
{
	if(hndl == null)
		ThrowError(sError);
		
	int client = GetClientOfUserId(data);
	
	if(client != 0)
		UC_PrintToChat(client, "%s%t", UCTag, "Command Chicken Deleted");
		
	LoadChickenSpawns();
}


void CreateChickenSpawn(int client)
{
	char sQuery[256], sOrigin[50];
	float Origin[3];

	
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
	
	Origin[2] += 15.0;
	Format(sOrigin, sizeof(sOrigin), "%.4f %.4f %.4f", Origin[0], Origin[1], Origin[2]);
	dbLocal.Format(sQuery, sizeof(sQuery), "INSERT OR IGNORE INTO UsefulCommands_Chickens (ChickenOrigin, ChickenMap, ChickenCreateDate) VALUES (\"%s\", \"%s\", %i)", sOrigin, MapName, GetTime());
	
	Handle DP = CreateDataPack();
	
	WritePackCell(DP, GetClientUserId(client));
	
	WritePackFloat(DP, Origin[0]);
	WritePackFloat(DP, Origin[1]);
	WritePackFloat(DP, Origin[2]);
	
	dbLocal.Query(SQLCB_ChickenSpawnCreated, sQuery, DP);
}

public void SQLCB_ChickenSpawnCreated(Handle db, Handle hndl, const char[] sError, Handle DP)
{
	ResetPack(DP);
	
	int client = GetClientOfUserId(ReadPackCell(DP));
	
	float Origin[3];
	for(int i=0;i < 3;i++)
		Origin[i] = ReadPackFloat(DP);
		
	CloseHandle(DP);
	
	if(hndl == null)
		ThrowError(sError);
	
	else if(client != 0)
		UC_PrintToChat(client, "%s%t", UCTag, "Command Chicken Created");
	
	char sOrigin[50];
	Format(sOrigin, sizeof(sOrigin), "%.4f %.4f %.4f", Origin[0], Origin[1], Origin[2]);
	CreateChickenSpawner(sOrigin);
	
}

void CreateChickenSpawner(char[] sOrigin)
{
	PushArrayString(ChickenOriginArray, sOrigin);
}

public Action Command_Last(int client, int args)
{
	if(dbLocal == INVALID_HANDLE || client == 0)
		return Plugin_Handled;
	
	char AuthStr[64];
	
	if(args > 0)
		GetCmdArgString(AuthStr, sizeof(AuthStr));
	
	QueryLastConnected(client, 0, AuthStr);
	
	return Plugin_Handled;
}

public void QueryLastConnected(int client, int ItemPos, char[] AuthStr)
{
	Handle DP = CreateDataPack();
	
	WritePackCell(DP, GetClientUserId(client));
	WritePackCell(DP, ItemPos);
	WritePackString(DP, AuthStr);
	
	if(AuthStr[0] == EOS)
		dbLocal.Query(SQLCB_LastConnected, "SELECT * FROM UsefulCommands_LastPlayers ORDER BY LastConnect DESC", DP); 
		
	else
	{
		char sQuery[512];
		dbLocal.Format(sQuery, sizeof(sQuery), "SELECT * FROM UsefulCommands_LastPlayers WHERE Name LIKE '%%%s%%' OR AuthId LIKE '%%%s%%' OR IPAddress LIKE '%%%s%%' ORDER BY LastConnect DESC", AuthStr, AuthStr, AuthStr); 
		
		dbLocal.Query(SQLCB_LastConnected, sQuery, DP); 
	}
}

public void SQLCB_LastConnected(Handle db, Handle hndl, const char[] sError, Handle DP)
{
	ResetPack(DP);
	
	int UserId = ReadPackCell(DP);
	int ItemPos = ReadPackCell(DP);
	
	char AuthStr[64];
	
	ReadPackString(DP, AuthStr, sizeof(AuthStr));
	
	CloseHandle(DP);
	
	if(hndl == null)
		ThrowError(sError);
    
	int client = GetClientOfUserId(UserId);

	if(client != 0)
	{
		
		char TempFormat[256], AuthId[32], IPAddress[32], Name[64];
		
		Handle hMenu = CreateMenu(LastConnected_MenuHandler);
		
		LastAuthStr[client] = AuthStr;
	
		while(SQL_FetchRow(hndl))
		{
			SQL_FetchString(hndl, 0, AuthId, sizeof(AuthId));
			SQL_FetchString(hndl, 2, IPAddress, sizeof(IPAddress));
			SQL_FetchString(hndl, 3, Name, sizeof(Name));
			
			int LastConnect = SQL_FetchInt(hndl, 1);
				
			Format(TempFormat, sizeof(TempFormat), "\"%s\" \"%s\" \"%i\"", AuthId, IPAddress, LastConnect);
			AddMenuItem(hMenu, TempFormat, Name);
		}
		
		if(AuthStr[0] == EOS)
			SetMenuTitle(hMenu, "Showing all players that have last connected in the past");
			
		else
			SetMenuTitle(hMenu, "Showing all players that have last connected in the past matching:\n%s", AuthStr);
			
		DisplayMenuAtItem(hMenu, client, ItemPos, MENU_TIME_FOREVER);
	
	}
}


public int LastConnected_MenuHandler(Handle hMenu, MenuAction action, int client, int item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	else if(action == MenuAction_Select)
	{
		char AuthId[32], IPAddress[32], Name[64], Info[150], Date[64];
		
		GetMenuItem(hMenu, item, Info, sizeof(Info), _, Name, sizeof(Name));
		
		int len = BreakString(Info, AuthId, sizeof(AuthId));
		int len2 = BreakString(Info[len], IPAddress, sizeof(IPAddress));
		
		BreakString(Info[len+len2], Date, sizeof(Date));
		
		int LastConnect = StringToInt(Date);

		if(!CheckCommandAccess(client, "sm_uc_last_showip", ADMFLAG_ROOT))
		{
			Format(IPAddress, sizeof(IPAddress), "%t", "No Admin Access");
		}	
		FormatTime(Date, sizeof(Date), "%Y/%m/%d - %H:%M:%S", LastConnect);
		
		UC_PrintToChat(client, "%s%t", UCTag, "Command Last Name SteamID", Name, AuthId);
		UC_PrintToChat(client, "%t", "Command Last IP Last Disconnect", IPAddress, Date); // Rarely but still, I won't use the UC tag to show continuity. 
		PrintToConsole(client, "\n%t", "Command Last Console Full", Name, AuthId, IPAddress, Date);
		
		QueryLastConnected(client, GetMenuSelectionPosition(), LastAuthStr[client]);
	}
}

public Action Command_Hug(int client, int args)
{
	if(!IsPlayerAlive(client))
	{
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Error Alive");
		return Plugin_Handled;
	}
	

	float Origin[3], WinningDistance = -1.0;
	int ClosestRagdoll = -1, WinningPlayer = -1;
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
	
	if(isCSGO())
	{
		for(int i=1;i <= MaxClients;i++)
		{
			if(!IsClientInGame(i))
				continue;
				
			else if(IsPlayerAlive(i))
				continue;
			
			else if(isHugged[i])
				continue;
				
			int Ragdoll = GetEntPropEnt(i, Prop_Send, "m_hRagdoll");
			
			if(Ragdoll == -1)
				continue;
				
			float ragOrigin[3];
			GetEntPropVector(Ragdoll, Prop_Data, "m_vecOrigin", ragOrigin);
			
			float Distance = GetVectorDistance(ragOrigin, Origin)
			if(Distance <= MAX_HUG_DISTANCE)
			{
				if(Distance < WinningDistance || WinningDistance == -1.0)
				{
					WinningDistance = Distance;
					ClosestRagdoll = Ragdoll;
					WinningPlayer = i;
				}
			}
		}
	}
	else // if(!isCSGO())
	{
		int Ragdoll = -1;
		
		while((Ragdoll = FindEntityByClassname(Ragdoll, "cs_ragdoll")) != -1)
		{
			int i = GetEntPropEnt(Ragdoll, Prop_Send, "m_hOwnerEntity");
			
			if(i == -1 || IsPlayerAlive(i)) // IDK lol.
				break;
				
			float ragOrigin[3];
			GetEntPropVector(Ragdoll, Prop_Data, "m_vecOrigin", ragOrigin);
			
			float Distance = GetVectorDistance(ragOrigin, Origin)
			if(Distance <= MAX_HUG_DISTANCE)
			{
				if(Distance < WinningDistance || WinningDistance == -1.0)
				{
					WinningDistance = Distance;
					ClosestRagdoll = Ragdoll;
					WinningPlayer = i;
				}
			}
		}
	}
	
	if(ClosestRagdoll == -1)
	{
		UC_PrintToChat(client, "%s%t", UCTag, "Command Hug Nobody Found");
		return Plugin_Handled;
	}
	
	UC_PrintToChatAll("%s%t", UCTag, "Player Hugged", client, WinningPlayer);
	isHugged[WinningPlayer] = true;
	return Plugin_Handled;
}

public Action Command_XYZ(int client, int args)
{
	float Origin[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
	
	UC_ReplyToCommand(client, "X, Y, Z = %.3f, %.3f, %3f", Origin[0], Origin[1], Origin[2]);
	return Plugin_Handled;
}

// Stolen from official SM plugin basecommands.sp.

public Action Command_SilentCvar(int client, int args)
{
	if(args < 1)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Silent Cvar", arg0);
		return Plugin_Handled;
	}

	char cvarname[64];
	GetCmdArg(1, cvarname, sizeof(cvarname));
	
	ConVar hndl = FindConVar(cvarname);
	
	if(hndl == null)
	{
		UC_ReplyToCommand(client, "%s%t", UCTag, "Unable to find cvar", cvarname);
		return Plugin_Handled;
	}

	char value[255];
	
	if(args < 2)
	{
		hndl.GetString(value, sizeof(value));

		UC_ReplyToCommand(client, "%s%t", UCTag, "Value of cvar", cvarname, value);
		return Plugin_Handled;
	}

	GetCmdArg(2, value, sizeof(value));
	
	// The server passes the values of these directly into ServerCommand, following exec. Sanitize.
	if(StrEqual(cvarname, "servercfgfile", false) || StrEqual(cvarname, "lservercfgfile", false))
	{
		int pos = StrContains(value, ";", true);
		if(pos != -1)
		{
			value[pos] = '\0';
		}
	}
	
	UC_ReplyToCommand(client, "%s%t", UCTag, "Cvar changed", cvarname, value);

	LogAction(client, -1, "\"%L\" silently changed cvar (cvar \"%s\") (value \"%s\")", client, cvarname, value);

	int flags = hndl.Flags;
	
	hndl.Flags = (flags & ~FCVAR_NOTIFY);
	
	hndl.SetString(value, true);
	
	hndl.Flags = flags;

	return Plugin_Handled;
}

public Action Command_AdminCookies(int client, int args)
{
	if (args < 3)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Admin Cookies #1", arg0);
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Admin Cookies #2", arg0);
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Admin Cookies #3", arg0);
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Printing Cookie List");
		
		/* Show list of cookies */
		Handle iter = GetCookieIterator();
		
		char name[30];
		name[0] = '\0';
		char description[255];
		description[0] = '\0';
		
		PrintToConsole(client, "%t:", "Cookie List");
		
		CookieAccess access;
		
		int count = 1;
		
		while (ReadCookieIterator(iter, 
								name, 
								sizeof(name),
								access, 
								description, 
								sizeof(description)) != false)
		{
			char AccessName[50];
			switch(access)
			{
				case CookieAccess_Public: AccessName = "Public Cookie";
				case CookieAccess_Protected: AccessName = "Protected Cookie";
				case CookieAccess_Private: AccessName = "Hidden Cookie";
			}
			
			PrintToConsole(client, "[%03d] %s - %s - %s", count++, name, description, AccessName);
		}
		
		delete iter;		
		return Plugin_Handled;
	}
	
	char CookieName[33]; // I think cookies are 32 characters long.
	GetCmdArg(1, CookieName, sizeof(CookieName));
	
	Handle hCookie = FindClientCookie(CookieName);
	
	if (hCookie == null)
	{
		UC_ReplyToCommand(client, "%s%t", UCTag, "Cookie not Found", CookieName);
		return Plugin_Handled;
	}
	
	char CommandType[50];
	
	GetCmdArg(2, CommandType, sizeof(CommandType));

	if(StrEqual(CommandType, "set", false))
	{
		char TargetArg[50];
		GetCmdArg(3, TargetArg, sizeof(TargetArg));
		
		char target_name[MAX_TARGET_LENGTH];
		int [] target_list = new int[MaxClients+1];
		int target_count;
		bool tn_is_ml;
		
		target_count = ProcessTargetString(
						TargetArg,
						client,
						target_list,
						MaxClients,
						0,
						target_name,
						sizeof(target_name),
						tn_is_ml);

		if(target_count <= COMMAND_TARGET_NONE) 	// If we don't have dead players
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		
		char Value[256];
		char[] Dummy_Value = new char[sizeof(Value)];
		
		if(args > 3)
		{
			GetCmdArgString(Value, sizeof(Value));
			
			int index;
			for(int i=1;i < 4;i++) // 4 = Argument number to start from that indicates the value to choose.
			{
				index = BreakString(Value, Dummy_Value, sizeof(Value));
				
				Format(Value, sizeof(Value), Value[index]);
			}
		}
		
		for(int i=0;i < target_count;i++)
		{
			int target = target_list[i];
			
			if(args > 3)
				SetClientCookie(target, hCookie, Value);
			
			else
			{
				char Name[64]; // I don't want to use %N to prevent multiple translations.
				GetClientName(i, Name, sizeof(Name));
				
				GetClientCookie(target, hCookie, Value, sizeof(Value));
				
				UC_ReplyToCommand(client, "%s%t", UCTag, "Command Admin Cookies Get Value", CookieName, Name, Value);
			}
		}
		
		if(args > 3)
		{
			UC_ReplyToCommand(client, "%s%t", UCTag, "Command Admin Cookies Set Value", CookieName, target_name, Value);
			LogAction(client, -1, "\"%L\" set cookie value \"%s\" for %s to \"%s\"", client, CookieName, target_name, Value);
		}
	}
	else if(StrEqual(CommandType, "offlineset", false))
	{
		char AuthIdArg[64];
		GetCmdArg(3, AuthIdArg, sizeof(AuthIdArg));
		
		if(args > 3)
		{
			char Value[256];
			char[] Dummy_Value = new char[sizeof(Value)];
			
			GetCmdArgString(Value, sizeof(Value));
			
			int index;
			for(int i=1;i < 4;i++) // 4 = Argument number to start from that indicates the value to choose.
			{
				index = BreakString(Value, Dummy_Value, sizeof(Value));
					
				Format(Value, sizeof(Value), Value[index]);
			}
			
			int Target = UC_FindTargetByAuthId(AuthIdArg);
			
			if(Target != 0 && AreClientCookiesCached(Target))
				SetClientCookie(Target, hCookie, Value);
			
			else
				SetAuthIdCookie(AuthIdArg, hCookie, Value);
			
			UC_ReplyToCommand(client, "%s%t", UCTag, "Command Admin Cookies Set Value", CookieName, AuthIdArg, Value);
			LogAction(client, -1, "\"%L\" set cookie value \"%s\" for %s to \"%s\"", client, CookieName, AuthIdArg, Value);
		}
		else
		{
			UC_GetAuthIdCookie(AuthIdArg, CookieName, client, GetCmdReplySource());
		}
	}
	else if(StrEqual(CommandType, "reset", false))
	{
		char Value[256];
		char[] Dummy_Value = new char[sizeof(Value)];
		
		GetCmdArgString(Value, sizeof(Value));
		
		int index;
		for(int i=1;i < 3;i++) // 3 = Argument number to start from that indicates the value to choose.
		{
			index = BreakString(Value, Dummy_Value, sizeof(Value));
			
			Format(Value, sizeof(Value), Value[index]);
		}
		
		UC_ResetCookieToValue(CookieName, Value, client, GetCmdReplySource());
	}
	else
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Admin Cookies #1", arg0);
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Admin Cookies #2", arg0);
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Admin Cookies #3", arg0);
	}
	delete hCookie;
	
	return Plugin_Handled;
}

public Action Command_FindCvar(int client, int args)
{
	if(args == 0)
	{
		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Usage Find Cvar", arg0);
		return Plugin_Handled;
	}
	
	char buffer[128], description[512];
	bool isCommand;
	int flags;
	Handle iterator = FindFirstConCommand(buffer, sizeof(buffer), isCommand, flags, description, sizeof(description));
	
	if(iterator == INVALID_HANDLE)
	{
		UC_ReplyToCommand(client, "%s%t", "Could not find commands");
		return Plugin_Handled;
	}
	
	char CvarToSearch[256]; // You can also search decriptions, it must be long for safety measures.
	GetCmdArgString(CvarToSearch, sizeof(CvarToSearch));
	
	char CmdFlags[128];
	int count;
	
	
	do
	{
		if(count >= 50)
			break;
			
		GetCommandFlagString(flags, CmdFlags, sizeof(CmdFlags));
		
		Handle convar;
		
		char CvarValue[256];
		
		if(!isCommand)
		{
			convar = FindConVar(buffer);
			
			GetConVarString(convar, CvarValue, sizeof(CvarValue));
		}
		if(StrContains(buffer, CvarToSearch, false) == -1 && StrContains(description, CvarToSearch, false) == -1 && StrContains(CmdFlags, CvarToSearch, false) == -1 && (isCommand || StrContains(CvarValue, CvarToSearch, false) == -1))
			continue;
		
		if(description[0] != EOS && description[0] != '-' && description[1] != ' ')
			Format(description, sizeof(description), "- %s", description);
			
		if(isCommand)
			PrintToConsole(client, "\"%s\"  %s %s", buffer, CmdFlags, description);
			
		else
		{	
			//char CvarValue[256]; // This appears upper than here.
			char CvarDefault[256];
			char OutputDefault[256];
			char OutputBounds[256];
			float CvarUpper, CvarLower;
			
			GetConVarDefault(convar, CvarDefault, sizeof(CvarDefault));
			
			if(!StrEqual(CvarValue, CvarDefault, true))
				Format(OutputDefault, sizeof(OutputDefault), "( def. \"%s\" ) ", CvarDefault);
				
			if(GetConVarBounds(convar, ConVarBound_Lower, CvarLower))
				Format(OutputBounds, sizeof(OutputBounds), "min. %f ", CvarLower);
				
			if(GetConVarBounds(convar, ConVarBound_Upper, CvarUpper))
				Format(OutputBounds, sizeof(OutputBounds), "%s max. %f ", OutputBounds, CvarUpper);
						
			PrintToConsole(client, "\"%s\" = \"%s\" %s%s%s    %s", buffer, CvarValue, OutputDefault, OutputBounds, CmdFlags, description);
			
			count++;
		}
		//PrintToConsole(client, Output);
	}
	while(FindNextConCommand(iterator, buffer, sizeof(buffer), isCommand, flags, description, sizeof(description)))
	
	CloseHandle(iterator);
	
	UC_ReplyToCommand(client, "%s%t", UCTag, "Check Console");
	return Plugin_Handled;
}

public Action Command_ClearChat(int client, int args)
{	
	for (int i = 0; i < 300;i++)
	{
		PrintToChatAll(" \x01\x0B \x0B");
	}
	
	UC_ShowActivity2(client, UCTag, "%t", "Chat Cleared");
	
	return Plugin_Handled;
}


public Action Command_CustomAce(int client, int args)
{
	
	char Args[100];
	GetCmdArgString(Args, sizeof(Args));
	StripQuotes(Args);
	
	if(Args[0] == EOS)
	{
		SetClientAceFunFact(client, "#funfact_ace");

		char arg0[65];
		GetCmdArg(0, arg0, sizeof(arg0));
		
		UC_PrintToChat(client, "%s%t", UCTag, "Command Usage Custom Ace", arg0);
		UC_PrintToChat(client, "%s%t", UCTag, "Command Ace Message Set To Default");
		return Plugin_Handled;		
	}	
	
	SetClientAceFunFact(client, Args);

	UC_PrintToChat(client, "%s%t", UCTag, "Command Ace Message Set", Args);
	UC_PrintToChat(client, "%s%t", UCTag, "Command Ace Message Hint");
	
	return Plugin_Handled;
}


public Action Command_WepStats(int client, int args)
{
	if(args == 0)
	{
		Handle hMenu = CreateMenu(WepStatsMenu_Handler);
		
		CSWeaponID i;
		char WeaponID[20], Alias[20];
		for(i = CSWeapon_NONE;i < CSWeapon_MAX_WEAPONS_NO_KNIFES;i++)
		{
			if(!CS_IsValidWeaponID(i))
				continue;
				
			if(!CS_WeaponIDToAlias(i, Alias, sizeof(Alias)))
				continue;
			
			bool Ignore = false;
			for(int a=0;a < sizeof(wepStatsIgnore);a++)
			{
				if(i == wepStatsIgnore[a])
				{
					a = sizeof(wepStatsIgnore);
					Ignore = true;
				}
			}
			
			if(Ignore)
				continue;
				
			IntToString(view_as<int>(i), WeaponID, sizeof(WeaponID));
			
			UC_StringToUpper(Alias);
			
			AddMenuItem(hMenu, WeaponID, Alias);	
		}

		SetMenuTitle(hMenu, "%t", "Menu Wepstats Title");
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
	else
	{
		char Arg1[32];
		GetCmdArg(1, Arg1, sizeof(Arg1));
		
		ReplaceStringEx(Arg1, sizeof(Arg1), "weapon_", "");
		
		CSWeaponID WeaponID = CS_AliasToWeaponID(Arg1);
		if(WeaponID == CSWeapon_NONE)
		{
			UC_ReplyToCommand(client, "%s%t", UCTag, "Command Give Invalid Weapon", Arg1); // Command Give tells "Weapon \"%s\" doesn't exist"
			return Plugin_Handled;
		}
		ShowSelectedWepStatMenu(client, WeaponID);
	}	
	return Plugin_Handled;
}


public int WepStatsMenu_Handler(Handle hMenu, MenuAction action, int client, int item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	else if(action == MenuAction_Select)
	{
		CSWeaponID i;
		
		int iIgnore;
		char WeaponName[64], WeaponID[64];
		
		GetMenuItem(hMenu, item, WeaponID, sizeof(WeaponID), iIgnore, WeaponName, sizeof(WeaponName));
		
		i = view_as<CSWeaponID>(StringToInt(WeaponID));
		
		ShowSelectedWepStatMenu(client, i);
	}
}

void ShowSelectedWepStatMenu(int client, CSWeaponID i)
{
	Handle hMenu = CreateMenu(WepStatsSelectedMenu_Handler);
	
	char TempFormat[150];
	
	char WeaponID[20];
	
	IntToString(view_as<int>(i), WeaponID, sizeof(WeaponID));
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Base Damage", wepStatsList[i].wepStatsDamage);
	AddMenuItem(hMenu, WeaponID, TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Rate of Fire", wepStatsList[i].wepStatsFireRate);
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Armor Penetration", wepStatsList[i].wepStatsArmorPenetration);
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Kill Award", wepStatsList[i].wepStatsKillAward);
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Wallbang Power", wepStatsList[i].wepStatsWallPenetration, wepStatsList[CSWeapon_AWP].wepStatsWallPenetration);
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Damage Dropoff", wepStatsList[i].wepStatsDamageDropoff);
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Max Range", wepStatsList[i].wepStatsMaxDamageRange);
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Pellets per Shot", wepStatsList[i].wepStatsPalletsPerShot);
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Damage per Pellet", wepStatsList[i].wepStatsDamagePerPallet);
	AddMenuItem(hMenu, "", TempFormat);
	
	char isFullAuto[15];
	Format(isFullAuto, sizeof(isFullAuto), "%t", wepStatsList[i].wepStatsIsAutomatic ? "Menu Yes" : "Menu No");
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Fully Automatic", isFullAuto);
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Damage per Second Unarmored", wepStatsList[i].wepStatsDamagePerSecondNoArmor);
	AddMenuItem(hMenu, "", TempFormat);

	Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats Damage per Second Armored", wepStatsList[i].wepStatsDamagePerSecondArmor);
	AddMenuItem(hMenu, "", TempFormat);
	
	if(wepStatsList[i].wepStatsTapDistanceNoArmor == 0)
	{
		Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats One Tap Distance Unarmored Impossible");
		AddMenuItem(hMenu, "", TempFormat);
	}
	else
	{
		Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats One Tap Distance Unarmored", wepStatsList[i].wepStatsTapDistanceNoArmor);
		AddMenuItem(hMenu, "", TempFormat);
	}
	
	if(wepStatsList[i].wepStatsTapDistanceArmor == 0)
	{
		Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats One Tap Distance Armored Impossible");
		AddMenuItem(hMenu, "", TempFormat);
	}
	else
	{
		Format(TempFormat, sizeof(TempFormat), "%t", "Menu Wepstats One Tap Distance Armored", wepStatsList[i].wepStatsTapDistanceArmor);
		AddMenuItem(hMenu, "", TempFormat);
	}
	
	
	
	SetMenuExitBackButton(hMenu, true);
	SetMenuExitButton(hMenu, true);
	
	CS_WeaponIDToAlias(i, WeaponID, sizeof(WeaponID)); // We already did everything needed for WeaponID, allowed to re-use it.
	
	UC_StringToUpper(WeaponID);
	SetMenuTitle(hMenu, "%s \n \n %t", WeaponID, "Menu Wepstats Shotgun Note");
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int WepStatsSelectedMenu_Handler(Handle hMenu, MenuAction action, int client, int item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	else if(action == MenuAction_Cancel && item == MenuCancel_ExitBack)
	{
		Command_WepStats(client, 0);
	}
	else if(action == MenuAction_Select)
	{
		CSWeaponID i;
		
		char WeaponName[64], WeaponID[64];
		int iIgnore;
		
		GetMenuItem(hMenu, 0, WeaponID, sizeof(WeaponID), iIgnore, WeaponName, sizeof(WeaponName));
		
		i = view_as<CSWeaponID>(StringToInt(WeaponID));
		
		ShowSelectedWepStatMenu(client, i);
	}
}

public Action Command_UC(int client, int args)
{
	ShowUCMenu(client, 0);
	
	return Plugin_Handled;
}

void ShowUCMenu(int client, int item)
{

	Handle hMenu = CreateMenu(UCMenu_Handler);
	
	Handle Trie_Snapshot = CreateTrieSnapshot(Trie_UCCommands);
	
	int size = TrieSnapshotLength(Trie_Snapshot);
	
	char buffer[256];

	if(isCSGO())
		AddMenuItem(hMenu, "sm_settings", "sm_settings");
	
	char Info[300];
	
	int len;
	
	int adminflags;
	char sAdminFlags[11];
			
	for(int i=0;i < size;i++)
	{
		GetTrieSnapshotKey(Trie_Snapshot, i, buffer, sizeof(buffer));
		
		
		GetTrieString(Trie_UCCommands, buffer, Info, sizeof(Info));
		
		len = BreakString(Info, sAdminFlags, sizeof(sAdminFlags));
		
		adminflags = StringToInt(sAdminFlags);
		
		if(len == -1)
			Info[0] = EOS;
			
		else
			Format(Info, sizeof(Info), Info[len]);
			
		if(CheckCommandAccess(client, "sm_null_command", adminflags, true))
			AddMenuItem(hMenu, Info, buffer);
	}

	CloseHandle(Trie_Snapshot);
	DisplayMenuAtItem(hMenu, client, item, MENU_TIME_FOREVER);
	
	
}

public int UCMenu_Handler(Handle hMenu, MenuAction action, int client, int item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
		
	else if(action == MenuAction_Select)
	{
		char Info[256], Command[50];
		
		GetMenuItem(hMenu, item, Info, sizeof(Info), _, Command, sizeof(Command));
		
		StripQuotes(Info);
		PrintToChat(client, "\"%s\" - %s", Command, Info);
		PrintToConsole(client, "\"%s\" - %s", Command, Info);
		
		ShowUCMenu(client, GetMenuSelectionPosition());
	}
	return 0;
}

stock void UC_StripPlayerWeapons(int client)
{
	for(int i=0;i <= 5;i++)
	{
		int weapon = GetPlayerWeaponSlot(client, i);
		
		if(weapon != -1)
		{
			RemovePlayerItem(client, weapon);
			i--; // This is to strip all nades, and zeus & knife
		}
	}
}

stock void UC_SetClientRocket(int client, bool rocket)
{
	if(rocket)
	{
		TIMER_LIFTOFF[client] = CreateTimer(1.5, RocketLiftoff, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		bool hadRocket = false;
		if(TIMER_LIFTOFF[client] != INVALID_HANDLE)
		{
			CloseHandle(TIMER_LIFTOFF[client]);
			TIMER_LIFTOFF[client] = INVALID_HANDLE;
			hadRocket = true;
		}
		if(TIMER_ROCKETCHECK[client] != INVALID_HANDLE)
		{
			CloseHandle(TIMER_ROCKETCHECK[client]);
			TIMER_ROCKETCHECK[client] = INVALID_HANDLE;
			hadRocket = true;
		}
		
		if(hadRocket)
		{
			SetEntityGravity(client, 1.0);
		}
	}
}

public Action RocketLiftoff(Handle hTimer, int UserId)
{
	int client = GetClientOfUserId(UserId);
	
	if(client == 0)
		return;

	TIMER_LIFTOFF[client] = INVALID_HANDLE;
	
	float Origin[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
	
	LastHeight[client] = Origin[2];
	SetEntityGravity(client, -0.5);
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 285.0}));
	SetEntityFlags(client, GetEntityFlags(client) & ~FL_ONGROUND);
	
	
	TIMER_ROCKETCHECK[client] = CreateTimer(0.2, RocketHeightCheck, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

}

public Action RocketHeightCheck(Handle hTimer, int UserId)
{
	int client = GetClientOfUserId(UserId);
	
	if(client == 0)
		return Plugin_Stop;
		
	float Origin[3];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);

	if(Origin[2] == LastHeight[client]) // KABOOM!!! We reached the ceiling!!!
	{
		TIMER_ROCKETCHECK[client] = INVALID_HANDLE;
		
		SetEntityGravity(client, 1.0);

		ForcePlayerSuicide(client);
		
		return Plugin_Stop;
	}
	LastHeight[client] = Origin[2];
	
	SetEntityGravity(client, -0.5);
	
	return Plugin_Continue;
}

stock void UC_SetClientCurse(int client, bool curse)
{
	g_bCursed[client] = curse;
}


stock void UC_SetClientGodmode(int client, bool godmode)
{
	if(godmode)
		SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);
		
	else
		SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
}

stock bool UC_GetClientGodmode(int client)
{
	if(GetEntProp(client, Prop_Data, "m_takedamage", 1) == 0)
		return true;
		
	return false;
}

// This function is perfect but I need to conduct tests to ensure no bugs occur.
stock bool UC_GetAimPositionBySize(int client, int target, float outputOrigin[3])
{
	float BrokenOrigin[3];
	float vecMin[3], vecMax[3], eyeOrigin[3], eyeAngles[3], Result[3], FakeOrigin[3], clientOrigin[3];
    
	GetClientMins(target, vecMin);
	GetClientMaxs(target, vecMax);
	
	GetEntPropVector(target, Prop_Data, "m_vecOrigin", BrokenOrigin);
    
	GetClientEyePosition(client, eyeOrigin);
	GetClientEyeAngles(client, eyeAngles);
	
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", clientOrigin);
	
	TR_TraceRayFilter(eyeOrigin, eyeAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceRayDontHitPlayers);
	
	TR_GetEndPosition(FakeOrigin);
	
	Result = FakeOrigin;
	
	if(TR_PointOutsideWorld(Result))
		return false;
		
	float fwd[3];	

	GetAngleVectors(eyeAngles, fwd, NULL_VECTOR, NULL_VECTOR);
	
	NegateVector(fwd);
	
	float clientHeight = eyeOrigin[2] - clientOrigin[2];
	float OffsetFix = eyeOrigin[2] - Result[2];
	
	if(OffsetFix < 0.0)
		OffsetFix = 0.0;
		
	else if(OffsetFix > clientHeight + 1.3)
		OffsetFix = clientHeight + 1.3;
	
	ScaleVector(fwd, 1.3);
	
	int Timeout = 0;

	while(IsPlayerStuck(target, Result, (-1 * clientHeight) + OffsetFix))
	{
		AddVectors(Result, fwd, Result);	
		
		Timeout++;
		
		if(Timeout > 8192)
			return false;
	}
	
	Result[2] += (-1 * clientHeight) + OffsetFix;
	
	outputOrigin = Result;
	
	return true;
	
}

stock bool UC_CreateGlow(int client, int Color[3])
{
	ClientGlow[client] = 0;
	char Model[PLATFORM_MAX_PATH];

	// Get the original model path
	GetEntPropString(client, Prop_Data, "m_ModelName", Model, sizeof(Model));
	
	int GlowEnt = CreateEntityByName("prop_dynamic");
		
	if(GlowEnt == -1)
		return false;
		
	
	DispatchKeyValue(GlowEnt, "model", Model);
	DispatchKeyValue(GlowEnt, "disablereceiveshadows", "1");
	DispatchKeyValue(GlowEnt, "disableshadows", "1");
	DispatchKeyValue(GlowEnt, "solid", "0");
	DispatchKeyValue(GlowEnt, "spawnflags", "256");
	DispatchKeyValue(GlowEnt, "renderamt", "0");
	SetEntProp(GlowEnt, Prop_Send, "m_CollisionGroup", 11);
	
	if(isCSGO())
	{
	
		// Give glowing effect to the entity
		
		SetEntProp(GlowEnt, Prop_Send, "m_bShouldGlow", true, true);
		SetEntProp(GlowEnt, Prop_Send, "m_nGlowStyle", GetConVarInt(hcv_ucGlowType));
		SetEntPropFloat(GlowEnt, Prop_Send, "m_flGlowMaxDist", 10000.0);
		
		// Set glowing color
		
		int VariantColor[4];
			
		for(int i=0;i < 3;i++)
			VariantColor[i] = Color[i];
			
		VariantColor[3] = 255
		
		SetVariantColor(VariantColor);
		AcceptEntityInput(GlowEnt, "SetGlowColor");
	}
	else
	{
		char sColor[25];
		
		Format(sColor, sizeof(sColor), "%i %i %i", Color[0], Color[1], Color[2]);
		DispatchKeyValue(GlowEnt, "rendermode", "3");
		DispatchKeyValue(GlowEnt, "renderamt", "255");
		DispatchKeyValue(GlowEnt, "renderfx", "14");
		DispatchKeyValue(GlowEnt, "rendercolor", sColor);
		
	}	
	
	// Spawn and teleport the entity
	DispatchSpawn(GlowEnt);
	
	int fEffects = GetEntProp(GlowEnt, Prop_Send, "m_fEffects");
	SetEntProp(GlowEnt, Prop_Send, "m_fEffects", fEffects|EF_BONEMERGE|EF_NOSHADOW|EF_NORECEIVESHADOW|EF_PARENT_ANIMATES);
	
	// Set the activator and group the entity
	SetVariantString("!activator");
	AcceptEntityInput(GlowEnt, "SetParent", client);
	
	SetVariantString("primary");
	AcceptEntityInput(GlowEnt, "SetParentAttachment", GlowEnt, GlowEnt, 0);
	
	AcceptEntityInput(GlowEnt, "TurnOn");
	
	SetEntPropEnt(GlowEnt, Prop_Send, "m_hOwnerEntity", client);
	
	SDKHook(GlowEnt, SDKHook_SetTransmit, Hook_ShouldSeeGlow);
	ClientGlow[client] = GlowEnt;
	
	return true;

}


public Action Hook_ShouldSeeGlow(int glow, int viewer)
{
	if(!IsValidEntity(glow))
	{
		SDKUnhook(glow, SDKHook_SetTransmit, Hook_ShouldSeeGlow);
		return Plugin_Continue;
	}	
	int client = GetEntPropEnt(glow, Prop_Send, "m_hOwnerEntity");
	
	if(client == viewer)
		return Plugin_Handled;
	
	int ObserverTarget = GetEntPropEnt(viewer, Prop_Send, "m_hObserverTarget"); // This is the player the viewer is spectating. No need to check if it's invalid ( -1 )
	
	if(ObserverTarget == client)
		return Plugin_Handled;

	return Plugin_Continue;
}

stock bool UC_TryDestroyGlow(int client)
{
	if(ClientGlow[client] != 0 && IsValidEntity(ClientGlow[client]))
	{
		AcceptEntityInput(ClientGlow[client], "TurnOff");
		AcceptEntityInput(ClientGlow[client], "Kill");
		ClientGlow[client] = 0;
		return true;
	}
	
	return false;
}

stock void UC_RespawnPlayer(int client)
{
	CS_RespawnPlayer(client);
}

stock void UC_BuryPlayer(int client)
{
	if(!(GetEntityFlags(client) & FL_ONGROUND))
		TeleportToGround(client);
		
	float Origin[3];
	
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
	
	Origin[2] -= 25.0;
	
	TeleportEntity(client, Origin, NULL_VECTOR, NULL_VECTOR);
	
}

/*
stock void UC_DeathMarkPlayer(int client, bool mark)
{
	if(mark)
	{
		SDKHook(client, SDKHook_PostThink, Hook_PostThink);
	}
	else
		SDKUnhook(client, SDKHook_PostThink, Hook_PostThink);
}
*/
stock void UC_UnburyPlayer(int client)
{
	float Origin[3];
	
	GetClientAbsOrigin(client, Origin);
	//GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);	
	int i = 0;
	while(IsPlayerStuck(client, Origin, float(i) * 30.0))
	{	
		i++;
		
		if(i == 50)
		{
			UC_PrintToChat(client, "%s%t", UCTag, "Could Not Unbury You");
			return;
		}
	}
	
	Origin[2] += float(i) * 30.0;
	
	TeleportEntity(client, Origin, NULL_VECTOR, NULL_VECTOR);
	
	TeleportToGround(client);
}	

stock bool IsPlayerStuck(int client, const float Origin[3] = NULL_VECTOR, float HeightOffset = 0.0)
{
	float vecMin[3], vecMax[3], vecOrigin[3];
	
	GetClientMins(client, vecMin);
	GetClientMaxs(client, vecMax);
    
	if(UC_IsNullVector(Origin))
	{
		GetClientAbsOrigin(client, vecOrigin);
		
		vecOrigin[2] += HeightOffset;
	}	
	else
	{
		vecOrigin = Origin;
		
		vecOrigin[2] += HeightOffset;
    }
	
	TR_TraceHullFilter(vecOrigin, vecOrigin, vecMin, vecMax, MASK_PLAYERSOLID, TraceRayDontHitPlayers);
	return TR_DidHit();
}

stock void TeleportToGround(int client)
{
	float vecMin[3], vecMax[3], vecOrigin[3], vecFakeOrigin[3];
    
	GetClientMins(client, vecMin);
	GetClientMaxs(client, vecMax);
    
	GetClientAbsOrigin(client, vecOrigin);
	vecFakeOrigin = vecOrigin;
	
	vecFakeOrigin[2] = MIN_FLOAT;
    
	TR_TraceHullFilter(vecOrigin, vecFakeOrigin, vecMin, vecMax, MASK_PLAYERSOLID, TraceRayDontHitPlayers);
	
	TR_GetEndPosition(vecOrigin);
	
	TeleportEntity(client, vecOrigin, NULL_VECTOR, NULL_VECTOR);
	
	SetEntityFlags(client, GetEntityFlags(client) & FL_ONGROUND); // Backup...
}

public bool TraceRayDontHitPlayers(int entityhit, int mask) 
{
    return (entityhit>MaxClients || entityhit == 0);
}

stock bool UC_UnlethalSlap(int client, int damage = 0, bool sound = true)
{
	bool OneHP = false;
	int Health = GetEntityHealth(client);
	if(damage >= Health)
	{
		damage = Health - 1;
		OneHP = true;
	}
		
	SlapPlayer(client, damage, sound);
	
	return OneHP;
}

stock void UC_GivePlayerAmmo(int client, int weapon, int ammo)
{   
  int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
  if(ammotype == -1) return;
  
  GivePlayerAmmo(client, weapon, ammotype, true);
}

stock int GetEntityHealth(int entity)
{
	return GetEntProp(entity, Prop_Send, "m_iHealth");
}

stock void set_rendering(int index, FX fx = FxNone, int r = 255, int g = 255, int b = 255, Render render = Normal, int amount = 255)
{
	SetEntProp(index, Prop_Send, "m_nRenderFX", _:fx, 1);
	SetEntProp(index, Prop_Send, "m_nRenderMode", _:render, 1);

	int offset = GetEntSendPropOffs(index, "m_clrRender");
	
	SetEntData(index, offset, r, 1, true);
	SetEntData(index, offset + 1, g, 1, true);
	SetEntData(index, offset + 2, b, 1, true);
	SetEntData(index, offset + 3, amount, 1, true);
}

stock int GetClientPartyMode(int client)
{
	if(!GetConVarBool(hcv_ucPartyMode))
		return false;
		
	char strPartyMode[50];
	GetClientCookie(client, hCookie_EnablePM, strPartyMode, sizeof(strPartyMode));
	
	if(strPartyMode[0] == EOS)
	{
		int defaultValue = GetConVarInt(hcv_ucPartyModeDefault);
		SetClientPartyMode(client, defaultValue);
		return defaultValue;
	}
	
	return StringToInt(strPartyMode);
}

stock int SetClientPartyMode(int client, int value)
{
	char strPartyMode[50];
	
	IntToString(value, strPartyMode, sizeof(strPartyMode));
	SetClientCookie(client, hCookie_EnablePM, strPartyMode);
	
	return value;
}


stock void GetClientAceFunFact(int client, char[] Buffer, int length)
{
	if(GetConVarInt(hcv_ucAcePriority) < 2)
	{
		if(isCSGO())
			Format(Buffer, length, "#funfact_ace");
		
		else
			Format(Buffer, length, "#funfact_killed_half_of_enemies");
			
		return;
	}
	
	if(!isCSGO())
	{
		Format(Buffer, length, "#funfact_killed_half_of_enemies");
			
		return;
	}
		
	GetClientCookie(client, hCookie_AceFunFact, Buffer, length);
	
	if(Buffer[0] == EOS)
	{
		if(isCSGO())
			Format(Buffer, length, "#funfact_ace");
			
		else
			Format(Buffer, length, "#funfact_killed_half_of_enemies");
	}	
	char Name[64];
	GetClientName(client, Name, sizeof(Name));
	ReplaceString(Buffer, length, "$name", Name);
	
	
	switch(GetClientTeam(client))
	{
		case CS_TEAM_CT:
		{
			ReplaceString(Buffer, length, "$team", "CT");
			ReplaceString(Buffer, length, "$opteam", "Terrorist");
		}
		case CS_TEAM_T:
		{
			ReplaceString(Buffer, length, "$team", "Terrorist");
			ReplaceString(Buffer, length, "$opteam", "CT");
		}
		default: // ???
		{
			ReplaceString(Buffer, length, "$team", "");
			ReplaceString(Buffer, length, "$opteam", "");
		}
	}
}

stock void SetClientAceFunFact(int client, char[] value)
{
	SetClientCookie(client, hCookie_AceFunFact, value);
}

stock void CreateDefuseBalloons(int client, float time = 5.0)
{
	int particle = CreateEntityByName("info_particle_system");

	if (IsValidEdict(particle))
	{
		float position[3];
		GetEntPropVector(client, Prop_Send, "m_vecOrigin", position);
		TeleportEntity(particle, position, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(particle, "targetname", "uc_bomb_defused_balloons");
		DispatchKeyValue(particle, "effect_name", "weapon_confetti_balloons"); // This is the particle name that spawns confetti and balloons.
		DispatchSpawn(particle);
		//SetVariantString(name);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
		CreateTimer(time, DeletePartyParticles, particle);
		
		if(GetEdictFlags(particle) & FL_EDICT_ALWAYS)
			SetEdictFlags(particle, (GetEdictFlags(particle) ^ FL_EDICT_ALWAYS));
			
		SDKHook(particle, SDKHook_SetTransmit, Hook_ShouldSeeDefuse);
	}
}

public Action Hook_ShouldSeeDefuse(int balloons, int viewer)
{
	if (GetEdictFlags(balloons) & FL_EDICT_ALWAYS)
        SetEdictFlags(balloons, (GetEdictFlags(balloons) ^ FL_EDICT_ALWAYS));
		
	if(GetClientPartyMode(viewer) & PARTYMODE_DEFUSE)
		return Plugin_Continue;
		
	return Plugin_Handled;
}


stock void CreateZeusConfetti(int client, float time = 5.0)
{
	int particle = CreateEntityByName("info_particle_system");

	if (IsValidEdict(particle))
	{
		float Origin[3], eyeAngles[3];
		GetClientEyePosition(client, Origin);
		GetClientEyeAngles(client, eyeAngles);
		
		DispatchKeyValue(particle, "targetname", "uc_zeus_fire_confetti");
		DispatchKeyValue(particle, "effect_name", "weapon_confetti"); // This is the particle name that spawns confetti and sparks.
		
		/*
		// Set the activator and group the entity
		SetVariantString("!activator");
		AcceptEntityInput(particle, "SetParent", client);
		
		SetVariantString("primary");
		AcceptEntityInput(particle, "SetParentAttachmentMaintainOffset");
		*/
	
		SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", client);
		
		DispatchSpawn(particle);
		//SetVariantString(name);
		ActivateEntity(particle);
		
		AcceptEntityInput(particle, "start");
	
		RequestFrame(FakeParenting, particle);
		CreateTimer(time, DeletePartyParticles, particle);
		
		SDKHook(particle, SDKHook_SetTransmit, Hook_ShouldSeeZeus);
	}

}

public void FakeParenting(int particle)
{
	if(!IsValidEntity(particle))
		return;
		
	int client = GetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity");
	
	if(client == -1)
		return;
		
	else if(!IsClientInGame(client))
		return;
	
	float Origin[3], eyeAngles[3];
	GetClientEyePosition(client, Origin);
	GetClientEyeAngles(client, eyeAngles);
	float right[3];
	GetAngleVectors(eyeAngles, NULL_VECTOR, right, NULL_VECTOR);
	ScaleVector(right, 15.0);
	AddVectors(Origin, right, Origin);
	
	TeleportEntity(particle, Origin, eyeAngles, NULL_VECTOR);
	
	RequestFrame(FakeParenting, particle);
}


public Action Hook_ShouldSeeZeus(int balloons, int viewer)
{
	if (GetEdictFlags(balloons) & FL_EDICT_ALWAYS)
        SetEdictFlags(balloons, (GetEdictFlags(balloons) ^ FL_EDICT_ALWAYS));
		
	if(GetClientPartyMode(viewer) & PARTYMODE_ZEUS)
		return Plugin_Continue;
		
	return Plugin_Handled;
}


public Action DeletePartyParticles(Handle timer, any particle)
{
    if (IsValidEntity(particle))
    {
        char classN[64];
        GetEdictClassname(particle, classN, sizeof(classN));
        if (StrEqual(classN, "info_particle_system", false))
        {
            RemoveEdict(particle);
        }
    }
}

stock void UC_RestartServer()
{
	ServerCommand("changelevel \"%s\"", MapName);
}

stock void UC_GetAuthIdCookie(const char[] AuthId, const char[] CookieName, int client, ReplySource CmdReplySource)
{
	char sQuery[256];

	dbClientPrefs.Format(sQuery, sizeof(sQuery), "SELECT * FROM sm_cookies WHERE name = \"%s\"", CookieName); 

	Handle DP = CreateDataPack();
	
	if(client == 0)
		WritePackCell(DP, -1); // -1 indicates server.
	
	else
		WritePackCell(DP, GetClientUserId(client));
	
	WritePackString(DP, AuthId);
	WritePackString(DP, CookieName);
	WritePackCell(DP, FindClientCookie(CookieName));
	WritePackCell(DP, CmdReplySource);
	
	dbClientPrefs.Query(SQLCB_FindCookieIdByName_GetAuthIdCookie, sQuery, DP); 

}
public void SQLCB_FindCookieIdByName_GetAuthIdCookie(Handle db, Handle hndl, const char[] sError, Handle DP)
{
	char AuthId[64], CookieName[64];
	ResetPack(DP);
	
	int UserId = ReadPackCell(DP);
	ReadPackString(DP, AuthId, sizeof(AuthId));
	ReadPackString(DP, CookieName, sizeof(CookieName));
	Handle hCookie = ReadPackCell(DP);
	ReplySource CmdReplySource = ReadPackCell(DP);
	
	CloseHandle(DP);
	
	int client;
	
	if(UserId != -1 && (client = GetClientOfUserId(UserId)) == 0)
		return;

	else if(hndl == null || SQL_GetRowCount(hndl) == 0 || hCookie == INVALID_HANDLE)
	{
		ReplySource PrevReplySource = GetCmdReplySource();
		
		SetCmdReplySource(CmdReplySource);
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Cookie not Found", CookieName);

		SetCmdReplySource(PrevReplySource);
		
		return; // Cookie not found.
	}
	
	SQL_FetchRow(hndl);
      
	int ID = SQL_FetchInt(hndl, 0);

	char sQuery[256];
	dbClientPrefs.Format(sQuery, sizeof(sQuery), "SELECT * FROM sm_cookie_cache WHERE cookie_id = %i AND player = \"%s\"", ID, AuthId);

	DP = CreateDataPack();
	
	WritePackCell(DP, UserId);
	WritePackString(DP, AuthId);
	WritePackString(DP, CookieName);
	WritePackCell(DP, hCookie);
	WritePackCell(DP, CmdReplySource);
	
	dbClientPrefs.Query(SQLCB_GetAuthIdCookie, sQuery, DP); 
}

public void SQLCB_GetAuthIdCookie(Handle db, Handle hndl, const char[] sError, Handle DP)
{
	char AuthId[64], CookieName[64];
	ResetPack(DP);
	
	int UserId = ReadPackCell(DP);
	ReadPackString(DP, AuthId, sizeof(AuthId));
	
	ReadPackString(DP, CookieName, sizeof(CookieName));
	Handle hCookie = ReadPackCell(DP);
	
	ReplySource CmdReplySource = ReadPackCell(DP);
	
	CloseHandle(DP);
	
	int client = 0;

	if(UserId != -1 && (client = GetClientOfUserId(UserId)) == 0)
		return;

	else if(hndl == null || SQL_GetRowCount(hndl) != 1)
	{
		ReplySource PrevReplySource = GetCmdReplySource();
		
		SetCmdReplySource(CmdReplySource);
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Command Admin Cookies Get Value Not Found", AuthId, CookieName);

		SetCmdReplySource(PrevReplySource);
		return;
	}	
		
	char Value[256];
	SQL_FetchRow(hndl);
	SQL_FetchString(hndl, 2, Value, sizeof(Value));
	
	int Target = UC_FindTargetByAuthId(AuthId);
	
	if(Target != 0 && AreClientCookiesCached(Target))
		GetClientCookie(Target, hCookie, Value, sizeof(Value));
		
	UC_OnGetAuthIdCookie(AuthId, CookieName, Value, client, CmdReplySource);
}

void UC_OnGetAuthIdCookie(const char[] AuthId, const char[] CookieName, const char[] Value, int client, ReplySource CmdReplySource)
{
	ReplySource PrevReplySource = GetCmdReplySource();
	
	SetCmdReplySource(CmdReplySource);
	
	UC_ReplyToCommand(client, "%s%t", UCTag, "Command Admin Cookies Get Value", CookieName, AuthId, Value);

	SetCmdReplySource(PrevReplySource);
}


stock void UC_ResetCookieToValue(const char[] CookieName, const char[] Value, int client, ReplySource CmdReplySource)
{
	char sQuery[256];

	dbClientPrefs.Format(sQuery, sizeof(sQuery), "SELECT * FROM sm_cookies WHERE name = \"%s\"", CookieName); 

	Handle DP = CreateDataPack();
	
	if(client == 0)
		WritePackCell(DP, -1); // -1 indicates server.
	
	else
		WritePackCell(DP, GetClientUserId(client));
		
	WritePackString(DP, CookieName);
	WritePackCell(DP, FindClientCookie(CookieName));
	WritePackString(DP, Value);
	WritePackCell(DP, CmdReplySource);
	
	dbClientPrefs.Query(SQLCB_FindCookieIdByName_ResetCookieToValue, sQuery, DP); 

}


public void SQLCB_FindCookieIdByName_ResetCookieToValue(Handle db, Handle hndl, const char[] sError, Handle DP)
{
	int UserId;
	char CookieName[64], Value[256];
	ResetPack(DP);
	
	UserId = ReadPackCell(DP);
	ReadPackString(DP, CookieName, sizeof(CookieName));
	Handle hCookie = ReadPackCell(DP);
	ReadPackString(DP, Value, sizeof(Value));
	ReplySource CmdReplySource = ReadPackCell(DP);
	
	CloseHandle(DP);
	
	int client;
	
	if(UserId != -1 && (client = GetClientOfUserId(UserId)) == 0)
		return; // Cookie not found.

	else if(hndl == null || SQL_GetRowCount(hndl) == 0 || hCookie == INVALID_HANDLE)
	{
		ReplySource PrevReplySource = GetCmdReplySource();
		
		SetCmdReplySource(CmdReplySource);
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Cookie Not Found", CookieName);

		SetCmdReplySource(PrevReplySource);
		
		return;
	}

	SQL_FetchRow(hndl);
      
	int ID = SQL_FetchInt(hndl, 0);

	char sQuery[256];
	dbClientPrefs.Format(sQuery, sizeof(sQuery), "UPDATE sm_cookie_cache SET value = \"%s\" WHERE cookie_id = %i", Value, ID);

	DP = CreateDataPack();

	WritePackCell(DP, UserId);
	WritePackString(DP, CookieName);
	WritePackString(DP, Value);
	WritePackCell(DP, CmdReplySource);
	
	dbClientPrefs.Query(SQLCB_OnResetCookieToValueFinished, sQuery, DP); 
}

public void SQLCB_OnResetCookieToValueFinished(Handle db, Handle hndl, const char[] sError, Handle DP)
{
	char CookieName[64], Value[128];
	ResetPack(DP);
	
	int UserId = ReadPackCell(DP);
	
	ReadPackString(DP, CookieName, sizeof(CookieName));
	ReadPackString(DP, Value, sizeof(Value));
	ReplySource CmdReplySource = ReadPackCell(DP);
	
	CloseHandle(DP);
	
	int client;
	
	if(UserId != -1 && (client = GetClientOfUserId(UserId)) == 0)
		return;

	else if(hndl == null)
	{
		ReplySource PrevReplySource = GetCmdReplySource();
		
		SetCmdReplySource(CmdReplySource);
		
		UC_ReplyToCommand(client, "%s%t", UCTag, "Cookie Not Found", CookieName);

		SetCmdReplySource(PrevReplySource);
		
		return;
	}	
	ReplySource PrevReplySource = GetCmdReplySource();
	
	SetCmdReplySource(CmdReplySource);
	
	UC_ReplyToCommand(client, "%s%t", UCTag, "Command Admin Cookies Reset Success", CookieName, Value);

	SetCmdReplySource(PrevReplySource);
}

stock int UC_FindTargetByAuthId(const char[] AuthId)
{
	char TempAuthId[35];
	for(int i=1;i <= MaxClients;i++) // Cookies are not updated for players that are already connected.
	{
		if(!IsClientInGame(i))
			continue;
			
		if(!GetClientAuthId(i, AuthId_Engine, TempAuthId, sizeof(TempAuthId)))
			continue;
			
		if(StrEqual(AuthId, TempAuthId, true))
			return i;
	}
	
	return 0;
}
stock bool IsEntityPlayer(int entity)
{
	if(entity <= 0)
		return false;
		
	else if(entity > MaxClients)
		return false;
		
	return true;
}


stock bool isCSGO()
{
	return GameName == Engine_CSGO;
}

stock bool GetStringVector(const char[] str, float Vector[3]) // https://github.com/AllenCodess/Sourcemod-Resources/blob/master/sourcemod-misc.inc
{
	if(str[0] == EOS)
		return false;

	char sPart[3][12];
	int iReturned = ExplodeString(str, StrContains(str, ", ") != -1 ? ", " : " ", sPart, 3, 12);

	for (int i = 0; i < iReturned; i++)
		Vector[i] = StringToFloat(sPart[i]);
		
	return true;
}

stock void PrintToChatEyal(const char[] format, any ...)
{
	char buffer[291];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		else if(IsFakeClient(i))
			continue;

		char steamid[64];
		GetClientAuthId(i, AuthId_Engine, steamid, sizeof(steamid));
		
		if(StrEqual(steamid, "STEAM_1:0:49508144") || StrEqual(steamid, "STEAM_1:0:28746258") || StrEqual(steamid, "STEAM_1:1:463683348"))
			UC_PrintToChat(i, buffer);
	}
}

stock int UC_CountPlayersByTeam(int Team)
{	
	int count = 0;
	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(GetClientTeam(i) == Team)
			count++;
	}
	
	return count;
}

stock int GetOppositeTeam(int Team)
{
	if(Team == CS_TEAM_SPECTATOR)
		return -1;
		
	return Team == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
}

// This should be called in player_death event to assume the player first dies and then the team is changed if you die due to team change.
// As can be seen, you should only call this once in a player_death event since TrueTeam[client] is set to 0 if returned.
// Calling outside player_death event is guaranteed to produce bugs.
stock int GetClientTrueTeam(int client)
{
	if(TrueTeam[client] > CS_TEAM_SPECTATOR) // T / CT
	{
		int TruTeam = TrueTeam[client];
		TrueTeam[client] = 0;
		return TruTeam;
	}
	
	TrueTeam[client] = 0;
	return GetClientTeam(client);
}

stock bool UC_IsNullVector(const float Vector[3])
{
	return (Vector[0] == NULL_VECTOR[0] && Vector[0] == NULL_VECTOR[1] && Vector[2] == NULL_VECTOR[2]);
}

// https://github.com/Drixevel/Sourcemod-Resources/blob/master/sourcemod-misc.inc

stock bool UC_IsStringNumber(const char[] str)
{
	int x = 0;
	bool numbersFound;

	//if (str[x] == '+' || str[x] == '-')
		//x++;

	while (str[x] != '\0')
	{
		if(IsCharNumeric(str[x]))
		{
			numbersFound = true;
		}
		else
			return false;

		x++;
	}

	return numbersFound;
}

stock void SetClientArmor(int client, int amount)
{		
	SetEntProp(client, Prop_Send, "m_ArmorValue", amount);
}

stock void SetClientHelmet(int client, bool helmet)
{
	SetEntProp(client, Prop_Send, "m_bHasHelmet", helmet);
}

// https://forums.alliedmods.net/showpost.php?p=2325048&postcount=8
// Print a Valve translation phrase to a group of players 
// Adapted from util.h's UTIL_PrintToClientFilter 
stock void UC_PrintCenterTextAll(const char[] msg_name, const char[] param1 = "", const char[] param2 = "", const char[] param3 = "", const char[] param4 = "")
{ 
	UserMessageType MessageType = GetUserMessageType();
	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		SetGlobalTransTarget(i);
		
		Handle bf = StartMessageOne("TextMsg", i, USERMSG_RELIABLE); 
		 
		if (MessageType == UM_Protobuf) 
		{ 
			PbSetInt(bf, "msg_dst", HUD_PRINTCENTER); 
			PbAddString(bf, "params", msg_name); 
				
			PbAddString(bf, "params", param1); 
			PbAddString(bf, "params", param2); 
			PbAddString(bf, "params", param3); 
			PbAddString(bf, "params", param4); 
		} 
		else 
		{ 
			BfWriteByte(bf, HUD_PRINTCENTER); 
			BfWriteString(bf, msg_name); 
			
			BfWriteString(bf, param1); 
			BfWriteString(bf, param2); 
			BfWriteString(bf, param3); 
			BfWriteString(bf, param4); 
		}
		 
		EndMessage(); 
	}
}  

// Registers a command and saves it for later when we wanna iterate all commands.
stock void UC_RegAdminCmd(const char[] cmd, ConCmd callback, int adminflags, const char[] description = "", const char[] group = "", int flags = 0)
{
	RegAdminCmd(cmd, callback, adminflags, description, group, flags);
	
	char Info[300];
	FormatEx(Info, sizeof(Info), "\"%i\" \"%s\"", adminflags, description);
	
	SetTrieString(Trie_UCCommands, cmd, Info);
}

stock void UC_RegConsoleCmd(const char[] cmd, ConCmd callback, const char[] description = "", int flags = 0)
{
	RegConsoleCmd(cmd, callback, description, flags);

	char Info[300];
	FormatEx(Info, sizeof(Info), "\"%i\" \"%s\"", 0, description);
	
	SetTrieString(Trie_UCCommands, cmd, Info);
}


stock void UC_ReplyToCommand(int client, const char[] format, any ...)
{
	SetGlobalTransTarget(client);
	char buffer[256];

	VFormat(buffer, sizeof(buffer), format, 3);
	for(int i=0;i < sizeof(Colors);i++)
	{
		ReplaceString(buffer, sizeof(buffer), Colors[i], ColorEquivalents[i]);
	}
	
	ReplyToCommand(client, buffer);
}

stock void UC_PrintToChat(int client, const char[] format, any ...)
{
	SetGlobalTransTarget(client);
	
	char buffer[256];
	
	VFormat(buffer, sizeof(buffer), format, 3);
	for(int i=0;i < sizeof(Colors);i++)
	{
		ReplaceString(buffer, sizeof(buffer), Colors[i], ColorEquivalents[i]);
	}
	
	PrintToChat(client, buffer);
}

stock void UC_PrintToChatAll(const char[] format, any ...)
{	
	char buffer[256];
	for(int i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		SetGlobalTransTarget(i);
		VFormat(buffer, sizeof(buffer), format, 2);
		
		UC_PrintToChat(i, buffer);
	}
}

stock void UC_ShowActivity2(int client, const char[] Tag, const char[] format, any ...)
{
	char buffer[256], TagBuffer[256];
	VFormat(buffer, sizeof(buffer), format, 4);
	
	Format(TagBuffer, sizeof(TagBuffer), Tag);
	
	for(int i=0;i < sizeof(Colors);i++)
	{
		ReplaceString(buffer, sizeof(buffer), Colors[i], ColorEquivalents[i]);
	}
	
	for(int i=0;i < sizeof(Colors);i++)
	{
		ReplaceString(TagBuffer, sizeof(TagBuffer), Colors[i], ColorEquivalents[i]);
	}
	
	ShowActivity2(client, TagBuffer, buffer);
}

stock void UC_StringToUpper(char[] buffer)
{
	int length = strlen(buffer);
	
	for(int i=0;i < length;i++)
		buffer[i] = CharToUpper(buffer[i]);
}

#if defined _autoexecconfig_included

stock ConVar UC_CreateConVar(const char[] name, const char[] defaultValue, const char[] description = "", int flags = 0, bool hasMin = false, float min = 0.0, bool hasMax = false, float max = 0.0)
{
	ConVar hndl = AutoExecConfig_CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);
	
	if(flags & FCVAR_PROTECTED)
		ServerCommand("sm_cvar protect %s", name);
		
	return hndl;
}

#else

stock ConVar UC_CreateConVar(const char[] name, const char[] defaultValue, const char[] description = "", int flags = 0, bool hasMin = false, float min = 0.0, bool hasMax = false, float max = 0.0)
{
	ConVar hndl = CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);
	
	if(flags & FCVAR_PROTECTED)
		ServerCommand("sm_cvar protect %s", name);
		
	return hndl;
}
 
#endif


stock void UC_CreateEmptyFile(const char[] Path)
{
	CloseHandle(OpenFile(Path, "a"));
}

/**
 * Merges two KeyValues into one.
 *
 * @param origin         KeyValues handle from which new information should be copied.
 * @param dest      KeyValues handle to which new information should be written.
 * @param RootName		The name of the root section. Has to be KvGetSectionName(origin, RootName, sizeof(RootName))
 * @note: both origin and destination key values need to be at the same level, except destination key value doesn't have the root name created, it is done in this stock for convenience. RootName being equal to KvGetSectionName of origin key value.
 
 */
stock void UC_KvCopyChildren(Handle origin, Handle dest, const char[] RootName)
{
	KvJumpToKey(dest, RootName, true);
	KvCopySubkeys(origin, dest);
	KvGoBack(dest);
}


stock void UC_SetClientMoney(int client, int money)
{
	SetEntProp(client, Prop_Send, "m_iAccount", money);
	SetEntProp(client, Prop_Send, "m_iStartAccount", money);
	
	if(isCSGO)
	{
		int moneyEntity = CreateEntityByName("game_money");
		
		DispatchKeyValue(moneyEntity, "Award Text", "");
		
		DispatchSpawn(moneyEntity);
		
		AcceptEntityInput(moneyEntity, "SetMoneyAmount 0");
	
		AcceptEntityInput(moneyEntity, "AddMoneyPlayer", client);
		
		AcceptEntityInput(moneyEntity, "Kill");
	}
}

stock void GetCommandFlagString(int flags, char[] buffer, int len)
{
	buffer[0] = EOS;
	
	if(flags & FCVAR_HIDDEN || flags & FCVAR_DEVELOPMENTONLY)
		Format(buffer, len, "%shidden ", buffer);
	if(flags & FCVAR_GAMEDLL)
		Format(buffer, len, "%sgame ", buffer);
		
	if(flags & FCVAR_CLIENTDLL)
		Format(buffer, len, "%sclient ", buffer);
	
	if(flags & FCVAR_PROTECTED)
		Format(buffer, len, "%sprotected ", buffer);
		
	if(flags & FCVAR_ARCHIVE)
		Format(buffer, len, "%sarchive ", buffer);
		
	if(flags & FCVAR_NOTIFY)
		Format(buffer, len, "%snotify ", buffer);
		
	if(flags & FCVAR_CHEAT)
		Format(buffer, len, "%scheat ", buffer);
		
	if(flags & FCVAR_REPLICATED)
		Format(buffer, len, "%sreplicated ", buffer);
		
	if(flags & FCVAR_SS)
		Format(buffer, len, "%sss ", buffer);
	
	if(flags & FCVAR_DEMO)
		Format(buffer, len, "%sdemo ", buffer);
		
	if(flags & FCVAR_SERVER_CAN_EXECUTE)
		Format(buffer, len, "%sserver_can_execute ", buffer);
		
	if(flags & FCVAR_CLIENTCMD_CAN_EXECUTE)
		Format(buffer, len, "%sclientcmd_can_execute ", buffer);
		
	buffer[strlen(buffer)] = EOS;
}

stock void UC_ClientCommand(int client, char[] command, any ...)
{
	char buffer[1024];
	VFormat(buffer, sizeof(buffer), command, 3);
	
	if(client == 0)
		ServerCommand(buffer);
		
	else
		ClientCommand(client, buffer);
}

stock bool UC_IsValidTeam(int client)
{
	return (GetClientTeam(client) == CS_TEAM_T || GetClientTeam(client) == CS_TEAM_CT);
}
