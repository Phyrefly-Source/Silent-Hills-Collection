Silent Hill 3 Enhanced package.

To make it live:
  1. copy the built d3d8.dll from E:\Games\Silent Hill 3 into files\
     (only the DLL: SH3EE.ini is the patch's own settings file and must NOT be in the payload,
      so a player's settings survive Off -> On)
  2. set "version" in manifest.pending.json
  3. rename manifest.pending.json -> manifest.json

The launcher ignores the package until the manifest has its real name.
Optional later: "settings": "…/settings.json" in the Godot launcher's patch-settings schema
(see packages/rebuilds/homecoming/files/Enhanced/settings.json) to edit SH3EE.ini from the Mods tab.
