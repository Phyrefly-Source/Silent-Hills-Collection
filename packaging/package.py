#!/usr/bin/env python3
"""Packages the exported launcher into the three release flavors.

    package.py portable    build/windows/*  + dist/  -> out/SilentHills-<v>-windows-portable.zip
    package.py appimage    build/linux/*    + dist/  -> out/SilentHills-<v>-linux-x86_64.AppImage
    package.py installer   build/windows/*  + dist/  -> out/SilentHills-<v>-windows-setup.exe   (needs Inno Setup)
    package.py --print-version
    package.py --notes <v>                            prints CHANGELOG.md section for <v>

Runs the same way in CI and on your PC. Export first (Godot: Project > Export),
putting "Silent Hills.exe" in build/windows and silent-hills.x86_64 in build/linux.
"""
import os, re, shutil, stat, subprocess, sys, urllib.request, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAUNCHER = ROOT / "launcher"
BUILD = ROOT / "build"
DIST = ROOT / "dist"
OUT = ROOT / "out"
APP = "Silent Hills"
SLUG = "SilentHills"


def version() -> str:
    text = (LAUNCHER / "project.godot").read_text(encoding="utf-8")
    m = re.search(r'^config/version="([^"]+)"', text, re.M)
    if not m:
        sys.exit("config/version not set in launcher/project.godot")
    return m.group(1)


def notes(v: str) -> str:
    log = ROOT / "CHANGELOG.md"
    if not log.exists():
        return f"Silent Hills {v}"
    text = log.read_text(encoding="utf-8")
    m = re.search(rf"^## \[?{re.escape(v)}\]?.*?$\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1).strip() if m else f"Silent Hills {v}"


def copy_tree(src: Path, dst: Path):
    if src.exists():
        shutil.copytree(src, dst, dirs_exist_ok=True)


def stage(platform: str) -> Path:
    """build/<platform> + dist/common + dist/<platform> -> stage/<platform>"""
    s = ROOT / "stage" / platform
    shutil.rmtree(s, ignore_errors=True)
    copy_tree(BUILD / platform, s)
    copy_tree(DIST / "common", s)
    copy_tree(DIST / platform, s)
    # Pre-baked packages: Enhanced patches (rebuilds/<game>) and mods (mods/<game>/<mod>),
    # toggled on and off from each game's Mods tab.
    copy_tree(ROOT / "packages" / "rebuilds", s / "rebuilds")
    copy_tree(ROOT / "packages" / "mods", s / "mods")
    return s


def portable():
    v = version()
    s = stage("windows")
    (s / "portable").write_text("Delete this file to store data in %APPDATA% instead of beside the exe.\n")
    OUT.mkdir(exist_ok=True)
    zpath = OUT / f"{SLUG}-{v}-windows-portable.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for p in s.rglob("*"):
            if p.is_file():
                z.write(p, Path(APP) / p.relative_to(s))
    print("wrote", zpath)


def installer():
    v = version()
    s = stage("windows")
    OUT.mkdir(exist_ok=True)
    iscc = shutil.which("iscc") or r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if not Path(iscc).exists():
        sys.exit("Inno Setup not found (install from jrsoftware.org or `winget install JRSoftware.InnoSetup`)")
    subprocess.check_call([iscc, f"/DAppVersion={v}", f"/DStageDir={s}", f"/DOutDir={OUT}",
                           str(ROOT / "packaging" / "windows" / "installer.iss")])
    print("wrote", OUT / f"{SLUG}-{v}-windows-setup.exe")


def appimage():
    v = version()
    s = stage("linux")
    OUT.mkdir(exist_ok=True)
    appdir = ROOT / "stage" / "AppDir"
    shutil.rmtree(appdir, ignore_errors=True)
    usr = appdir / "usr" / "bin"
    usr.mkdir(parents=True)
    copy_tree(s, usr)
    exe = usr / "silent-hills.x86_64"
    exe.chmod(exe.stat().st_mode | stat.S_IEXEC)
    lin = ROOT / "packaging" / "linux"
    shutil.copy(lin / "silent-hills.desktop", appdir / "silent-hills.desktop")
    shutil.copy(lin / "silent-hills.png", appdir / "silent-hills.png")
    shutil.copy(lin / "AppRun", appdir / "AppRun")
    (appdir / "AppRun").chmod(0o755)

    tool = ROOT / "stage" / "appimagetool"
    if not tool.exists():
        urllib.request.urlretrieve(
            "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage", tool)
        tool.chmod(0o755)
    target = OUT / f"{SLUG}-{v}-linux-x86_64.AppImage"
    env = dict(os.environ, ARCH="x86_64", APPIMAGE_EXTRACT_AND_RUN="1")
    subprocess.check_call([str(tool), "--no-appstream", str(appdir), str(target)], env=env)
    target.chmod(0o755)
    print("wrote", target)


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args[0] == "--print-version":
        print(version())
    elif args[0] == "--notes":
        print(notes(args[1]))
    else:
        for a in args:
            {"portable": portable, "installer": installer, "appimage": appimage}[a]()
