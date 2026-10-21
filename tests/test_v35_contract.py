import unittest
from pathlib import Path
P=Path(__file__).resolve().parents[1]
S=(P/'SourcePatches/ZombiesKitUI.v35.inc').read_text()
B=(P/'Build-Audited-Scropts.ps1').read_text()
class TestV35(unittest.TestCase):
 def test_offline_storage_schema(self):
  self.assertIn('v32VerifiedOfflineFile = 0x14', S)
  self.assertIn('zm_loadouts_offline.ddl',S)
  self.assertIn('ctx->len!=13312',S)
  self.assertIn('!Com_SessionMode_IsOnlineGame()',S)
 def test_compatibility_required(self):
  gate=S[S.index('static bool V35CanCreateFor'):S.index('// BO3 Lua uses',S.index('static bool V35CanCreateFor'))]
  self.assertIn('zm != mp',gate)
  self.assertIn('w.allowed.empty()',gate)
  self.assertIn('w.group == "weapon_cqb"',gate)
  self.assertIn('w.group == "weapon_lmg"',gate)
  self.assertIn('w.script.find("knife")',gate)
  self.assertIn('w.script.find("flourish")',gate)
 def test_strict_free_slot(self):
  part=S[S.index('static bool V35FindFreeCandidate(',S.index('static bool V32NativeSet(')):S.index('static bool V32Backup(')]
  for fragment in ('readable!=50 || count!=0 || candidate<0','weapon!=0','sort!=0','readOnly!=0','camo!=0','reticle!=0','variant!=(uint32_t)slot','attachmentVariant'):
   self.assertIn(fragment,part)
 def test_create_confirmed_and_last_weapon_index(self):
  part=S[S.index('static void V35CreateMissingKit()'):S.index('// Single primary action')]
  self.assertIn('!v27WritesConfirmed || !v35ConfirmCreate',part)
  self.assertIn('V35CanCreateFor(weapon,zm,mp)',part)
  self.assertIn('V32Backup(ctx,backup,reason)',part)
  self.assertLess(part.index('V32Backup(ctx,backup,reason)'),part.index('V32NativeSet(root,ctx,keys[i],updates[i])'))
  self.assertGreater(part.index('keys.push_back(V32Path(slot,"weaponIndex"))'),part.index('keys.push_back(V32Path(slot,"camoIndex"))'))
  self.assertIn('Storage_Write(0,v32VerifiedOfflineFile,0)',part)
  self.assertIn('V32ScanSlot(root,ctx,zm,confirm)',part)
 def test_unified_save_is_gated(self):
  part=S[S.index('static void V35SaveOrCreate()'):S.index('static std::string V35ShortStatus()')]
  self.assertLess(part.index('V27NativeProbe();'),part.index('V27NativeApply();'))
  self.assertIn('if (!v35ConfirmCreate)',part)
  self.assertIn('V35CreateMissingKit();',part)
 def test_existing_save_still_unique_and_offline(self):
  part=S[S.index('static void V27NativeApply()'):S.index('static void V35CreateMissingKit()')]
  self.assertIn('v27NativeSlot<0',part)
  self.assertIn('V32ScanSlot(root,ctx,zm,reason)',part)
  self.assertIn('V32Backup(ctx,backup,reason)',part)
  self.assertIn('Storage_Write(0,v32VerifiedOfflineFile,0)',part)
 def test_optic_zero_and_eight(self):
  part=S[S.index('static bool V27BuildSafeSlots('):S.index('static void V33FillToEight()')]
  self.assertIn('int nextRigSlot=1;',part)
  self.assertIn('destination=0',part)
  self.assertIn('ids[destination]=id;',part)
  self.assertIn('v24Attachments.size()>8',part)
 def test_ui_not_cluttered(self):
  ui=S[S.index('static void V24DrawWeaponKits()'):]
  self.assertIn('CollapsingHeader("Advanced: cosmetics, presets & troubleshooting")',ui)
  self.assertIn('Save & Apply (offline)',ui)
  self.assertIn('Copy Details',ui)
  self.assertIn('Create a new kit in an empty slot (EXPERIMENTAL)',ui)
  self.assertIn('static bool v25ShowAllAttachmentOptions = false;',S)
  self.assertIn('if(selected && v35ShowCosmeticSelectors)',ui)
  self.assertNotIn('Create 48 Dredge Kit',ui)
 def test_build_files(self):
  self.assertIn('ZombiesKitUI.v35.inc',B)
  self.assertIn('Scropts.QOL.v35-unified-native-kits-Oct2026.dll',B)
  self.assertTrue((P/'RUN_BUILD_V35_KITS.bat').exists())
  self.assertTrue((P/'CrashCollector/UPLOAD_A_CRASH.bat').exists())
 def test_camo_look_preservation(self):
  self.assertIn('V33ResolveLooks(ids,looks,old,resolvedLooks,reason)',S)
  self.assertIn('v33PreserveNativeLooks',S)
  self.assertIn('v33AllowUnverifiedLooks',S)
if __name__=='__main__':unittest.main()
