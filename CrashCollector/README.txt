1. Close Black Ops III after a crash.
2. Double-click UPLOAD_A_CRASH.bat.
3. Wait for SUCCESS. It will create Desktop\BO3_Crash_Reports\BO3_Crash_YYYY-MM-DD_HH-MM-SS.zip.
4. Drag that ZIP into the existing ChatGPT conversation. The script never uploads files by itself.
5. Mention what you clicked just before BO3 closed and which test DLL was loaded.

If ZIP is too large, run LOGS_ONLY_NO_DUMPS.bat (without crash memory data it may be less diagnostic).

Safety: this script reads only recent BO3 crash dumps, Application Error events,
BO3 Windows Error Reporting text, and a small number of recent game logs.
It does not edit Windows registry, BO3 files, Defender, or Steam.
A dump can include sensitive process information; inspect it before sharing.

This tool is standalone. No Scropts DLL has to be loaded for it to work.
