#include "NativeKitTransaction.v36.h"
#include "NativeKitSlots.v36.h"
#include "AttachmentCompatibility.v36.h"
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <sstream>
#include <unordered_map>
// v36 supported native offline-kit editing on BO3 using validated 0x14 Zombies DDL.
// Unsupported attachment assets remain local drafts.
// Cosmetic style indexes may need per-gun assets; non-default new IDs are opt-in.
struct V24Weapon {
    std::string script;
    std::string display;
    std::string group;
    std::vector<std::string> allowed;
    bool hidden;
};
struct V24Camo {
    int id;
    std::string display;
    std::string script;
    std::string group;
};
static std::vector<V24Weapon> v24Weapons;
static std::vector<V24Camo> v24Camos;
static std::vector<std::string> v24Attachments;
static std::vector<std::string> v25AllAttachments;
static bool v25ShowAllAttachmentOptions = false;
// Cosmetic appearance variants are separate from gameplay attachment tokens.
// IDs are UNVERIFIED manual draft values, not an inventory of owned BM looks.
static std::unordered_map<std::string, int> v26CosmeticVariantIds;
static const char* v26VariantLabels =
    "Default (0)\0Look ID 1*\0Look ID 2*\0Look ID 3*\0Look ID 4*\0"
    "Look ID 5*\0Look ID 6*\0Look ID 7*\0Look ID 8*\0\0";
static bool V26PrestigeToken(const std::string& token) {
    return token == "gmod6" || token == "gmod7";
}
static int V26PrestigeChoice() {
    const bool clan = std::find(v24Attachments.begin(), v24Attachments.end(), "gmod6") != v24Attachments.end();
    const bool counter = std::find(v24Attachments.begin(), v24Attachments.end(), "gmod7") != v24Attachments.end();
    return (clan ? 1 : 0) | (counter ? 2 : 0);
}
static void V26SetPrestigeChoice(int choice) {
    v24Attachments.erase(std::remove_if(v24Attachments.begin(), v24Attachments.end(), V26PrestigeToken), v24Attachments.end());
    if (choice & 1) v24Attachments.push_back("gmod6"); // MP prestige clan tag
    if (choice & 2) v24Attachments.push_back("gmod7"); // MP prestige kill counter
}
static void V26ResetVariant(const std::string& token) { v26CosmeticVariantIds.erase(token); }

static bool V25WeaponSupports(const V24Weapon& weapon, const std::string& attachment) {
    return std::find(weapon.allowed.begin(), weapon.allowed.end(), attachment) != weapon.allowed.end();
}
static int v24WeaponIndex = -1;
static int v24CamoId = 0;
static int v24ListFilter = 0;  // All, Normal, Hidden
static char v24WeaponSearch[96] = {};
static char v24CamoSearch[96] = {};
static std::string v24Message = "Choose Zombies and click Scan Weapons & Camos.";

