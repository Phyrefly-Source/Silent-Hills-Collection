Silent Hill Homecoming Enhanced 0.9 (29 Oct 2026)
==================================================
Requires Unknownproject's Patch 3.20 (g_SilentHill.sgl from 20 Dec 2024). On any other game build
the DLL turns itself off and the game runs unmodified.

Turning it on and off
  Use the Silent Hills launcher: Homecoming > Mods > Homecoming Enhanced. Off removes every file of
  the patch and puts back the game's own config values it had changed (Engine\vars_pc.cfg,
  Engine\default_pc.cfg, recorded in Enhanced\engine-originals.ini). On brings every feature and
  your settings back.

Settings
  In the game: Options (title screen or pause menu). They are kept in Enhanced\HomecomingEnhanced.ini.

Files
  Bin\dinput8.dll                     the patch (loads as the game's DirectInput)
  Enhanced\ui\*.xml                   the Options pages
  Enhanced\strings\english.txt        menu text
  Enhanced\prompts\*.png              button prompts (the collection set)
  Enhanced\src\shh-enhanced-src.bundle  source (git bundle)
  Written while playing: HomecomingEnhanced.ini / .log, engine-originals.ini

Credits
  Unknownproject - Patch 3.20, which this builds on and leaves untouched.
