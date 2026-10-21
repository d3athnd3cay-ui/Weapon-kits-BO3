# Scropts QOL v35 — cleaner F5 Weapon Kits + missing firearm kit pilot

User-confirmed: v32 205 Brecci writes and persists after restart; v33 8 attachments write and persist; v34 screenshot shows Kuda wrote successfully. Argus native kit exists in slot 5; 48 Dredge native kit absent but a free variant slot was found. Bowie Knife is not a verified standard kit.

## What's different

- Compact top row: **Scan Weapons / Check Kit / Load Saved Kit / Save & Apply (offline) / Copy Details**.
- One visible checkbox to confirm BO3 players folder was backed up and offline writing is allowed.
- **Save & Apply** now calls a fresh **Check Kit** automatically; existing kits use the previously verified writer. When a base firearm has no kit entry, it identifies a **strictly empty slot** and requires the separate **Create a new kit in an empty slot (EXPERIMENTAL)** checkbox. Clicking Save & Apply again (with both checkboxes) runs the experimental creator.
- Missing-kit creation is available only to ordinary base firearms: assault rifles, SMGs, LMGs, snipers, shotguns, and pistols, with nonempty native attachment lists and exactly matching Zombies/Multiplayer weapon IDs. Bowie, flourish and melee items remain excluded.
- Attachment/camo selectors remain visible. Cosmetics, experimental unsupported-attachment drafts, local presets, and full diagnostics are in a collapsed Advanced area. Black Market Look ID selectors display only if enabled.
- Native optic is reserved in slot zero; remaining seven attachment slots are for other native-compatible attachments.

## Suggested test sequence

1. Exit BO3. BACK UP its entire `players` folder to a separate location. This backup is the ONLY dependable restoration method.
2. Extract ZIP, run `RUN_BUILD_V35_KITS.bat` in Windows with MSVC C++ build tools. Do not load multiple DLL versions.
3. Go to **offline Zombies**, open F5, select **Argus**. Press Check Kit; expect one verified existing slot (as in v34). Choose an ordinary camo; confirm external backup; click Save & Apply. Read **Details** and verify persistence after restart.
4. To try **48 Dredge**: select it, choose stock compatible parts, Check Kit. If an **empty slot available** line appears, check both backup and **Create a new kit**; press **Save & Apply (offline)**. Do not create another kit until the first creation has been verified after restarting BO3.
5. If anything fails, send the exact **Copy Details** result plus what happened in BO3. Native Save & Apply is not a cloud upload.

**Limitations and warnings:** Creating previously absent kits has not been runtime-tested. Native DDL is 0x14 (13,312 bytes) on the game build already probed. The program checks its type and the selected item before each write; successful in-memory readback alone is not proof of persistence. The 13,312-byte snapshot in LocalAppData is a diagnostic backup, not an automatic restore. Never use online Zombies with the native writer. Bowie Knife and `bowie_flourish` cannot be treated as ordinary gun kits and are blocked. Unsupported suppressors, prestige elements, and arbitrary Black Market Look IDs are not confirmed to work in gameplay. Generated builder sources are not a prebuilt or runtime-tested Windows DLL.