static bool V24Contains(const std::vector<std::string>& arr, const std::string& v) {
    return std::find(arr.begin(), arr.end(), v) != arr.end();
}
static bool V24Matches(std::string value, std::string query) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return (char)std::tolower(c); });
    std::transform(query.begin(), query.end(), query.begin(), [](unsigned char c) { return (char)std::tolower(c); });
    return query.empty() || value.find(query) != std::string::npos;
}
static bool V24IsOptic(const std::string& s) {
    return s == "reflex" || s == "reddot" || s == "holo" || s == "acog" ||
        s == "dualoptic" || s == "ir" || s == "mms" || s == "vzoom" ||
        s == "dynzoom" || s == "rangefinder" || s == "is";
}
static std::string V24WeaponName(const std::string& script, const char* localizedKey) {
    struct Alias { const char* id; const char* display; };
    static const Alias aliases[] = {
        {"bowie_knife","Bowie Knife"},{"bowie_flourish","Bowie Knife (Flourish Animation)"},{"knife_loadout","Combat Knife"},
        {"pistol_standard","MR6"},{"pistol_m1911","M1911"},{"smg_ppsh","PPSh-41"},
        {"lmg_rpk","RPK"},{"smg_ak74u","AK-74u"},{"smg_mp40","MP40"},
        {"smg_sten","Sten"},{"ar_fastburst","M8A7"},{"ar_famas","FFAR"},{"ar_garand","MX Garand"},
        {"ar_m16","M16"},{"ar_galil","Galil"},{"ar_peacekeeper","Peacekeeper MK2"},
        {"smg_hg40","HG 40"},{"pistol_shotgun","Marshal 16"},
        {"pistol_revolver38","Revolver"}
    };
    for (const auto& a : aliases) if (script == a.id) return a.display;
    if (localizedKey && *localizedKey) {
        const char* localized = UI_SafeTranslateString(localizedKey);
        if (localized && *localized && std::string(localized) != localizedKey) return localized;
    }
    std::string out = script;
    std::replace(out.begin(), out.end(), '_', ' ');
    if (!out.empty()) out[0] = (char)std::toupper((unsigned char)out[0]);
    return out;
}
static std::string V24AttachmentName(const std::string& a) {
    struct Alias { const char* id; const char* label; };
    static const Alias known[] = {
        {"reflex","Reflex Sight"},{"reddot","Red Dot"},{"holo","Holo Sight"},
        {"acog","ACOG"},{"dualoptic","Dual Optic"},{"ir","Thermal"},
        {"quickdraw","Quickdraw"},{"grip","Grip"},{"stalker","Stock"},
        {"steadyaim","Laser Sight"},{"fmj","FMJ"},{"fastreload","Fast Mags"},
        {"extclip","Extended Mag"},{"extbarrel","Long Barrel"},{"rf","Rapid Fire"},
        {"suppressed","Suppressor"},{"dw","Dual Wield"},{"damage","High Caliber"},
        {"swayreduc","Ballistics CPU"},{"vzoom","Variable Zoom"},
        {"mms","Target Finder"},{"gl","Grenade Launcher"},{"gmod6","Clan Tag (MP Prestige)"},
        {"gmod7","Kill Counter (MP Prestige)"}
    };
    for (const auto& k : known) if (a == k.id) return k.label;
    return a;
}
static std::string V24CamoFallback(const std::string& script) {
    std::string n = script;
    if (n.find("camo_") == 0) n = n.substr(5);
    std::replace(n.begin(), n.end(), '_', ' ');
    bool capitalize = true;
    for (auto& ch : n) {
        if (capitalize) ch = (char)std::toupper((unsigned char)ch);
        capitalize = (ch == ' ');
    }
    return n;
}
static const V24Camo* V24FindCamo(int id) {
    for (const auto& c : v24Camos) if (c.id == id) return &c;
    return nullptr;
}
static std::string V24PresetPath(bool previous = false) {
    char buffer[MAX_PATH] = {};
    DWORD n = GetEnvironmentVariableA("LOCALAPPDATA", buffer, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return "";
    std::string dir(buffer);
    dir += "\\ScroptsQOL";
    if (!CreateDirectoryA(dir.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return "";
    return dir + (previous ? "\\zombies_weapon_kit_drafts_v23.ini" : "\\zombies_weapon_kit_drafts_v24.ini");
}
static void V24LoadPreset() {
    v24Attachments.clear();
    v26CosmeticVariantIds.clear();
    v24CamoId = 0;
    if (v24WeaponIndex < 0 || v24WeaponIndex >= (int)v24Weapons.size()) return;
    const V24Weapon& w = v24Weapons[v24WeaponIndex];
    std::string file = V24PresetPath();
    if (file.empty()) { v24Message = "Unable to read the local kit folder."; return; }
    char buffer[2048] = {};
    // Migrate an existing v23 attachment draft if v24 has not saved this weapon yet.
    GetPrivateProfileStringA(w.script.c_str(), "attachments", "__missing__", buffer, sizeof(buffer), file.c_str());
    if (std::string(buffer) == "__missing__") {
        const std::string old = V24PresetPath(true);
        if (!old.empty()) GetPrivateProfileStringA(w.script.c_str(), "attachments", "", buffer, sizeof(buffer), old.c_str());
    }
    std::istringstream ss(buffer);
    std::string token;
    while (ss >> token) {
        if ((V24Contains(v25AllAttachments, token) || V24Contains(w.allowed, token) || V26PrestigeToken(token)) && !V24Contains(v24Attachments, token)) {
            if (V24IsOptic(token)) {
                v24Attachments.erase(std::remove_if(v24Attachments.begin(), v24Attachments.end(), V24IsOptic), v24Attachments.end());
            }
            v24Attachments.push_back(token);
        }
    }
    // Preserve v24 attachment drafts while optionally loading v26 style indexes.
    // A style is meaningful only for an already-selected attachment.
    for (const auto& a : v24Attachments) {
        char style[24] = {};
        const std::string key = "variant_" + a;
        GetPrivateProfileStringA(w.script.c_str(), key.c_str(), "0", style, sizeof(style), file.c_str());
        char* endStyle = nullptr;
        long idx = std::strtol(style, &endStyle, 10);
        if (endStyle != style && !*endStyle && idx >= 1 && idx <= 8)
            v26CosmeticVariantIds[a] = (int)idx;
    }
    char id[24] = {};
    GetPrivateProfileStringA(w.script.c_str(), "camo_id", "0", id, sizeof(id), file.c_str());
    int requestedCamo = (int)std::strtol(id, nullptr, 10);
    if (V24FindCamo(requestedCamo)) v24CamoId = requestedCamo;
    v24Message = "Local draft loaded for " + w.display + ".";
}
static void V24SavePreset() {
    if (v24WeaponIndex < 0 || v24WeaponIndex >= (int)v24Weapons.size()) {v24Message = "Select a weapon first."; return;}
    const V24Weapon& w = v24Weapons[v24WeaponIndex];
    const std::string file = V24PresetPath();
    if (file.empty()) {v24Message = "Couldn't create local kit folder.";return;}
    std::string joined;
    for (const auto& a : v24Attachments) {
        if (!joined.empty()) joined += ' ';
        joined += a;
    }
    const std::string camo = std::to_string(v24CamoId);
    bool ok1 = !!WritePrivateProfileStringA(w.script.c_str(), "attachments", joined.c_str(), file.c_str());
    bool ok2 = !!WritePrivateProfileStringA(w.script.c_str(), "camo_id", camo.c_str(), file.c_str());
    bool stylesOK = true;
    // Existing style keys from the old draft must be cleared on attachment removal.
    std::vector<std::string> allStyleTokens = v25AllAttachments;
    for (const auto& a : w.allowed)
        if (!V24Contains(allStyleTokens, a)) allStyleTokens.push_back(a);
    for (const auto& token : allStyleTokens) {
        const std::string key = "variant_" + token;
        const auto variant = v26CosmeticVariantIds.find(token);
        const bool keep = V24Contains(v24Attachments, token) &&
            variant != v26CosmeticVariantIds.end() && variant->second >= 1 && variant->second <= 8;
        const std::string number = keep ? std::to_string(variant->second) : "";
        stylesOK = !!WritePrivateProfileStringA(w.script.c_str(), key.c_str(),
            keep ? number.c_str() : nullptr, file.c_str()) && stylesOK;
    }
    v24Message = ok1 && ok2 && stylesOK ? ("Saved LOCAL draft for " + w.display + ". Not applied to BO3.") : "Preset save failed.";
}
static void V24ChooseAttachment(const std::string& a, bool selected) {
    if (!selected) {
        v24Attachments.erase(std::remove(v24Attachments.begin(), v24Attachments.end(), a), v24Attachments.end());
        V26ResetVariant(a);
        return;
    }
    // Exactly one optic is supported. Other compatible attachments have no draft-count cap.
    if (V24IsOptic(a)) {
        v24Attachments.erase(std::remove_if(v24Attachments.begin(), v24Attachments.end(), V24IsOptic), v24Attachments.end());
    }
    if (!V24Contains(v24Attachments, a)) v24Attachments.push_back(a);
}
static void V24SelectAllCompatible() {
    if (v24WeaponIndex < 0 || v24WeaponIndex >= (int)v24Weapons.size()) return;
    const auto& w = v24Weapons[v24WeaponIndex];
    v24Attachments.clear();
    // Prefer Reflex when available, otherwise first optic from the game table.
    std::string optic;
    if (V24Contains(w.allowed, "reflex")) optic = "reflex";
    else for (const auto& a : w.allowed) if (V24IsOptic(a)) {optic = a;break;}
    if (!optic.empty()) v24Attachments.push_back(optic);
    for (const auto& a : w.allowed) if (!V24IsOptic(a) && !V26PrestigeToken(a)) v24Attachments.push_back(a);
    v26CosmeticVariantIds.clear();
    v24Message = "Selected all catalog-listed attachments (one optic). Local draft only.";
}
static void V24Scan() {
    v24Weapons.clear();v24Camos.clear();v24Attachments.clear();v25AllAttachments.clear();v26CosmeticVariantIds.clear();v24WeaponIndex = -1;v24CamoId = 0;
    if (Com_SessionMode_GetMode() != MODE_ZOMBIES) {v24Message = "Enter the Zombies lobby before scanning.";return;}
    StringTable* guns = nullptr;
    StringTable_GetAsset("gamedata/stats/zm/zm_statstable.csv", &guns);
    if (!guns || guns->rowCount <= 0 || guns->rowCount > 1024 || guns->columnCount < 15) {
        v24Message = "Zombies weapon table isn't available.";return;
    }
    for (int i = 0; i < guns->rowCount; ++i) {
        const char* s = StringTable_GetColumnValueForRow(guns, i, 4);
        const char* attachmentList = StringTable_GetColumnValueForRow(guns, i, 8);
        const char* category = StringTable_GetColumnValueForRow(guns, i, 2);
        const char* nameKey = StringTable_GetColumnValueForRow(guns, i, 3);
        const char* visibility = StringTable_GetColumnValueForRow(guns, i, 12);
        if (!s || !*s || !category || std::string(category).find("weapon_") != 0) continue;
        const std::string script(s);
        if (script.size() > 80 || script == "weapon_null" ||
            script.find("_upgraded") != std::string::npos || script.find("_dw") != std::string::npos) continue;
        V24Weapon w;
        w.script = script;
        w.display = V24WeaponName(script,nameKey);
        w.group = category;
        w.hidden = visibility && std::string(visibility) == "-1";
        std::istringstream tokens(attachmentList ? attachmentList : "");
        std::string a;
        while (tokens >> a) {
            if (a.size() > 48 || w.allowed.size() >= 40) break;
            if (!V24Contains(w.allowed,a)) w.allowed.push_back(a);
        }
        // Keep weapons with no attachment slots, including Bowie Knife and melee weapons.
        // Such weapons can still receive a camo draft where the game provides a material.
        v24Weapons.push_back(std::move(w));
    }
    std::sort(v24Weapons.begin(), v24Weapons.end(), [](const V24Weapon& a,const V24Weapon& b) {
        if (a.display != b.display) return a.display < b.display;
        return a.script < b.script;
    });
    StringTable* camoTable = nullptr;
    StringTable_GetAsset("gamedata/weapons/common/attachmenttable.csv", &camoTable);
    if (camoTable && camoTable->rowCount >= 46 && camoTable->rowCount <= 1024 && camoTable->columnCount >= 21) {
        // Build the *global* attachment selector from the actual asset table.
        // Listing a token here does not make it loadable on every weapon.
        for (int i = 1; i < std::min(45, camoTable->rowCount); ++i) {
            const char* cat = StringTable_GetColumnValueForRow(camoTable, i, 2);
            const char* token = StringTable_GetColumnValueForRow(camoTable, i, 4);
            if (!cat || !token || !*token || std::string(token) == "none") continue;
            if ((std::string(cat) == "optic" || std::string(cat) == "rig") &&
                std::string(token).size() < 48 && !V24Contains(v25AllAttachments, token))
                v25AllAttachments.push_back(token);
        }
        // BO3's table places camo IDs 0-137 on rows 45-182; optics/reticles follow.
        const int last = std::min(183, camoTable->rowCount);
        for (int i = 45; i < last; ++i) {
            const char* idText = StringTable_GetColumnValueForRow(camoTable,i,0);
            const char* type = StringTable_GetColumnValueForRow(camoTable,i,1);
            const char* key = StringTable_GetColumnValueForRow(camoTable,i,3);
            const char* raw = StringTable_GetColumnValueForRow(camoTable,i,4);
            const char* grp = StringTable_GetColumnValueForRow(camoTable,i,20);
            if (!idText || !type || std::string(type) != "camo" || !raw || !*raw) continue;
            char* end = nullptr;
            long id = std::strtol(idText,&end,10);
            if (end == idText || *end || id < 0 || id > 137) continue;
            V24Camo c;
            c.id = (int)id;
            c.script = raw;
            c.group = grp ? grp : "";
            c.display = V24CamoFallback(c.script);
            if (key && *key) {
                const char* translated = UI_SafeTranslateString(key);
                if (translated && *translated && std::string(translated) != key) c.display = translated;
            }
            v24Camos.push_back(std::move(c));
        }
    }
    if (!V24FindCamo(0)) v24Camos.insert(v24Camos.begin(), {0,"None","camo_none",""});
    // Some asset builds omit rows from the global table; always allow a visible
    // suppressor request without inventing a per-gun weapon asset.
    if (!V24Contains(v25AllAttachments, "suppressed")) v25AllAttachments.push_back("suppressed");
    v24Message = "Found " + std::to_string(v24Weapons.size()) + " weapons, " +
        std::to_string(v25AllAttachments.size()) + " attachment types and " +
        std::to_string(v24Camos.size()) + " camos. Offline native pilot available for verified entries.";
}

// v32 verified from user v31 report: 0x14 holds offline ZM loadouts.
// Strict offline-only pilot. The schema is checked *every* time before reading or
// writing. Never use the stale Scropts STORAGE_ZM_LOADOUTS_OFFLINE enum (0x16).
// No online/cloud upload, no unsupported attachment assets or melee creation.
static std::string v27NativeStatus = "Choose a weapon, then Save & Apply (offline). The native kit is checked automatically.";
static int v27NativeSlot = -1;
static int v27NativeMPId = -1;
static int v32ProbedZMId = -1;
static std::string v32ProbedWeapon;
static bool v27WritesConfirmed = false;
// Default protects existing cosmetic parts when a user modifies their attachment set.
// Unverified new Black Market look indexes always need a separate confirmation.
static bool v33PreserveNativeLooks = true;
static bool v33AllowUnverifiedLooks = false;
// v36: automatic creation in a rigorously checked EMPTY native variant slot.
// Only unmodified base firearms with matching ZM/MP IDs and an attachment
// catalog may qualify. Animation/melee and special weapon IDs are excluded.
// A failed persistence call or unverified rollback needs recovery, not another write.
static bool v36NativeWritesSuspended = false;
static bool v36ShowCosmeticSelectors = false;
static int v36PreparedEmptySlot = -1;
static std::string v36PreparedWeapon;
static int v36PreparedZM = -1;
static const int v32VerifiedOfflineFile = 0x14;
static bool V27CanWrite() {
    return Com_SessionMode_GetMode() == MODE_ZOMBIES && !Com_SessionMode_IsOnlineGame();
}
static int V29TableIndex(const std::string& token, const char* path) {
    // Weapon LIST must come from ZM. This finds a table-specific ID only;
    // it does NOT claim that the native stored weaponIndex uses that ID.
    StringTable* table = nullptr;
    StringTable_GetAsset(path, &table);
    if (!table || table->rowCount <= 0 || table->rowCount > 512 || table->columnCount < 9) return -1;
    for (int i=0; i<table->rowCount; ++i) {
        const char* script = StringTable_GetColumnValueForRow(table,i,4);
        if (!script || token != script) continue;
        const char* id = StringTable_GetColumnValueForRow(table,i,0);
        if (!id) continue;
        char* end = nullptr;
        const long value = std::strtol(id,&end,10);
        if (end != id && !*end && value >= 1 && value <= 511) return (int)value;
    }
    return -1;
}
static int V29ZMIndex(const std::string& token) {
    return V29TableIndex(token,"gamedata/stats/zm/zm_statstable.csv");
}
static int V27MPIndex(const std::string& token) {
    // Used for comparison ONLY; never use MP lookup as a mandatory ZM gate.
    return V29TableIndex(token,"gamedata/stats/mp/mp_statstable.csv");
}
// Eligibility is conservative: a real base firearm, a native attachment list,
// and identical ZM/MP item IDs. This does NOT guarantee that a newly created
// variant will appear in-game; creation still requires an in-game persistence test.
static bool V36CanCreateFor(const V24Weapon& w, int zm, int mp) {
    if (zm < 1 || zm > 199 || zm != mp || w.allowed.empty()) return false;
    if (w.script.find("_upgraded")!=std::string::npos ||
        w.script.find("flourish")!=std::string::npos ||
        w.script.find("knife")!=std::string::npos ||
        w.script.find("melee")!=std::string::npos) return false;
    return w.group == "weapon_ar" || w.group == "weapon_smg" ||
           w.group == "weapon_lmg" || w.group == "weapon_sniper" ||
           w.group == "weapon_cqb" || w.group == "weapon_pistol";
}

// BO3 Lua uses `cacLoadouts`; DDL navigation may differ. Probe both cases.
// Navigate named DDL members with MoveToName and numeric array slots with
// MoveToIndex. In v27, the string-based path passed "0" as a member name;
// this did not prove the engine resolved an array index.
static bool V27DDLState(DDLState* root, const std::vector<std::string>& steps, DDLState& output) {
    if (!root || !root->isValid || steps.empty() || steps.size() > 8) return false;
    DDLState current = *root;
    for (const auto& step : steps) {
        if (step.empty()) return false;
        DDLState next = {};
        bool numeric = std::all_of(step.begin(), step.end(), [](unsigned char c) {return c >= '0' && c <= '9';});
        bool moved = false;
        if (numeric) {
            char* end = nullptr;
            long index = std::strtol(step.c_str(), &end, 10);
            if (end == step.c_str() || *end || index < 0 || index > 1024) return false;
            moved = DDL_MoveToIndex(&current, &next, (int)index);
        } else {
            moved = !!DDL_MoveToName(reinterpret_cast<__int64>(&current), reinterpret_cast<char*>(&next), step.c_str());
        }
        if (!moved || !next.isValid) return false;
        current = next;
    }
    output = current;
    return true;
}
static bool V27Read(DDLState* root, DDLContext* ctx, const std::vector<std::string>& steps, uint32_t& value) {
    if (!ctx) return false;
    DDLState state = {};
    if (!V27DDLState(root,steps,state)) return false;
    value=(uint32_t)DDL_GetUInt(reinterpret_cast<__int64>(&state), reinterpret_cast<__int64>(ctx));
    return true;
}
// v30 READ-ONLY: verify that the legacy storage functions return a DDL
// definition that actually describes Zombies loadouts. Root.isValid alone
// proves nothing if an RVA points to a different function after a patch.
static bool V30Readable(const void* p, size_t size) {
    if (!p || size < 1 || size > 4096) return false;
    MEMORY_BASIC_INFORMATION mb{};
    if (!VirtualQuery(p, &mb, sizeof(mb)) || mb.State != MEM_COMMIT) return false;
    if ((mb.Protect & PAGE_GUARD) || (mb.Protect & PAGE_NOACCESS)) return false;
    const auto protection = mb.Protect & 0xFF;
    if (protection != PAGE_READONLY && protection != PAGE_READWRITE &&
        protection != PAGE_WRITECOPY && protection != PAGE_EXECUTE_READ &&
        protection != PAGE_EXECUTE_READWRITE && protection != PAGE_EXECUTE_WRITECOPY) return false;
    const uintptr_t address = (uintptr_t)p;
    const uintptr_t base = (uintptr_t)mb.BaseAddress;
    if (address < base || address-base >= mb.RegionSize) return false;
    return size <= mb.RegionSize-(address-base);
}
static std::string V30SafeText(const char* p) {
    if (!p) return "NULL";
    std::string result;
    for (int i=0;i<95;++i) {
        const char* q=p+i;
        if (!V30Readable(q,1)) return result.empty()?"(unreadable)":result+"(truncated)";
        const unsigned char c=(unsigned char)*q;
        if (!c) return result.empty()?"(empty)":result;
        if (c < 32 || c > 126) return "(non-text)";
        result.push_back((char)c);
    }
    return result+"...";
}
static std::string V30RootMetadata(DDLState* root, DDLContext* ctx) {
    std::ostringstream a;
    if (!V30Readable(root, sizeof(DDLState)) || !V30Readable(ctx, sizeof(DDLContext))) {
        a << "Root/context pointer not safely readable; ";return a.str();
    }
    a << "rootValid=" << (root->isValid?1:0)
      << ", offset=" << root->offset
      << ", arrIndex=" << root->arrayIndex
      << ", ctxLen=" << ctx->len
      << ", ctxDefMatchesRoot=" << ((root->ddlDef && root->ddlDef==ctx->def)?"YES":"NO") << "; ";
    const DDLDef* def=root->ddlDef;
    if (!V30Readable(def,sizeof(DDLDef))) {
        a << "root DDLDef unreadable; ";return a.str();
    }
    a << "rootDef=" << V30SafeText(def->name)
      << ", structs=" << def->structCount << "; ";
    if (V30Readable(ctx->def,sizeof(DDLDef)) && ctx->def!=def)
        a << "contextDef=" << V30SafeText(ctx->def->name) << "; ";
    // Inspect a small number of root member names. These come from in-memory
    // DDL schema, not a guessed path, and never modify game storage.
    if (def->structCount<=0 || def->structCount>512 ||
        !V30Readable(def->structList,sizeof(DDLStruct))) return a.str();
    const DDLStruct* str=&def->structList[0];
    a << "rootStruct=" << V30SafeText(str->name)
      << ", members=" << str->memberCount << "; ";
    if (str->memberCount<=0 || str->memberCount>256 || !str->members) return a.str();
    a << "rootFields=";
    int found=0;
    for (int i=0; i<str->memberCount && found<18; ++i) {
        const DDLMember* field=&str->members[i];
        if (!V30Readable(field,sizeof(DDLMember))) break;
        if (found++) a << ",";
        a << V30SafeText(field->name);
    }
    a << "; ";
    return a.str();
}

// Returns the exact offline Zombies DDL, or a human-readable reason for refusal.
static bool V32GetOffline(DDLState*& root, DDLContext*& ctx, std::string& why) {
    root = nullptr; ctx = nullptr;
    if (!V27CanWrite()) {why="Open an OFFLINE Zombies lobby. No changes made.";return false;}
    root=Storage_GetDDLRootState(v32VerifiedOfflineFile);
    ctx=Storage_GetDDLContext(0,v32VerifiedOfflineFile,0);
    if (!V30Readable(root,sizeof(DDLState)) || !V30Readable(ctx,sizeof(DDLContext)) ||
        !root->isValid || !V30Readable(root->ddlDef,sizeof(DDLDef)) ||
        !V30Readable(ctx->def,sizeof(DDLDef)) || root->ddlDef!=ctx->def) {
        why="Storage 0x14 root/context are unavailable or disagree. Nothing written.";return false;
    }
    const std::string def=V30SafeText(root->ddlDef->name);
    if (def != "gamedata/ddl/loadouts/zm_loadouts_offline.ddl" ||
        root->offset!=0 || root->arrayIndex!=-1 || ctx->len!=13312 || !ctx->buff) {
        why="Storage 0x14 schema changed: "+def+", len="+std::to_string(ctx->len)+". Writes BLOCKED.";return false;
    }
    DDLState arr{};
    if (!V27DDLState(root,{"cacLoadouts","variant"},arr)) {
        why="0x14 is Zombies loadouts but cacLoadouts.variant is unreadable. Writes BLOCKED.";return false;
    }
    DDLState item{};
    if (!DDL_MoveToIndex(&arr,&item,0) || !item.isValid) {
        why="0x14 variant[0] unavailable. Writes BLOCKED.";return false;
    }
    return true;
}
static int V32ScanSlot(DDLState* root, DDLContext* ctx, int zmID, std::string& detail) {
    DDLState array{};
    if (!V27DDLState(root,{"cacLoadouts","variant"},array)) {detail="Variant array inaccessible";return -1;}
    int count=0, valid=0, candidate=-1;
    std::ostringstream occupied;
    for (int slot=0;slot<160;++slot) {
        DDLState item{};
        if (!DDL_MoveToIndex(&array,&item,slot) || !item.isValid) break;
        ++valid;
        uint32_t index=0;
        if (!V27Read(root,ctx,{"cacLoadouts","variant",std::to_string(slot),"weaponIndex"},index)) {
            detail="variant["+std::to_string(slot)+"].weaponIndex unavailable; sample blocked";return -1;
        }
        if (index && index!=0xFFFFFFFF && occupied.tellp()<std::streampos(220)) {
            occupied << slot << ":" << index << " ";
        }
        if (zmID>=0 && index==(uint32_t)zmID) {++count;candidate=slot;}
    }
    std::ostringstream d;
    d << "variant slots readable=" << valid << "; occupied samples=" << occupied.str()
      << "; matching weaponIndex=" << zmID << " count=" << count;
    detail=d.str();
    if (valid != 50 || count != 1) return -1;
    return candidate;
}
static bool V36FindFreeCandidate(DDLState* root, DDLContext* ctx, int weaponId, int& candidate, std::string& info);
static void V27NativeProbe() {
    v27NativeSlot=-1;v27NativeMPId=-1;v32ProbedZMId=-1;v32ProbedWeapon.clear();
    v36PreparedEmptySlot=-1;v36PreparedWeapon.clear();v36PreparedZM=-1;
    if (v24WeaponIndex<0 || v24WeaponIndex>=(int)v24Weapons.size()) {v27NativeStatus="Select a Zombies weapon first.";return;}
    const auto& w=v24Weapons[v24WeaponIndex];
    const int zm=V29ZMIndex(w.script), mp=V27MPIndex(w.script);
    std::ostringstream out;
    out << "v36 " << w.display << " [" << w.script << "] ZM=" << zm << ", MP=" << mp << "; ";
    DDLState* root=nullptr; DDLContext* ctx=nullptr;std::string why;
    if (!V32GetOffline(root,ctx,why)) {v27NativeStatus=out.str()+why;return;}
    out << "Verified offline ZM DDL=0x14 (13312 bytes); ";
    const int slot=V32ScanSlot(root,ctx,zm,why);
    out << why << "; ";
    if (zm<1 || mp<1 || zm!=mp) {
        out << "ZM/MP weapon IDs do not agree. Read-only; native mapping not proven.";
        v27NativeStatus=out.str();return;
    }
    if (slot<0) {
        out << "No unique verified native kit entry. ";
        if (V36CanCreateFor(w,zm,mp)) {
            int empty=-1;std::string details;
            if (V36FindFreeCandidate(root,ctx,zm,empty,details) && empty>=0) {
                v36PreparedEmptySlot=empty;v36PreparedWeapon=w.script;v36PreparedZM=zm;
                out << "CREATE AVAILABLE: clean empty native slot " << empty
                    << " found. Save & Apply will create it automatically after backup confirmation. ";
            } else out << "CREATE NOT AVAILABLE: " << details << ". ";
        } else if (w.script == "bowie_flourish") {
            out << "bowie_flourish is an alternate melee animation ID, not a confirmed saved kit. Creation disabled. ";
        } else {
            out << "Not an eligible base firearm; no automatic kit creation. ";
        }
        v27NativeStatus=out.str();return;
    }
    uint32_t storedVariant=0, oldCamo=0;
    if (!V27Read(root,ctx,{"cacLoadouts","variant",std::to_string(slot),"variantIndex"},storedVariant) ||
        !V27Read(root,ctx,{"cacLoadouts","variant",std::to_string(slot),"camoIndex"},oldCamo)) {
        out << "Variant metadata unavailable; apply blocked.";v27NativeStatus=out.str();return;
    }
    out << "unique slot=" << slot << ", variantIndex=" << storedVariant << ", stored camo=" << oldCamo << "; ";
    if (storedVariant!=(uint32_t)slot) {
        out << "variantIndex differs from slot; apply BLOCKED.";v27NativeStatus=out.str();return;
    }
    v27NativeSlot=slot;v27NativeMPId=mp;v32ProbedZMId=zm;v32ProbedWeapon=w.script;
    out << "EXACT SINGLE ENTRY VERIFIED. Offline experimental Apply permitted after backup confirmation.";
    v27NativeStatus=out.str();
}
static bool V27GetAttachmentIndex(const std::string& token, uint32_t& id, std::string& compatible) {
    StringTable* table=nullptr;
    StringTable_GetAsset("gamedata/weapons/common/attachmenttable.csv",&table);
    if (!table || table->rowCount<43 || table->rowCount>1024 || table->columnCount<13) return false;
    for(int row=0;row<std::min(45,table->rowCount);++row) {
        const char* raw=StringTable_GetColumnValueForRow(table,row,4);
        if (!raw || token!=raw) continue;
        const char* idText=StringTable_GetColumnValueForRow(table,row,0);
        const char* pairs=StringTable_GetColumnValueForRow(table,row,12);
        if (!idText) return false;
        char* end=nullptr;const long found=std::strtol(idText,&end,10);
        if (end==idText || *end || found<1 || found>254) return false;
        id=(uint32_t)found;compatible=pairs?pairs:"";return true;
    }
    return false;
}
// Read-only evidence gathered on demand. This does not extend the native write
// allowlist or equate menu metadata with an equipped weapon's actual assets.
static std::string V36AttachmentReport() {
    if(v24WeaponIndex<0 || v24WeaponIndex>=(int)v24Weapons.size())
        return "Select a Zombies weapon before inspecting attachment compatibility.";
    if(Com_SessionMode_GetMode()!=MODE_ZOMBIES)
        return "Open Zombies before inspecting the loaded attachment catalog.";
    const auto& weapon=v24Weapons[v24WeaponIndex];
    using namespace weapon_kits::compatibility;
    std::vector<Definition> definitions;
    StringTable* table=nullptr;
    StringTable_GetAsset("gamedata/weapons/common/attachmenttable.csv",&table);
    std::string sourceStatus="Global attachment table unavailable or unexpected; IDs are unknown.\n";
    if(table && table->rowCount>=43 && table->rowCount<=1024 && table->columnCount>=13) {
        // The existing writer reads the first 45 rows. Report the same range
        // explicitly; omitted rows cannot be treated as evidence of uniqueness.
        const int count=std::min(45,table->rowCount);
        for(int row=0;row<count;++row) {
            const char* token=StringTable_GetColumnValueForRow(table,row,4);
            if(!token || !*token) continue;
            Definition entry;entry.token=token;
            const char* idText=StringTable_GetColumnValueForRow(table,row,0);
            if(idText) {
                char* end=nullptr;const long id=std::strtol(idText,&end,10);
                if(end!=idText && !*end && id>=1 && id<=254) entry.id=(uint32_t)id;
            }
            const char* pairs=StringTable_GetColumnValueForRow(table,row,12);
            if(pairs) entry.compatibleWith=SplitTokens(pairs);
            definitions.push_back(std::move(entry));
        }
        sourceStatus="Attachment table rows inspected="+std::to_string(count)+"/"+
            std::to_string(table->rowCount)+" (native writer lookup range).\n";
    }
    const auto report=Inspect(weapon.script,weapon.allowed,v24Attachments,definitions);
    return "v36 attachment investigation; ZM="+std::to_string(V29ZMIndex(weapon.script))+
        ", MP="+std::to_string(V27MPIndex(weapon.script))+"\n"+sourceStatus+FormatReport(report);
}
static std::string v36AttachmentDetails;
static std::string V36CopyDetails() {
    // Refresh for the current selection; a cached report may describe another
    // weapon or an attachment combination that has since been edited.
    return v27NativeStatus+"\n\nCURRENT SELECTION (may differ from the last write):\n"+V36AttachmentReport();
}
// Native BO3 kit slot 0 is the OPTIC slot. Remaining rig attachments start
// at index 1 even when the gun has no optic, matching the retail Gunsmith layout.
// Older v33 saved kit(s) remain importable by attachment ID and may be reordered.
static bool V27BuildSafeSlots(const V24Weapon& weapon,uint32_t ids[8],uint32_t styles[8],std::string& error) {
    for(int i=0;i<8;++i){ids[i]=0;styles[i]=0;}
    if (v24Attachments.size()>8) {error="BO3 native kit has max 8 attachment slots.";return false;}
    if (v24CamoId<0 || v24CamoId>137 || !V24FindCamo(v24CamoId)) {error="Unknown camo ID.";return false;}
    int nextRigSlot=1;
    std::vector<uint32_t> selectedIds;
    for(const auto& token:v24Attachments) {
        if (!V25WeaponSupports(weapon,token)) {
            error=V24AttachmentName(token)+" is not listed for this weapon in the Zombies catalog. Gameplay compatibility is unverified; native write blocked.";return false;
        }
        uint32_t id=0;std::string pairList;
        if(!V27GetAttachmentIndex(token,id,pairList)){error="Unknown attachment ID: "+token;return false;}
        if (std::find(selectedIds.begin(),selectedIds.end(),id)!=selectedIds.end()) {
            error="Duplicate native attachment ID: "+token;return false;
        }
        selectedIds.push_back(id);
        for(const auto& other:v24Attachments) {
            if (other==token) continue;
            std::istringstream words(pairList);std::string one;bool permitted=false;
            while(words>>one) if(one==other){permitted=true;break;}
            if (!permitted) {error=V24AttachmentName(token)+" conflicts with "+V24AttachmentName(other);return false;}
        }
        int destination;
        if (V24IsOptic(token)) {
            if (ids[0]) {error="Only one native optic can use slot 0.";return false;}
            destination=0;
        } else {
            if (nextRigSlot>=8) {
                error="The native Weapon Kit reserves slot 0 for an optic; max seven other parts.";
                return false;
            }
            destination=nextRigSlot++;
        }
        ids[destination]=id;
        const auto look=v26CosmeticVariantIds.find(token);
        if (look!=v26CosmeticVariantIds.end()) {
            if (look->second<0 || look->second>8) {error="Attachment look index out of range 0-8.";return false;}
            styles[destination]=(uint32_t)look->second;
        }
    }
    return true;
}
// Use the real BO3 attachment compatibility table to extend a selected kit.
// The cap applies only to native editing; arbitrary larger drafts remain local.
static void V33FillToEight() {
    if(v24WeaponIndex<0 || v24WeaponIndex>=(int)v24Weapons.size()) return;
    const V24Weapon& weapon=v24Weapons[v24WeaponIndex];
    if(v24Attachments.size()>=8) {
        v24Message="Already at or above eight attachments. Native Apply caps at eight.";return;
    }
    const size_t before=v24Attachments.size();
    for(const auto& token:weapon.allowed) {
        if(v24Attachments.size()>=8) break;
        if(V26PrestigeToken(token) || V24Contains(v24Attachments,token)) continue;
        if(V24IsOptic(token)) {
            const bool hasOptic=std::find_if(v24Attachments.begin(),v24Attachments.end(),V24IsOptic)!=v24Attachments.end();
            if(hasOptic) continue;
        }
        v24Attachments.push_back(token);
        uint32_t ids[8]={},looks[8]={};std::string error;
        if(!V27BuildSafeSlots(weapon,ids,looks,error)) v24Attachments.pop_back();
    }
    v24Message="Added "+std::to_string(v24Attachments.size()-before)+
        " compatible native attachments ("+std::to_string(v24Attachments.size())+
        "/8 selected). Verify each before Save && Apply.";
}
// Map native DDL attachment IDs back into this game version's attachment table.
// Reverse mapping is used for importing an existing kit, NOT for inventing weapon assets.
static bool V33TokenForAttachmentId(uint32_t wanted,std::string& token) {
    StringTable* table=nullptr;
    StringTable_GetAsset("gamedata/weapons/common/attachmenttable.csv",&table);
    if (!table || table->rowCount<43 || table->rowCount>1024 || table->columnCount<13) return false;
    for (int row=1;row<std::min(45,table->rowCount);++row) {
        const char* raw=StringTable_GetColumnValueForRow(table,row,4);
        const char* n=StringTable_GetColumnValueForRow(table,row,0);
        if (!raw || !*raw || !n) continue;
        char* end=nullptr;
        const long idx=std::strtol(n,&end,10);
        if (end!=n && !*end && idx>0 && (uint32_t)idx==wanted) {
            token=raw;return true;
        }
    }
    return false;
}
// Preserve existing appearance by attachment identity, even if slots are reordered.
// A brand-new unverified style requires a separate opt-in, never silent inclusion.
static bool V33ResolveLooks(const uint32_t newIds[8],const uint32_t requestedLooks[8],
        const std::vector<uint32_t>& old,uint32_t resolved[8],std::string& why) {
    if(old.size()!=17) {why="Could not read original native kit fields.";return false;}
    for(int i=0;i<8;++i) {
        resolved[i]=0;
        if(newIds[i]==0) continue;
        uint32_t previouslyStored=0;
        for(int j=0;j<8;++j) {
            if(old[(size_t)j]==newIds[i]) {
                previouslyStored=old[(size_t)8+j];break;
            }
        }
        const uint32_t chosen=requestedLooks[i];
        if (chosen!=0 && chosen!=previouslyStored && !v33AllowUnverifiedLooks) {
            why="Look ID "+std::to_string(chosen)+" is not proven for this attachment. "
                "Enable experimental Black Market look writes to test it offline, "
                "or select Default to preserve the native appearance.";
            return false;
        }
        resolved[i]=chosen ? chosen : (v33PreserveNativeLooks ? previouslyStored : 0);
    }
    return true;
}
static std::vector<std::string> V32Path(int slot,const char* key,int sub=-1) {
    if(sub<0) return {"cacLoadouts","variant",std::to_string(slot),key};
    return {"cacLoadouts","variant",std::to_string(slot),key,std::to_string(sub)};
}
static bool V32NativeRead(DDLState* root,DDLContext* ctx,const std::vector<std::string>& p,uint32_t& v) {
    return V27Read(root,ctx,p,v);
}
static bool V32NativeSet(DDLState* root,DDLContext* ctx,const std::vector<std::string>& p,uint32_t v) {
    DDLState field{};
    if(!V27DDLState(root,p,field)) return false;
    return !!DDL_SetUInt((__int64)&field,(__int64)ctx,(int)v);
}
// Inspect every kit entry before allowing any empty-slot allocation. We never
// borrow an occupied slot and we never infer IDs from the animation-only Bowie.
static bool V36FindFreeCandidate(DDLState* root, DDLContext* ctx, int weaponId,
                                int& candidate, std::string& info) {
    candidate=-1;
    DDLState array{};
    if(!V27DDLState(root,{"cacLoadouts","variant"},array)) {info="Missing native variant array";return false;}
    const auto result=scropts::kits::FindEmptySlot((uint32_t)weaponId,
        [&](int slot) {
            DDLState item{};
            return DDL_MoveToIndex(&array,&item,slot) && item.isValid;
        },
        [&](int slot,scropts::kits::SlotMetadata& value) {
            return V32NativeRead(root,ctx,V32Path(slot,"weaponIndex"),value.weapon) &&
                   V32NativeRead(root,ctx,V32Path(slot,"variantIndex"),value.variant) &&
                   V32NativeRead(root,ctx,V32Path(slot,"sortIndex"),value.sort) &&
                   V32NativeRead(root,ctx,V32Path(slot,"readOnly"),value.readOnly) &&
                   V32NativeRead(root,ctx,V32Path(slot,"camoIndex"),value.camo) &&
                   V32NativeRead(root,ctx,V32Path(slot,"reticleIndex"),value.reticle);
        },
        [&](int slot,int part,uint32_t& attachment,uint32_t& look) {
            return V32NativeRead(root,ctx,V32Path(slot,"attachment",part),attachment) &&
                   V32NativeRead(root,ctx,V32Path(slot,"attachmentVariant",part),look);
        });
    if(result.unreadableSlot>=0) {
        info="Native slot fields unreadable at slot "+std::to_string(result.unreadableSlot);return false;
    }
    candidate=result.candidate;
    info="slots="+std::to_string(result.readable)+", matching weapon="+std::to_string(result.matchingWeapons)+
         ", clean unused="+std::to_string(result.cleanUnused)+", chosen="+std::to_string(candidate);
    return candidate>=0;
}
static bool V32Backup(DDLContext* ctx,std::string& folder,std::string& error) {
    if(!ctx || ctx->len!=13312 || !ctx->buff) {error="DDL context unavailable";return false;}
    for(int p=0;p<ctx->len;p+=1024) {
        if(!V30Readable((const unsigned char*)ctx->buff+p,(size_t)std::min(1024,ctx->len-p))) {
            error="DDL buffer not safely readable";return false;
        }
    }
    char dir[MAX_PATH]={};
    if(!GetEnvironmentVariableA("LOCALAPPDATA",dir,MAX_PATH)) {error="LOCALAPPDATA missing";return false;}
    std::string base=std::string(dir)+"\\ScroptsQOL";
    if(!CreateDirectoryA(base.c_str(),nullptr) && GetLastError()!=ERROR_ALREADY_EXISTS) {error="Backup base directory failed";return false;}
    base+="\\NativeBackup";
    if(!CreateDirectoryA(base.c_str(),nullptr) && GetLastError()!=ERROR_ALREADY_EXISTS) {error="Backup directory failed";return false;}
    SYSTEMTIME clock{};GetLocalTime(&clock);
    char stamp[72]={};sprintf_s(stamp,"v36_%04u%02u%02u_%02u%02u%02u_%03u",clock.wYear,clock.wMonth,clock.wDay,clock.wHour,clock.wMinute,clock.wSecond,clock.wMilliseconds);
    folder=base+"\\"+stamp;
    if(!CreateDirectoryA(folder.c_str(),nullptr)) {error="Backup timestamp folder failed";return false;}
    // Snapshot the exact validated 13,312-byte memory DDL before any edit.
    {
        std::ofstream snapshot(folder+"\\offline_zm_ddl_buffer_BEFORE.bin",std::ios::binary);
        if (!snapshot) {error="Couldn't create native DDL snapshot";return false;}
        snapshot.write((const char*)ctx->buff,ctx->len);
        snapshot.flush();
        if (!snapshot) {error="DDL snapshot incomplete";return false;}
    }
    // Try to copy original .cgp files for easier manual restoration.
    char path[MAX_PATH]={};
    if(GetModuleFileNameA(nullptr,path,MAX_PATH)) {
        std::string game(path);auto pos=game.find_last_of("\\/");
        if(pos!=std::string::npos) {
            game.resize(pos);
            for(int k=0;k<2;++k) {
                std::string file="loadouts_zm_offline_"+std::to_string(k)+".cgp";
                std::string src=game+"\\players\\311210\\"+file;
                if(GetFileAttributesA(src.c_str())!=INVALID_FILE_ATTRIBUTES)
                    CopyFileA(src.c_str(),(folder+"\\"+file).c_str(),TRUE);
            }
        }
    }
    return true;
}
// Keep the verified engine API and field layout; fail closed if storage changes
// while taking the diagnostic backup or performing the native transaction.
static bool V36ContextUnchanged(DDLState* root, DDLContext* ctx, const void* buffer,
                               std::string& reason) {
    DDLState* currentRoot=nullptr;DDLContext* currentContext=nullptr;
    if(!V32GetOffline(currentRoot,currentContext,reason)) return false;
    if(currentRoot!=root || currentContext!=ctx || currentContext->buff!=buffer) {
        reason="The offline storage context changed while taking the snapshot.";
        return false;
    }
    return true;
}
static bool V36WriteFields(DDLState* root, DDLContext* ctx, int slot, int zm,
                          const std::vector<std::vector<std::string>>& keys,
                          const std::vector<uint32_t>& updates,
                          const std::vector<uint32_t>& previous,
                          const std::string& backup) {
    const void* buffer = ctx->buff;
    const void* definition = root->ddlDef;
    const bool creating = !keys.empty() && keys.back()==V32Path(slot,"weaponIndex");
    const auto contextValid = [&]() {
        DDLState* currentRoot=nullptr;DDLContext* currentContext=nullptr;std::string why;
        if(v36NativeWritesSuspended || !V32GetOffline(currentRoot,currentContext,why) ||
           currentRoot!=root || currentContext!=ctx || currentContext->buff!=buffer ||
           currentRoot->ddlDef!=definition) return false;
        uint32_t weapon=0,variant=0,readOnly=0;
        // Never write or roll back into a slot which now belongs to a different
        // weapon. During creation weaponIndex changes from zero to zm last.
        return V32NativeRead(root,ctx,V32Path(slot,"weaponIndex"),weapon) &&
               (weapon==(uint32_t)zm || (creating && weapon==0)) &&
               V32NativeRead(root,ctx,V32Path(slot,"variantIndex"),variant) && variant==(uint32_t)slot &&
               V32NativeRead(root,ctx,V32Path(slot,"readOnly"),readOnly) && readOnly==0;
    };
    const auto identityValid = [&]() {
        std::string why;uint32_t variant=0,readOnly=0;
        return V32ScanSlot(root,ctx,zm,why)==slot &&
               V32NativeRead(root,ctx,V32Path(slot,"variantIndex"),variant) && variant==(uint32_t)slot &&
               V32NativeRead(root,ctx,V32Path(slot,"readOnly"),readOnly) && readOnly==0;
    };
    const auto result = scropts::kits::ExecuteWrite(previous,updates,
        [&](size_t i,uint32_t& value) {return V32NativeRead(root,ctx,keys[i],value);},
        [&](size_t i,uint32_t value) {return V32NativeSet(root,ctx,keys[i],value);},
        contextValid,identityValid,
        [&]() {return contextValid() && !!Storage_Write(0,v32VerifiedOfflineFile,0);});
    using scropts::kits::WriteStatus;
    if(result.status==WriteStatus::Committed) return true;
    if(result.persistenceAttempted || (result.attempted && !result.rollbackVerified))
        v36NativeWritesSuspended=true;
    switch(result.status) {
        case WriteStatus::PreconditionChanged:
            v27NativeStatus="WRITE BLOCKED: offline context or native fields changed after the snapshot. ";break;
        case WriteStatus::FieldWriteFailed:
            v27NativeStatus="WRITE FAILED: native field write/readback mismatch. ";break;
        case WriteStatus::IdentityChanged:
            v27NativeStatus="WRITE FAILED: kit identity changed before persistence. ";break;
        case WriteStatus::PersistFailed:
            v27NativeStatus="WRITE FAILED: Storage_Write(0x14) returned false; disk state is unknown. ";break;
        default:
            v27NativeStatus="WRITE FAILED: Storage_Write accepted the request, but post-call verification failed; disk state is unknown. ";break;
    }
    if(!result.attempted) v27NativeStatus+="No fields written. ";
    else if(result.status!=WriteStatus::PostPersistMismatch)
        v27NativeStatus+=result.rollbackVerified ? "In-memory rollback verified. " : "In-memory rollback could not be verified. ";
    if(v36NativeWritesSuspended)
        v27NativeStatus+="Further writes disabled until BO3 restarts. Check your profile and recover the external players backup if needed. ";
    v27NativeStatus+="Diagnostic snapshot: "+backup;
    return false;
}
// v33: import exactly what BO3 currently saved before extending a kit to 6-8 parts.
// The entire import is read-only and atomic with respect to the editor state.
static void V33ImportCurrentNativeKit() {
    if(v24WeaponIndex<0 || v24WeaponIndex>=(int)v24Weapons.size()) {
        v27NativeStatus="Select a weapon first.";return;
    }
    const auto& w=v24Weapons[v24WeaponIndex];
    const int zm=V29ZMIndex(w.script),mp=V27MPIndex(w.script);
    if(v27NativeSlot<0 || v32ProbedWeapon!=w.script || zm!=v32ProbedZMId ||
       zm!=mp || mp!=v27NativeMPId) {
        v27NativeStatus="Import BLOCKED: Check Native Kit for this weapon first.";return;
    }
    DDLState* root=nullptr;DDLContext* ctx=nullptr;std::string why;
    if(!V32GetOffline(root,ctx,why)) {v27NativeStatus="Import BLOCKED: "+why;return;}
    const int slot=V32ScanSlot(root,ctx,zm,why);
    if(slot!=v27NativeSlot) {v27NativeStatus="Import BLOCKED: kit slot changed/ambiguous. "+why;return;}
    uint32_t storedVariant=0,storedWeapon=0,storedCamo=0;
    if(!V32NativeRead(root,ctx,V32Path(slot,"variantIndex"),storedVariant) ||
       storedVariant!=(uint32_t)slot ||
       !V32NativeRead(root,ctx,V32Path(slot,"weaponIndex"),storedWeapon) ||
       storedWeapon!=(uint32_t)zm ||
       !V32NativeRead(root,ctx,V32Path(slot,"camoIndex"),storedCamo) ||
       storedCamo>137 || !V24FindCamo((int)storedCamo)) {
        v27NativeStatus="Import BLOCKED: slot or camo failed verification.";return;
    }
    std::vector<std::string> tokens;
    std::unordered_map<std::string,int> looks;
    int uncommonLooks=0;
    for(int i=0;i<8;++i) {
        uint32_t id=0,look=0;
        if(!V32NativeRead(root,ctx,V32Path(slot,"attachment",i),id) ||
           !V32NativeRead(root,ctx,V32Path(slot,"attachmentVariant",i),look)) {
            v27NativeStatus="Import BLOCKED: attachment/cosmetic slot unreadable; editor unchanged.";return;
        }
        if(id==0) continue;
        std::string token;
        if(!V33TokenForAttachmentId(id,token) || V24Contains(tokens,token)) {
            v27NativeStatus="Import BLOCKED: unknown/duplicate native attachment ID "+std::to_string(id)+
                "; editor unchanged.";return;
        }
        tokens.push_back(token);
        if(look>0 && look<=8) looks[token]=(int)look;
        else if(look>8) ++uncommonLooks; // preserved by v33's native look resolver
    }
    v24Attachments=std::move(tokens);
    v26CosmeticVariantIds=std::move(looks);
    v24CamoId=(int)storedCamo;
    v24Message="Imported saved native kit into editor. Add supported attachments, then Save && Apply.";
    v27NativeStatus="READ-ONLY imported "+w.display+" from native kit slot "+std::to_string(slot)+
        ": "+std::to_string(v24Attachments.size())+" attachments, camo "+std::to_string(storedCamo)+
        (uncommonLooks ? "; "+std::to_string(uncommonLooks)+" out-of-range native cosmetic IDs will be preserved when possible." : ".")+
        " Save Local Preset to keep a separate draft, or Save && Apply to edit BO3 offline.";
}
static void V27NativeApply() {
    if(!v27WritesConfirmed) {v27NativeStatus="Blocked: check the backup/experimental write confirmation first.";return;}
    if(v24WeaponIndex<0 || v24WeaponIndex>=(int)v24Weapons.size()) {v27NativeStatus="Select a weapon.";return;}
    const auto& w=v24Weapons[v24WeaponIndex];
    const int zm=V29ZMIndex(w.script),mp=V27MPIndex(w.script);
    if(v27NativeSlot<0 || v32ProbedWeapon!=w.script || zm!=v32ProbedZMId || zm!=mp || mp!=v27NativeMPId) {
        v27NativeStatus="Blocked: click Check Native Kit for THIS weapon before applying.";return;
    }
    uint32_t ids[8]={}, looks[8]={};std::string reason;
    if(!V27BuildSafeSlots(w,ids,looks,reason)) {v27NativeStatus="Blocked: "+reason;return;}
    DDLState* root=nullptr;DDLContext* ctx=nullptr;
    if(!V32GetOffline(root,ctx,reason)){v27NativeStatus="Blocked: "+reason;return;}
    const int freshSlot=V32ScanSlot(root,ctx,zm,reason);
    if(freshSlot!=v27NativeSlot){v27NativeStatus="Blocked: kit slot changed/ambiguous. Recheck. "+reason;v27NativeSlot=-1;return;}
    uint32_t variant=0,readOnly=0;
    if(!V32NativeRead(root,ctx,V32Path(freshSlot,"variantIndex"),variant) || variant!=(uint32_t)freshSlot ||
       !V32NativeRead(root,ctx,V32Path(freshSlot,"readOnly"),readOnly) || readOnly!=0) {
        v27NativeStatus="Native variant identity/readOnly check failed. No write.";return;
    }
    std::vector<std::vector<std::string>> keys;std::vector<uint32_t> updates,old;
    for(int i=0;i<8;++i){keys.push_back(V32Path(freshSlot,"attachment",i));updates.push_back(ids[i]);}
    for(int i=0;i<8;++i){keys.push_back(V32Path(freshSlot,"attachmentVariant",i));updates.push_back(looks[i]);}
    keys.push_back(V32Path(freshSlot,"camoIndex"));updates.push_back((uint32_t)v24CamoId);
    for(const auto& key:keys){uint32_t v=0;if(!V32NativeRead(root,ctx,key,v)){v27NativeStatus="Native attachment/camo schema unexpected; NO CHANGES.";return;}old.push_back(v);}
    uint32_t resolvedLooks[8]={};
    if(!V33ResolveLooks(ids,looks,old,resolvedLooks,reason)) {
        v27NativeStatus="Blocked: "+reason;return;
    }
    for(int i=0;i<8;++i) updates[(size_t)8+i]=resolvedLooks[i];
    std::string backup;
    const void* backupBuffer=ctx->buff;
    if(!V32Backup(ctx,backup,reason)){v27NativeStatus="Backup FAILED; no write: "+reason;return;}
    // Recheck identity after the backup, immediately before changing fields.
    if(!V36ContextUnchanged(root,ctx,backupBuffer,reason)) {
        v27NativeStatus="WRITE BLOCKED: "+reason;return;
    }
    if(V32ScanSlot(root,ctx,zm,reason)!=freshSlot) {
        v27NativeStatus="WRITE BLOCKED: native slot changed after snapshot. No fields written.";return;
    }
    if(!V36WriteFields(root,ctx,freshSlot,zm,keys,updates,old,backup)) return;
    v27NativeStatus="BO3 Storage_Write(0x14) returned success for "+w.display+
        " (native slot "+std::to_string(freshSlot)+", "+
        std::to_string(v24Attachments.size())+" attachments). Post-call in-memory readback=MATCH."+
        " Reopen Zombies Weapon Kits and restart BO3 to VERIFY persistence; not yet verified. Backup: "+backup;
}
// Allocate a missing ordinary firearm kit from the unified Save & Apply action.
// A verified empty slot and external players backup are still mandatory.
// Field rollback restores memory only; it cannot prove restoration of disk data.
static void V36CreateMissingKit() {
    if (!v27WritesConfirmed || v36NativeWritesSuspended) {
        v27NativeStatus="CREATE BLOCKED: confirm the offline backup; writes must not be suspended.";return;
    }
    if(v24WeaponIndex<0 || v24WeaponIndex>=(int)v24Weapons.size() || v36PreparedEmptySlot<0) {
        v27NativeStatus="CREATE BLOCKED: no verified unused slot. Click Check Kit first.";return;
    }
    const auto& weapon=v24Weapons[v24WeaponIndex];
    const int zm=V29ZMIndex(weapon.script), mp=V27MPIndex(weapon.script);
    if(!V36CanCreateFor(weapon,zm,mp) ||
       v36PreparedWeapon!=weapon.script || v36PreparedZM!=zm) {
        v27NativeStatus="CREATE BLOCKED: weapon is not an eligible base firearm or selection changed.";return;
    }
    uint32_t ids[8]={},looks[8]={};std::string reason;
    if(!V27BuildSafeSlots(weapon,ids,looks,reason)){v27NativeStatus="CREATE BLOCKED: "+reason;return;}
    for(int i=0;i<8;++i) if(looks[i]!=0) {
        v27NativeStatus="CREATE BLOCKED: initialize the kit with Default cosmetic Look IDs only.";return;
    }
    DDLState* root=nullptr;DDLContext* ctx=nullptr;
    if(!V32GetOffline(root,ctx,reason)) {v27NativeStatus="CREATE BLOCKED: "+reason;return;}
    int slot=-1;
    if(!V36FindFreeCandidate(root,ctx,zm,slot,reason) || slot!=v36PreparedEmptySlot) {
        v36PreparedEmptySlot=-1;
        v27NativeStatus="CREATE BLOCKED: free slot changed or became occupied; Check Native Kit again. "+reason;return;
    }
    // Fresh DDL read on all affected fields BEFORE backup or writes.
    std::vector<std::vector<std::string>> keys;
    std::vector<uint32_t> updates,previous;
    keys.push_back(V32Path(slot,"variantIndex")); updates.push_back((uint32_t)slot);
    keys.push_back(V32Path(slot,"sortIndex")); updates.push_back(1);
    for(int i=0;i<8;++i) {keys.push_back(V32Path(slot,"attachment",i));updates.push_back(ids[i]);}
    for(int i=0;i<8;++i) {keys.push_back(V32Path(slot,"attachmentVariant",i));updates.push_back(0);}
    keys.push_back(V32Path(slot,"camoIndex"));updates.push_back((uint32_t)v24CamoId);
    // Commit weaponIndex LAST so a partially edited in-memory entry cannot
    // masquerade as an occupied gun slot before all other fields succeed.
    keys.push_back(V32Path(slot,"weaponIndex"));updates.push_back((uint32_t)zm);
    for(const auto& key:keys) {
        uint32_t v=0;
        if(!V32NativeRead(root,ctx,key,v)) {v27NativeStatus="CREATE BLOCKED: slot field unreadable. Nothing changed.";return;}
        previous.push_back(v);
    }
    if(previous.back()!=0 || previous[0]!=(uint32_t)slot || previous[1]!=0) {
        v27NativeStatus="CREATE BLOCKED: candidate metadata changed. Nothing changed.";return;
    }
    std::string backup;
    const void* backupBuffer=ctx->buff;
    if(!V32Backup(ctx,backup,reason)){v27NativeStatus="CREATE BLOCKED: snapshot failed. "+reason;return;}
    // Recheck the complete empty slot, including untouched reticle/readOnly,
    // after backup I/O. Never use a stale free-slot decision.
    if(!V36ContextUnchanged(root,ctx,backupBuffer,reason)) {
        v27NativeStatus="CREATE BLOCKED: "+reason;return;
    }
    int refreshed=-1;
    if(!V36FindFreeCandidate(root,ctx,zm,refreshed,reason) || refreshed!=slot) {
        v36PreparedEmptySlot=-1;
        v27NativeStatus="CREATE BLOCKED: candidate changed after snapshot. No fields written. "+reason;return;
    }
    if(!V36WriteFields(root,ctx,slot,zm,keys,updates,previous,backup)) return;
    v36PreparedEmptySlot=-1;
    v27NativeSlot=slot;v27NativeMPId=mp;v32ProbedZMId=zm;v32ProbedWeapon=weapon.script;
    v27NativeStatus="BO3 Storage_Write reported success creating "+weapon.display+" in offline native slot "+
        std::to_string(slot)+" ("+std::to_string(v24Attachments.size())+
        " attachments, camo "+std::to_string(v24CamoId)+"). "+
        "In-memory verification passed; OPEN WEAPON KITS AND RESTART BO3 to check actual persistence. "
        "New-kit gameplay and persistence still need runtime verification. Backup: "+backup;
}
// Single primary action; uses a fresh read-only probe every time. Existing
// verified slots use the previously successful v32 writer. Creating a missing
// firearm kit is automatic only when every eligibility and empty-slot check passes.
static void V36SaveOrCreate() {
    if (v36NativeWritesSuspended) {
        v27NativeStatus="Save BLOCKED: a previous write could not be verified. Restart BO3 and check/recover your players backup before continuing.";return;
    }
    if (!v27WritesConfirmed) {
        v27NativeStatus="Save blocked: confirm offline write/backup first.";return;
    }
    V27NativeProbe();
    if (v27NativeSlot>=0) {
        V27NativeApply();
    } else if (v36PreparedEmptySlot>=0) {
        V36CreateMissingKit();
    }
    // Otherwise leave probe's detailed refusal message intact.
}
static std::string V36ShortStatus() {
    if(v27NativeStatus.find("Blocked")!=std::string::npos ||
       v27NativeStatus.find("blocked")!=std::string::npos ||
       v27NativeStatus.find("BLOCKED")!=std::string::npos ||
       v27NativeStatus.find("FAILED")!=std::string::npos ||
       v27NativeStatus.find("failed")!=std::string::npos) {
        const size_t n=std::min<size_t>(154,v27NativeStatus.size());
        return v27NativeStatus.substr(0,n)+(v27NativeStatus.size()>n?"... [Copy Details]":"");
    }
    if(v27NativeStatus.find("returned success")!=std::string::npos ||
       v27NativeStatus.find("reported success")!=std::string::npos)
        return "Game accepted write; reopen Weapon Kits and restart to verify persistence.";
    if(v27NativeStatus.find("EXACT SINGLE ENTRY VERIFIED")!=std::string::npos)
        return "Existing native kit found. Save & Apply will update it offline.";
    if(v27NativeStatus.find("CREATE AVAILABLE")!=std::string::npos)
        return "Missing kit: Save & Apply will create it in a verified unused slot.";
    if(v27NativeStatus.find("No unique verified native kit entry")!=std::string::npos)
        return "No writable kit found. See Copy Details for eligibility and empty-slot information.";
    return "Use Copy Details for complete native kit report.";
}
static void V24DrawWeaponKits() {
    if (!open) return;
    ImGui::SetNextWindowSize(ImVec2(1080.0f, 655.0f),ImGuiCond_Once);
    ImGui::Begin("Scropts QOL - Zombies Weapon Kits v36 [OFFLINE]", &open);
    ImGui::TextUnformatted("ZOMBIES WEAPON KITS");
    ImGui::SameLine(); ImGui::TextDisabled("Offline | 8 native slots | backups before writes");
    // Keep the everyday workflow obvious and ABOVE scrolling attachment lists.
    if(ImGui::Button("Scan Weapons")) V24Scan();
    ImGui::SameLine();if(ImGui::Button("Check Kit")) V27NativeProbe();
    ImGui::SameLine();if(ImGui::Button("Load Saved Kit")) V33ImportCurrentNativeKit();
    ImGui::SameLine();if(ImGui::Button("Save & Apply (offline)")) V36SaveOrCreate();
    ImGui::SameLine();if(ImGui::Button("Copy Details")) {
        const std::string details=V36CopyDetails();ImGui::SetClipboardText(details.c_str());
    }
    ImGui::Checkbox("I've backed up my players folder; allow OFFLINE writes", &v27WritesConfirmed);
    ImGui::TextDisabled("Save & Apply checks the kit automatically: update existing, or create in a verified empty slot.");
    ImGui::TextWrapped("%s",V36ShortStatus().c_str());
    ImGui::Separator();

    ImGui::SetNextItemWidth(165.0f);
    ImGui::Combo("##v36_visibility", &v24ListFilter,"All Weapons\0Normal\0Hidden / DLC\0\0");
    ImGui::SameLine();ImGui::SetNextItemWidth(290.0f);
    ImGui::InputTextWithHint("##v24WeaponSearch","Search weapon...",v24WeaponSearch,sizeof(v24WeaponSearch));

    const float contentHeight = 380.0f;
    ImGui::BeginChild("##v24WeaponList",ImVec2(270.0f,contentHeight),true);
    for (size_t i=0; i<v24Weapons.size(); ++i) {
        const auto& w=v24Weapons[i];
        if(v24ListFilter==1 && w.hidden) continue;
        if(v24ListFilter==2 && !w.hidden) continue;
        if(!V24Matches(w.display+" "+w.script,v24WeaponSearch)) continue;
        const std::string display=w.display+(w.hidden?" [H]":"")+"##"+w.script;
        if(ImGui::Selectable(display.c_str(),v24WeaponIndex==(int)i)) {
            v24WeaponIndex=(int)i;
            v27NativeSlot=-1;v36PreparedEmptySlot=-1;
            v36PreparedWeapon.clear();v36PreparedZM=-1;
            v27NativeStatus="Weapon changed. Save & Apply will check the native kit automatically.";
            V24LoadPreset();
        }
    }
    ImGui::EndChild();ImGui::SameLine();
    ImGui::BeginChild("##v24Attachments",ImVec2(375.0f,contentHeight),true);
    if(v24WeaponIndex>=0 && v24WeaponIndex<(int)v24Weapons.size()) {
        const auto& w=v24Weapons[v24WeaponIndex];
        ImGui::Text("%s",w.display.c_str());
        ImGui::TextDisabled("%s | %d/8 selected",w.script.c_str(),(int)v24Attachments.size());
        if(ImGui::Button("Fill to 8")) V33FillToEight();
        ImGui::SameLine();if(ImGui::Button("Clear")) {v24Attachments.clear();v26CosmeticVariantIds.clear();}
        ImGui::Separator();
        const auto& choices = v25ShowAllAttachmentOptions ? v25AllAttachments : w.allowed;
        if(w.allowed.empty()) ImGui::TextDisabled("No standard attachments for this weapon.");
        for(const auto& a:choices) {
            if(V26PrestigeToken(a)) continue;
            bool selected=V24Contains(v24Attachments,a);
            const std::string label=V24AttachmentName(a)+"##v36_"+a;
            if(ImGui::Checkbox(label.c_str(),&selected)) V24ChooseAttachment(a,selected);
            if(!V25WeaponSupports(w,a)) {
                ImGui::SameLine();ImGui::TextDisabled("(?)");
                if(ImGui::IsItemHovered()) ImGui::SetTooltip("Not listed in this weapon's Zombies catalog. Gameplay compatibility is unverified; native apply will refuse it.");
            }
            if(selected && v36ShowCosmeticSelectors) {
                ImGui::SameLine(222.0f);ImGui::SetNextItemWidth(128.0f);
                int look=0;
                auto prev=v26CosmeticVariantIds.find(a);
                if(prev!=v26CosmeticVariantIds.end()) look=prev->second;
                if(ImGui::Combo(("##v36_style_"+a).c_str(),&look,v26VariantLabels)) {
                    if(!look) v26CosmeticVariantIds.erase(a);
                    else v26CosmeticVariantIds[a]=look;
                }
                if(ImGui::IsItemHovered()) ImGui::SetTooltip("Unverified appearance ID for this attachment; not all styles exist in Zombies.");
            }
        }
    } else ImGui::TextDisabled("Select a Zombies weapon.");
    ImGui::EndChild();ImGui::SameLine();
    ImGui::BeginChild("##v24CamoList",ImVec2(0,contentHeight),true);
    const V24Camo* chosen=V24FindCamo(v24CamoId);
    ImGui::Text("CAMO: %s",chosen?chosen->display.c_str():"None");
    ImGui::SetNextItemWidth(-1.0f);
    ImGui::InputTextWithHint("##v24CamoSearch","Search camo...",v24CamoSearch,sizeof(v24CamoSearch));
    ImGui::Separator();
    for(const auto& camo:v24Camos) {
        if(!V24Matches(camo.display+" "+camo.script+" "+camo.group,v24CamoSearch)) continue;
        const std::string label=camo.display+"##camo"+std::to_string(camo.id);
        if(ImGui::Selectable(label.c_str(),v24CamoId==camo.id)) v24CamoId=camo.id;
    }
    ImGui::EndChild();
    if(ImGui::CollapsingHeader("Advanced: cosmetics, presets & troubleshooting")) {
        ImGui::Checkbox("Show unsupported attachment types (draft only)",&v25ShowAllAttachmentOptions);
        ImGui::Checkbox("Show Black Market Look ID selectors",&v36ShowCosmeticSelectors);
        ImGui::Checkbox("Preserve saved Black Market looks",&v33PreserveNativeLooks);
        ImGui::Checkbox("Allow NEW unverified Black Market look IDs (experimental)",&v33AllowUnverifiedLooks);
        int prestige=V26PrestigeChoice();
        ImGui::SetNextItemWidth(165.0f);
        if(ImGui::Combo("Prestige (unverified in Zombies)",&prestige,
                "None\0Clan Tag\0Kill Counter\0Both\0\0")) V26SetPrestigeChoice(prestige);
        if(ImGui::Button("Save Local Draft")) V24SavePreset();
        ImGui::SameLine();if(ImGui::Button("Reload Draft")) V24LoadPreset();
        if(ImGui::Button("Inspect attachment compatibility")) v36AttachmentDetails=V36AttachmentReport();
        ImGui::SameLine();if(ImGui::Button("Copy attachment report")) {
            v36AttachmentDetails=V36AttachmentReport();ImGui::SetClipboardText(v36AttachmentDetails.c_str());
        }
        if(!v36AttachmentDetails.empty()) {
            ImGui::TextDisabled("Last inspection; refresh after changing the selection.");
            ImGui::TextWrapped("%s",v36AttachmentDetails.c_str());
        }
        ImGui::TextWrapped("Details: %s",v27NativeStatus.c_str());
        ImGui::TextDisabled("Offline only. Unsupported assets and melee kits are never force-written. Native creation is untested; always verify after restart.");
    }
    ImGui::End();
}
