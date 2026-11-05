# Pre-baked packages

Everything here ships beside the launcher in every build and is turned on and
off from the game's Mods tab, with full file rollback (core/mods.gd).

- `rebuilds/<game>/` — Enhanced patches: `manifest.json` (`"kind": "enhanced"`), `files/` mirrors the game folder.
  Source of each package is its own project (`shh/package/homecoming`, …); copy the built package here.
- `mods/<game>/<mod>/` — ordinary mods: `mod.json` + `files/`.

| Package | Game | Source |
|---|---|---|
| rebuilds/homecoming | Silent Hill: Homecoming | Homecoming Enhanced (`shh/package/homecoming`) |
| mods/sh2-remake/Classic Mode | Silent Hill 2 (2024) | `projects/sh2r-classic`, `tools/shots.py package` |
