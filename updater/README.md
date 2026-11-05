# Updater

Lives in the launcher as `core/updater.gd` (service "updater") and
`ui/widgets/update_banner.gd` (bar under the nav: What's new / Update now / Later / Skip).
`main.gd` adds the banner at start; it rate-limits itself to one API hit per 6 h.
A "Check for updates" entry in Settings can call `App.svc("updater").check(true)`.
`--updated` on the command line shows an "Updated to x.y.z" toast.

## Data folder: portable vs installed

`app.gd`: a `portable` marker, or an existing `data\` beside the exe (older builds),
keeps data there; otherwise `user://` (`%APPDATA%\Silent Hills`, `~/.local/share/Silent Hills`).
`rebuilds\`, `tools\` and `licenses\` stay beside the exe in every flavor.

## How each flavor swaps itself

| Flavor | Detected by | Apply |
|---|---|---|
| Windows installer | `unins000.exe` beside the exe | runs `…-setup.exe /VERYSILENT /CLOSEAPPLICATIONS`; Inno's `[Run]` relaunches with `--updated` |
| Windows portable | anything else on Windows | unzips to `user://update/staging`, writes `apply.cmd` that waits for our PID, xcopies over, relaunches |
| Linux AppImage | `$APPIMAGE` env var | `mv -f` the new AppImage over the old one (safe while running), relaunch |

Every download is checked against `SHA256SUMS.txt` from the same release first;
a mismatch deletes the file and shows an error.

## SteamOS notes

- AppImage, not Flatpak: Flatpak's sandbox would stop the launcher from starting games
  in `/home/deck` and from reading Steam's library files. The read-only root is never touched.
- Add it to Steam as a non-Steam game once; updates replace the file in place.
- Linux branches: processes via `/proc`, Steam at `~/.local/share/Steam` / `~/.steam`,
  scan roots include `~/Games`, `~/Emulation` and `/run/media/*` (SD cards).
- Windows-only games (`.exe`) run through `umu-run` (Proton) if installed, else `wine`;
  otherwise the launcher says what to install. Native Linux builds run directly.
- The tray-hide trick (`_hide_from_taskbar`) is Windows-only and skipped elsewhere.
