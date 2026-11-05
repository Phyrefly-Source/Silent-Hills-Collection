# Releasing the launcher

Minor work stays local. A **major build** is a tag.

## One-time setup

The repo is **public**, so releases are public and the launcher's updater reads
them anonymously. No tokens, no secrets: Actions uses its own `GITHUB_TOKEN`.

1. Push `main` once (`git push -u origin main`, or "Push origin" in GitHub Desktop).
2. On GitHub: Settings → Actions → General → Workflow permissions: **Read and write**.

## Cutting a release

```powershell
# 1. bump
#    launcher/project.godot  -> config/version="2.5.0"
#    CHANGELOG.md            -> add "## 2.5.0" section (becomes the release notes + banner text)
git add -A
git commit -m "Silent Hills 2.5.0"
# 2. tag = trigger
git tag v2.5.0
git push origin main --tags
```

Actions then: exports both platforms headless → portable zip + AppImage (Ubuntu)
→ Inno Setup installer (Windows runner) → `SHA256SUMS.txt` → GitHub release
`v2.5.0` on this repo with all four files. Running launchers see it within
6 hours, or at once from Settings → Check for updates.

A tag whose version doesn't match `project.godot` fails the first job on purpose.

## Building locally (same script CI uses)

```powershell
# export from the Godot editor (Project > Export > Export All, release), or:
godot --headless --path launcher --export-release "Windows" build/windows/"Silent Hills.exe"
godot --headless --path launcher --export-release "Linux" build/linux/silent-hills.x86_64

python packaging/package.py portable installer      # Windows PC (needs Inno Setup 6)
python packaging/package.py appimage                # Linux / WSL
```

Results land in `out/`. To publish a local build by hand:
`gh release create v2.5.0 out/* -F notes.md`.

## Flavors

| Asset | For | Data lives in |
|---|---|---|
| `SilentHills-<v>-windows-setup.exe` | normal Windows install, Start-menu entry, uninstaller | `%APPDATA%\Silent Hills` |
| `SilentHills-<v>-windows-portable.zip` | USB / any folder; contains a `portable` marker | `data\` beside the exe |
| `SilentHills-<v>-linux-x86_64.AppImage` | SteamOS and any Linux; `chmod +x`, add to Steam | `~/.local/share/Silent Hills` |

## Godot version

`GODOT_VERSION` in `release.yml` must be the exact editor version the project was
last saved with (export templates are version-locked). Bump both together.

## Secrets that must stay out of the repo

`launcher/keystore/` (the Android companion's signing key and its password) is
git-ignored and was not copied from `E:\Games\Project-Silent\projects\launcher-godot`.
Keep it there; the Android export is done locally, never in CI.
