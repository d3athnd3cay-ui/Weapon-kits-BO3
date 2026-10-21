# Attachment compatibility investigation for v36

Status: unsupported Suppressor gameplay is **unresolved**. The imported v35
writer persists normal attachments and camos according to the user's confirmed
BO3 tests. This investigation does not invalidate that baseline. No Windows/BO3
session or proprietary weapon asset data is available in the cloud workspace.

## What the source actually proves

The primary source is `SourcePatches/ZombiesKitUI.v35.inc` from the supplied ZIP.
The older upstream source was inspected only to understand the engine interfaces
that the v35 build uses: `Scroptss/Scropts-QOL` commit
`bbd4a19cead88372bb227d489a84d32c86a30e60`.

| Evidence | Meaning | What it does not establish |
| --- | --- | --- |
| `V24Scan` reads column 8 of `gamedata/stats/zm/zm_statstable.csv` | Tokens listed for each Zombies weapon in the loaded catalog | Whether a combination omitted from this catalog has functional weapon assets |
| `V25WeaponSupports` checks membership in that list | The writer's current per-weapon allow rule | Actual engine-level compatibility of an unlisted attachment |
| `V27GetAttachmentIndex` reads columns 0, 4 and 12 of `gamedata/weapons/common/attachmenttable.csv` | Global attachment ID, token and declared pair compatibility | A loaded, functioning Suppressor for a particular weapon |
| `V27BuildSafeSlots` checks both catalog membership and attachment pairs | A conservative native write plan with an optic slot and seven other slots | Firing behavior, sound, muzzle effects or handling |
| The token `suppressed` is always offered in the optional global selector | A local draft can express a Suppressor request even when the global catalog omits it | Proof that even a valid global Suppressor ID exists in that build |
| Native DDL readback and restart persistence | Stored kit values survived | That gameplay consumed those values or used the intended attachment |

The v35 wording “isn't supported by this gun's original asset” is stronger than
its evidence: the check only inspects catalog membership. v36 reports that an
attachment is *not listed in the Zombies catalog* and that its gameplay
compatibility remains unverified.

The pinned upstream `common.h` exposes unlockable/menu enumeration functions
(`BG_UnlockablesGetNumItemAttachments`, `BG_UnlockablesGetItemAttachment`) and
restriction queries. Its `Variant` structure in `structs.h` contains stored kit
fields. The inspected source does not provide a validated weapon-definition
layout, attachment-asset layout, or resolver for an equipped weapon with a
particular attachment combination. Calling additional menu functions cannot
substitute for verifying that resolver and the loaded assets.

## Implementation boundary

Keep the existing catalog, ID and pair-compatibility checks for native writes.
Do not silently remove an unsupported selected attachment and then report that
Save & Apply applied the requested kit. Do not relax the check merely because
`attachmenttable.csv` contains the numeric ID. An unknown, contradictory or
unverified combination must produce a useful diagnostic rather than an
unsubstantiated success report.

`SourcePatches/AttachmentCompatibility.v36.h` implements the read-only metadata
classifier and report formatter; `tests/attachment_compatibility_tests.cpp`
exercises 13 behavioral cases on C++17. Its report records attachment tokens,
catalog membership, global IDs, duplicate or ambiguous identities, directed pair
checks, and an explicit unverified gameplay result. It performs no engine calls
and authorizes no writes. The UI supplies current catalog data. An investigation
record should include:

- selected weapon script and Zombies/Multiplayer item IDs;
- selected attachment tokens, their global IDs, and whether the weapon's Zombies
  catalog lists them;
- both directions of the attachment pair checks and unresolved/duplicate IDs;
- the exact blocker for a native write;
- a separate `gameplay compatibility: unverified` result.

This report is diagnostic evidence. It must never act as an allowlist override.
Existing kit writes should continue to use the proven storage file and schema,
retain eight-slot behavior, preserve camos and existing cosmetic variants, and
remain offline with the existing backup confirmation.

## What an actual Suppressor fix needs

There are at least two distinct possibilities, which the supplied source cannot
distinguish:

1. The assets and runtime combination exist, but the menu/catalog excludes them.
   A narrowly scoped compatibility extension could then be appropriate after the
   resolver and the gameplay result have been verified for that exact weapon.
2. The weapon does not have the required attachment definition, models, sound or
   behavior assets. Persisting an ID cannot manufacture those assets. A genuine
   implementation would need compatible content and a supported loading path,
   potentially a BO3 Mod Tools project in addition to this DLL.

Before adding any new engine call, verify its signature and executable-version
mapping, the weapon/attachment data layout, ownership/lifetime, and the active
map's loaded asset set. Do not guess addresses or mutate global weapon assets
based on another weapon's structure. Preserve the existing build fingerprint
check. A newly discovered interface must be independently validated on every
supported executable build.

## Windows/BO3 acceptance test

Use offline Zombies and an external backup of the complete `players` folder.
Record the executable fingerprint, map, DLL SHA256, weapon script, attachment
IDs, kit slot and combination. Load only one DLL version.

1. Establish a supported control using a weapon whose current Zombies catalog
   lists `suppressed`. Test without the attachment, then with it, using the same
   map and weapon acquisition path. Record the actual expected sound, muzzle
   effects and any documented gameplay-property changes for that weapon.
2. Select the requested weapon whose current catalog omits `suppressed`. Capture
   its compatibility report. The present implementation should reject the
   native write while leaving the kit unchanged. This is a guard test, not a
   successful unsupported-Suppressor test.
3. Once a verified runtime resolver/content implementation exists, inspect the
   resolved equipped weapon and attachment state for that exact candidate. Check
   for missing/default assets and fallback to an unsuppressed weapon. A menu
   label, stored ID or inventory icon alone cannot pass this step.
4. Enter a match, obtain the weapon through its normal Zombies acquisition path,
   and fire, aim, reload and switch weapons. Compare the supported control and
   candidate against their unsuppressed baselines. Record audiovisual effects
   separately from gameplay properties; a changed firing sound alone is not
   proof that all intended behavior is active.
5. Repeat with the intended combination of other attachments. Exercise map
   reload, a complete game restart, weapon reacquisition and, where applicable,
   Pack-a-Punch/weapon replacement. Those paths can resolve different assets.
6. Recheck saved kit fields and runtime behavior after restart, then remove the
   Suppressor and verify the original behavior is restored. Re-run normal
   attachment, camo, cosmetic preservation and eight-slot regression cases.

Record each stage as passed, failed or unrun. Unsupported Suppressor support
must remain unresolved until both runtime resolution and gameplay checks pass.
No such runtime test was executed in this Linux cloud environment.
