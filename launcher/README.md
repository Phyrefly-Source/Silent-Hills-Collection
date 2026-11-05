# Silent Hills (Godot)

A launcher for the Silent Hill series. Start it with **Silent Hills.exe**.

The magnifier left of NEWS (or **Ctrl+K**) opens a search box that goes to any game, film, comic or album, or runs a command (letters in order are enough: "sh2r" finds Silent Hill 2 (2024)); it also shows each section's shortcut (Ctrl+1 to Ctrl+6, Ctrl+, for Settings). Esc closes any window. Everything can be reached with the keyboard (controllers are ignored, so they never trigger the launcher while you play); the focused control has an amber outline. **Reduce motion** (Settings → Playing) keeps backgrounds and panels still.

## Profiles

Each person using the PC can have a **local profile**: a username and password, kept on this PC only (in `data/accounts.json`; passwords are stored as salted PBKDF2-SHA256 hashes, never as text). Your round profile picture sits in the top-right corner; click it for **Profile**, **Settings** and **Sign out**.

- **On first start** the launcher offers to make a profile (or carry on as a guest). With profiles on the PC it asks you to sign in, unless you ticked "Keep me signed in".
- **Profile** shows your picture (Change picture… crops any picture to a circle), total time played, games played, achievements across the series and completed games; your **favourites** (up to three, also starred from any game's page and marked with a star in the list); and **achievement progress** for every game you've started (click one for its achievements).
- **Each profile has its own** play time, achievements and favourites. The first profile made on a PC takes over what was recorded before profiles existed. As a guest, play time and achievements go to the shared records.
- There's no password recovery yet; later, profiles can move online.

## News

The page the launcher opens on.

- **Buy on PC:** every Silent Hill game sold for PC (Townfall, Silent Hill f, Silent Hill 2 (2024), Homecoming, Silent Hill 4) with its price at the **official stores only**: Steam, GOG and the Epic Games Store. When a store has it on sale you see the discount and the full price; otherwise the full price. Games on sale come first. Each store opens that game's page. Steam's and GOG's prices come straight from their stores; Epic's from CheapShark's reading of the Epic store, since Epic has no public price feed.
- **New on PC stores:** a Silent Hill page that appears on Steam or GOG (a new game, edition or DLC) shows here for 60 days, and you get a notice.
- **This week in Silent Hill history:** games and films whose release anniversary was in the last few days or is coming up this week.
- **Silent Hill news:** headlines from the last 30 days (a Google News search for "Silent Hill", plus announcements from Steam for the series' Steam games), newest first. Headlines about games being announced, dated, released or remade are marked **New entry**; Konami's own posts and Steam announcements are marked **Official**. Headlines that only use the name ("a scene from Silent Hill") are left out. **Only new entries** hides the rest.
- **Alerts:** the launcher checks when it starts and every 3 hours. A new sale (or a lower price), a new store page or a new-entry headline gets a notice and a dot on NEWS until you open it.

## Games

The series in release order, each over its own art.

- **The main button** always does the next useful thing. Depending on the game, that's **Play**, **Find game**, **Choose your dump**, **Build for PC** or **Install** the Enhanced patch.
- **Finding games.** On first start the launcher looks for your games, existing PC builds and disc dumps in the usual places:
  - each drive's Games, GOG Games and SteamLibrary folders
  - your Steam libraries
  - Program Files
  - Documents, Downloads and Desktop
  - any folder you add in Settings

  If a game isn't found, use **Browse…** to point to its folder or dump. **Manage** can also look for it again.
- **Rebuilds and Enhanced patches.** Console-only games are rebuilt for PC from your own disc dump. PC releases get an Enhanced patch. Both come as packages in the `rebuilds` folder (see below). Until a game's package is there:
  - an existing PC build or install is played as it is
  - your dump is remembered so the build can start as soon as the package arrives
- **Achievements** work the same way for every game, laid out like Steam's: one list per game, each achievement with its icon, name, description, how many players have it, and the date you unlocked it. Unlocked ones come first (newest first), then locked ones (most common first); hidden ones stay folded away until unlocked, or until you choose to see them. When one unlocks, a notice with its icon slides in at the bottom right. Every list is **built into the launcher**, so nothing needs an account, a key or a connection, and the companion app shows exactly the same thing. Official lists come first:
  - **Silent Hill 2 (2024), Silent Hill f and Townfall:** their Steam achievements. Which ones you've unlocked comes from Steam's records on this PC.
  - **Silent Hill 2 and 3:** their PlayStation 3 trophies from the HD Collection. **Homecoming and Downpour:** their Xbox 360 achievements (the PC versions never had them). **Book of Memories:** its PS Vita trophies. Official icons; Enhanced patches and rebuilds report them through the bridge (DownpourRecomp's own unlocks are read directly), and a game's "unlock everything" trophy unlocks itself.
  - **Silent Hill, Silent Hill 4, Origins and Shattered Memories** never had official lists, so they use the RetroAchievements community's sets, with RA's badges. Native builds unlock them by the set's own rules.
  - **P.T. and The Short Message** never had any, so they have none.
  - How many players have each one comes from Exophase, for the version each list belongs to. Anything a game can't report yet can be marked by hand. The lists are made by `tools/build_achievements.py`.
- **Saves.** A backup is taken each time you press Play, and the newest 15 are kept. You can also back up with a name, restore (your current saves are backed up first) or delete backups.
- **Mods** from a .zip or a folder. Turning one off puts the original files back, whatever order mods were turned on in.
- **Play time.** Time played is counted while any program from the game's folder runs, so launcher stubs and Steam starts are counted properly.
- **Game settings** are made inside the games, through their Enhanced patches. A patch that ships a settings list (Homecoming Enhanced) can also be tuned from **Mods**: open its card (the arrow, or click its name) for every value, grouped by section. Each change is saved to the patch's settings file at once. While the game runs, values the game picks up live stay editable and apply right away; the rest are locked until you close it.

**Artwork.** Nothing is bundled; each game's background is official key art fetched when it's first shown, then kept in the cache:

- Steam games use Steam's own art cache on this PC, or Steam's public store art.
- Other games use their official key art or widest official wallpaper from [Silent Hill Memories](https://www.silenthillmemories.net), a long-running archive of official Silent Hill material. No key is needed.
- With your own free SteamGridDB API key (Settings), SteamGridDB is used first, with a wider choice of art.
- **Manage → Background…** (and **Logo…**) opens a picture picker:
  - **Official art:** Steam's art and Silent Hill Memories' wallpapers, key art and posters
  - **SteamGridDB:** paste your free API key right there the first time (**Get a free key** opens the page)
  - **Web search:** searches the web for pictures (DuckDuckGo). If it can't, **Search in browser** opens the search, and you can paste a picture's address
  - **Use a picture…**, a pasted link, or a picture dropped onto the window
  - **Automatic** goes back to the launcher's own choice

The fog, rain, snow, ash and embers drawn over the art are generated by the launcher. Turn them off in Settings.

## Comics

Every Silent Hill comic is on the shelf, including the ones you don't have yet. Add your own copies with **Add comics…** or **Add a folder…**. They're matched to the shelf by name, and issue numbers are read from the file names ("Issue #2", "#2").

- **A series** opens to its page: the cover, year, publisher and writer, and every issue with your progress. Issues you don't have are shown too. **Continue** picks up where you stopped; **Start from the beginning** goes back to issue 1.
- **Continue** on the shelf goes straight back to the comic you were last reading.
- **The reader:**
  - ← → or A D, Space, Page Up / Page Down, the mouse wheel, or click the left or right of the page: turn pages
  - the slider at the bottom jumps to any page
  - W, F or double-click: fit the page's width and scroll down it (wheel or ↑ ↓); again to fit the whole page
  - 2: two-page spreads (the cover stays on its own)
  - F11: full screen
  - Home / End: first or last page
  - Esc: close
  - The controls fade away while you read; move the mouse or click the middle of the page to bring them back.
- At the end of an issue the reader offers the next one.
- Your page in every comic is remembered, and finished issues are marked as read.
- **Formats:** CBZ / ZIP and folders of page images open directly. CBR and CB7 open when 7-Zip is installed. PDF isn't supported yet.

## Concept Art

The officially released concept art for every game and film, in one place.

- Pictures come from the concept-art galleries on [Silent Hill Memories](https://www.silenthillmemories.net), grouped as the site groups them (characters, creatures, sketches…). The site asks for credit and a link back: every picture links to the page it came from. Nothing is bundled.
- Click a picture to view it full-window: ← → to move between pictures, Space or a click in the middle for full size (drag to look around), **Open the source page**, Esc to close.
- **Keep offline** saves a game's pictures to `data\concept-art\<game>\` under the site's own file names, so they stay available without the internet. A bar under the title shows how far it's got (pictures and size), each picture gets a "✓ kept" mark as it lands, and the list on the left shows ↓ while a game is saving and ✓ when all of it is kept. Saving carries on while you look at other games. **Open folder** shows that folder.
- **Keep everything offline** saves every game's and film's art in one go, with its own bar under the list.
- **Add a folder…** adds your own scans (art books, press kits). Folders named after a game ("Silent Hill 3", "SH3") are listed with that game; the rest are under **Other pictures**.

## Films

The Silent Hill films, played in the launcher.

- Your copies are found in a `Movies` (or `Films`) folder next to the launcher or one folder up, or in a "Silent Hill" folder in Videos. **Choose the file…** connects one by hand.
- Files are matched by name ("Silent.Hill.Revelation.2012.1080p.mkv" works). Videos that don't match a film are listed under **Other files**.
- **The player** plays anything FFmpeg can (MKV, MP4, H.264, HEVC 10-bit, 4K…) through `tools\ffmpeg.exe`, using your graphics card's video decoder when it can:
  - Space or K: pause
  - ← → or J L: back or forward 10 seconds (with Shift: a minute); or drag the bar
  - ↑ ↓: volume, M: mute
  - S: subtitles (text tracks in the file, or an .srt with the same name beside it)
  - A: sound track, when the file has more than one
  - F, F11 or double-click: full screen
  - Home: from the beginning; Esc: close
- Your place in each film is remembered; **Resume** picks up there.
- **Soundtrack** opens the film's soundtrack when it's in your OSTs folder (it's listed under **Film soundtracks**); **Concept art** opens the film's art.

## Soundtracks

A jukebox of the official soundtracks you own, plus any other folders of music you add.

- **Your soundtrack albums are found on their own.** Put them in an `OSTs` (or `Soundtracks`) folder next to the launcher or one folder up, or in a "Silent Hill …" folder inside Music. **Add a folder…** adds any other place.
- Each album folder is matched to its game by name and listed under **Soundtracks**, by game, in release order. Folders that don't match a game are listed under **Other music**.
- New or changed albums are noticed the next time the launcher starts, or straight away with **Look again**.
- **Tracklists come from the files' own tags:** titles, artist, year, and track and disc order. Some fixes are made for badly tagged files:
  - When every track has the same title, titles come from the file names, and the music is credited to the game's composer rather than whoever uploaded the files.
  - Titles split into "artist" and "title" at a dash (SH3's "Breeze - in Monochrome Night") are put back together.
  - Untagged tracks are credited to the game's composer.
- **Album covers** come from a front-cover image in the album folder or its `Covers` folder, otherwise from the picture embedded in the tracks.
- MP3, OGG and WAV play directly, and so do ADX and AIX rips.
- FLAC is converted once with the FFmpeg in the `tools` folder, and kept in the cache. The next track in the queue is converted while the current one plays.
- **Favourites:** ♥ on any track. **Playlists:** the ⋯ menu.
- Tracks can be renamed from the ⋯ menu too.

## Sounds

Interface sounds play as you move through the launcher: moving through a list, switching sections, pressing a button and closing. Choose a **Sound profile** in Settings:

- **Silent Hill 3:** the game's own menu sounds, read from your copy (`data\sound\sd.afs`).
- **Silent Hill 2:** the sounds in your Silent Hill 2: Enhanced Edition's sound folder.
- **Radio static:** made by the launcher, so it works without any game.
- **Off.**

A profile needs its game connected. **Choose sounds…** lets you try every short sound in that game and pick which one each action uses. Nothing is bundled.

## Hide missing

By default the Comics shelf, Films and Soundtracks also list what you don't have yet, so they double as a checklist. **Hide missing** (a checkbox on those pages, and in Settings) leaves them out.

## Phone companion (Android)

A companion app for your phone brings this launcher to your phone, without the games themselves. It has five tabs:
- **Achievements:** every game's achievements and your progress.
- **Concept Art.**
- **Soundtracks:** your albums, played from this PC at home. **Keep on phone** saves an album so it plays anywhere. Tracks this PC converts for the PC player (FLAC and so on) are converted for the phone the same way.
- **Comics:** read page by page. Swipe or tap the sides to turn, pinch or double-tap to zoom. **Keep on phone** saves a whole comic. Your page is kept in step with this PC both ways.
- **Films:** two ways to watch.
  - **Get it ready for the phone:** this PC converts the film for phones once, into `data\cache\companion-films`. That takes a while, using half your processor cores, and needs Silent Hills left open. The phone then downloads it, which takes a minute or two on home Wi-Fi, and plays it in the app, anywhere, sideways, with subtitles when the film has them. Your place is kept in step with this PC.
  - **Stream to a video app:** opens the film straight away in the phone's browser, or in Samsung Video or VLC, streamed from this PC at home.

1. On this PC: **Settings → Phone companion → Let the phone app connect.** Settings then lists this PC's address. Windows may ask once whether Silent Hills can use the network; allow **private networks**.
2. On the phone, with both on the same Wi-Fi: **Find my PC** (or type the address), then type the 6-digit code this PC shows.

**Updates come from this PC.** The launcher carries the newest companion app in its `companion` folder. When a paired phone syncs and is older, it offers **Update**: the phone downloads the app from this PC, checks it, and Android shows its usual update screen. The first time, Android asks you to let Silent Hills install apps. Settings lists each phone's app version.

The phone keeps what it last synced, so it still shows your progress away from home. Pages read and places in films while away are sent to this PC the next time the phone reaches it. Only phones you paired can read anything. **Forget** in Settings removes a phone. The link uses TCP port 47630 and UDP port 47631 on your home network only. Nothing goes through the internet.

## Where things are kept

Everything stays in this folder:

- `data\settings.json`, `data\library.json`: settings, game folders, play time, favourites and playlists
- `data\save-backups\<game>\`: save backups (zip files)
- `data\mod-backups\<game>\`: original files that turned-on mods replaced
- `data\achievements\`: progress, player-made lists, and the bridge inbox
- `data\art\<game>\`: pictures you chose
- `data\concept-art\<game>\`: concept art you kept offline
- `data\cache\`: art, downloads and indexes. Safe to delete.
- `mods\<game>\`: your mods
- `rebuilds\<game>\`: rebuild and Enhanced patch packages
- `tools\`: ffmpeg.exe, for FLAC music

On first start, game folders and play time are brought over from the Electron launcher one folder up.

## For developers

The look (colours, type, spacing, icons, motion) lives in `ui/style.gd`; the reasons are in `docs/design.md`, and `tests/contrast.gd` checks every text colour against WCAG 2.2 AA. Fonts: Cormorant Garamond and IBM Plex Sans (SIL OFL, in `fonts`); icons: Lucide (ISC, `icons/icons.json`).


### Packages: `rebuilds\<game>\manifest.json`

```json
{
  "name": "Silent Hill: Origins PC",
  "version": "1.5.2",
  "kind": "rebuild",
  "steps": [{"label": "Recompiling", "exe": "tools/build.exe", "args": ["--dump", "{dump}", "--out", "{output}"]}],
  "output": "{launcher}/builds/origins",
  "run": {"exe": "{output}/SilentHillOrigins.exe", "args": ["{dump}"]}
}
```

An Enhanced patch uses `"kind": "enhanced"`. Its `files\` folder is copied into the game folder through the mod manager, so it can be removed cleanly. `"installed_when": ["SH3EE.ini"]` tells the launcher the patch is already in place. `"settings": "Enhanced/settings.json"` (relative to `files`) names a settings schema, `{ini, live_reload, groups: [{title, note, items: [{section, key, label, type, min, max, step, default, options, help, live}]}]}` with types bool, int, float and choice; the Mods card lists those settings and writes them into `ini` (relative to the game folder), one key at a time. Items with `"live": true` stay editable while the game runs when `live_reload` is true.

Tokens: `{game}` `{dump}` `{output}` `{launcher}` `{documents}` `{appdata}` `{localappdata}` `{savedgames}` `{programfiles}` `{programfilesx86}`.

### The bridge

Games started from the launcher get `SILENTHILLS_GAME_ID` and `SILENTHILLS_ACHIEVEMENTS_INBOX` in their environment. Write one JSON object per file into the inbox:

```
{"game":"sh3","event":"leonard_defeated"}     count an event
{"game":"sh3","event":"kills","count":5}      add to a counter
{"game":"sh3","set":"kills","value":40}       set a counter
{"game":"sh3","unlock":"the-end"}             unlock an entry
```

The C header `dev\achievements-bridge.h` falls back to this inbox when its pipe isn't there.

Lists live in `resources` (built in) or `data\achievements\<game>.json`. Entries can use these triggers:

- `rexglue` (`id`)
- `event` (`name`, `count`)
- `stat` (`playtime` / `sessions`)
- `manual`

### Native achievements

`dev\silenthills-ra\` is a small C kit for native builds: it runs a game's RetroAchievements set against the console memory a recompiled build keeps, using RetroAchievements' own evaluator (rcheevos, MIT, included), and reports unlocks to the launcher. The launcher passes the achievements still locked in `SILENTHILLS_RA_DEFS`. See its README for each game.

### Catalogue

Built-in games are in the project's `data\games.json`. Files in `data\catalogue\*.json` (`{"games": [...]}`) add games or override fields by id, with no new build.

### Source

The Godot 4.7 project (GDScript, Compatibility renderer) is in `projects\launcher-godot` next to the old launcher:

- `core\`: services
- `ui\`: pages and widgets
- `fx\`: the atmosphere shader
- `tests\`: headless checks: `godot --headless --script res://tests/services.gd` with `SILENTHILLS_ROOT` pointing at a test folder

Fonts: Cormorant Garamond and Inter, both SIL Open Font License.

Silent Hills is a fan-made launcher. It isn't affiliated with or endorsed by Konami. Silent Hill is a trademark of Konami Digital Entertainment. No game data, art or music is included.
