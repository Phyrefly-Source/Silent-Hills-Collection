#!/usr/bin/env python3
"""Builds the launcher's achievement lists: one file per game in one shape,
data/achievements/<game>.json, modelled on Steam's achievement lists.

    {"game", "platform", "source", "credit", "link", "notes",
     "achievements": [{"id", "name", "description", "hidden", "icon",
                       "icon_locked"?, "rarity"?, "unlock": {...}}]}

Where each list comes from (official lists first):
  * Steam games: their Steam lists (dev/achievements/source/<game>.json, made by
    tests/dump_steam_lists.gd) with Steam's own icons; Townfall from Exophase.
  * Games that had an official list on another platform: that list, with its
    official icons (Exophase's copies): Silent Hill 2 and 3 (PS3 trophies, HD
    Collection), Homecoming and Downpour (Xbox 360), Book of Memories (Vita).
  * Games that never had one: the RetroAchievements community set, with RA's
    badges (data/achievements/ra/<set>.json).
Global unlock rates ("rarity", % of players) come from Exophase for every list.

How an entry unlocks ("unlock"):
  {"type": "steam", "key": ...}     the Steam client's records on this PC
  {"type": "ra", "id": n}           a native build running the RA set's rules
  {"type": "rexglue", "id": "hex"}  DownpourRecomp's runtime
  {"type": "event", "name", "count"} bridge events from Enhanced patches/rebuilds
  {"type": "all"}                   every other entry unlocked (platinum)
Anything can also be unlocked through the bridge by id, or by hand.

Run from the project folder:  python3 tools/build_achievements.py
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "achievements")
SRC = os.path.join(ROOT, "dev", "achievements")
EXO_ICON = "https://m.exophase.com/%s/awards/l/%s"
RA_BADGE = "https://media.retroachievements.org/Badge/%s.png"

GAMES = {
    "sh1": {"ra": 11252, "platform": "PlayStation", "kind": "ra"},
    "sh2": {"exo": "sh2", "platform": "PlayStation 3", "kind": "trophies",
            "source": "Silent Hill HD Collection (PlayStation 3) trophies"},
    "sh3": {"exo": "sh3", "platform": "PlayStation 3", "kind": "trophies",
            "source": "Silent Hill HD Collection (PlayStation 3) trophies"},
    "sh4": {"ra": 1336, "platform": "PlayStation 2", "kind": "ra"},
    "origins": {"ra": 3927, "platform": "PSP", "kind": "ra"},
    "homecoming": {"exo": "homecoming", "platform": "Xbox 360", "kind": "xbox", "old": "homecoming.json",
                   "source": "Xbox 360 achievements"},
    "shattered-memories": {"ra": 19179, "platform": "PlayStation 2", "kind": "ra"},
    "downpour": {"exo": "downpour", "platform": "Xbox 360", "kind": "xbox", "old": "downpour.json",
                 "source": "Xbox 360 achievements"},
    "book-of-memories": {"exo": "book-of-memories", "platform": "PlayStation Vita", "kind": "trophies",
                         "source": "PlayStation Vita trophies"},
    "sh2-remake": {"steam": "sh2-remake.json", "appid": "2124490"},
    "sh-f": {"steam": "sh-f.json", "appid": "2947440"},
    "townfall": {"exo": "townfall", "appid": "1636440", "kind": "steam"},
}

NOTES = {
    "ra": "This game never had an official achievement list, so the launcher uses the {platform} set made by the "
          "RetroAchievements community. Native builds unlock them by the set's own rules; Enhanced patches report them "
          "through the launcher's bridge; anything else can be marked by hand.",
    "trophies": "The game's official {platform} trophies. Rebuilds and Enhanced patches report them through the "
                "launcher's bridge as they're hooked; until then you can mark them by hand.",
    "xbox": "The game's official Xbox 360 achievements, which the PC versions never had. The PC game reports them "
            "through the launcher's bridge; until then you can mark them by hand.",
    "steam": "Which ones you've unlocked comes from Steam's records on this PC.",
}


def slug(s):
    s = s.lower().replace("…", "").replace("'", "").replace("’", "")
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def read_exo():
    full, rarity, sec, kind, plat = {}, {}, None, None, None
    for line in open(os.path.join(SRC, "exophase.tsv"), encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or (line.startswith("#") and not line.startswith("## ")):
            continue
        if line.startswith("## "):
            _, sec, plat = line.split()[:3]
            full[sec] = {"platform": plat, "items": []}
            kind = "full"
            continue
        if line.startswith("@ "):
            sec = line.split()[1]
            rarity[sec] = {}
            kind = "rarity"
            continue
        f = line.split("\t")
        if kind == "full":
            full[sec]["items"].append({"name": f[0], "description": f[1], "icon": EXO_ICON % (plat, f[2]),
                                       "rarity": float(f[3]), "hidden": f[4] == "1", "grade": f[5] if len(f) > 5 else ""})
        else:
            rarity[sec][f[0]] = float(f[1])
    for k, v in full.items():
        rarity.setdefault(k, {}).update({i["name"]: i["rarity"] for i in v["items"]})
    return full, rarity


def main():
    full, rarity = read_exo()
    out_games = {}
    for gid, spec in GAMES.items():
        rates = rarity.get(gid, {})
        items = []
        meta = {"game": gid, "platform": spec.get("platform", "Steam")}
        if "ra" in spec:
            s = json.load(open(os.path.join(DATA, "ra", "%d.json" % spec["ra"]), encoding="utf-8"))
            for a in s["achievements"]:
                it = {"id": "ra-%d" % a["id"], "name": a["title"], "description": a["description"], "hidden": False}
                if a.get("badge"):
                    it["icon"] = RA_BADGE % a["badge"]
                    it["icon_locked"] = RA_BADGE % (a["badge"] + "_lock")
                if a["title"] in rates:
                    it["rarity"] = rates[a["title"]]
                it["unlock"] = {"type": "ra", "id": a["id"]}
                items.append(it)
            meta.update({"source": "%s set by the RetroAchievements community" % s["console"],
                         "credit": "RetroAchievements", "link": "https://retroachievements.org/game/%d" % spec["ra"],
                         "notes": NOTES["ra"].format(platform=s["console"])})
        elif "steam" in spec:
            s = json.load(open(os.path.join(SRC, "source", spec["steam"]), encoding="utf-8"))
            for a in s["achievements"]:
                it = {"id": slug(a["name"]), "name": a["name"], "description": a.get("description", ""),
                      "hidden": bool(a.get("hidden", False)), "icon": a.get("icon", "")}
                if a.get("icon_locked"):
                    it["icon_locked"] = a["icon_locked"]
                if a["name"] in rates:
                    it["rarity"] = rates[a["name"]]
                it["unlock"] = {"type": "steam", "key": a.get("key", ""), "steam_id": str(a["id"])}
                items.append(it)
            meta.update({"source": "Steam achievements", "credit": "Steam",
                         "link": "https://steamcommunity.com/stats/%s/achievements" % spec["appid"],
                         "steam_appid": spec["appid"], "notes": NOTES["steam"]})
        else:
            e = full[spec["exo"]]
            old = {}
            if spec.get("old"):
                for a in json.load(open(os.path.join(SRC, "source", spec["old"]), encoding="utf-8"))["achievements"]:
                    old[norm(a["name"])] = a
            for x in e["items"]:
                it = {"id": slug(x["name"]), "name": x["name"], "description": x["description"], "hidden": x["hidden"],
                      "icon": x["icon"], "rarity": x["rarity"]}
                if x["grade"]:
                    it["grade"] = x["grade"]
                o = None
                for k, a in old.items():
                    if k == norm(x["name"]) or (len(k) > 5 and k.startswith(norm(x["name"]))) or \
                            norm(x["name"]).startswith(k):
                        o = a
                        break
                if o:
                    it["id"] = o["id"]     # keep ids (and earlier unlocks) the launcher already used
                    if o.get("trigger"):
                        it["unlock"] = o["trigger"]
                if x["grade"] == "platinum":
                    it["unlock"] = {"type": "all"}
                if spec.get("kind") == "steam":
                    it["unlock"] = {"type": "steam", "name": x["name"]}
                it.setdefault("unlock", {"type": "event", "name": it["id"], "count": 1})
                items.append(it)
            if spec.get("kind") == "steam":
                meta.update({"source": "Steam achievements", "credit": "Steam",
                             "link": "https://steamcommunity.com/stats/%s/achievements" % spec["appid"],
                             "steam_appid": spec["appid"], "notes": NOTES["steam"]})
            else:
                meta.update({"source": spec["source"], "credit": "Exophase",
                             "link": {"sh2": "https://www.exophase.com/game/silent-hill-2-hd/trophies/",
                                      "sh3": "https://www.exophase.com/game/silent-hill-3-hd/trophies/",
                                      "homecoming": "https://www.exophase.com/game/silent-hill-homecoming-xbox-360/achievements/",
                                      "downpour": "https://www.exophase.com/game/silent-hill-downpour-xbox-360/achievements/",
                                      "book-of-memories": "https://www.exophase.com/game/silent-hill-book-of-memories-ps-vita/trophies/"}[gid],
                             "notes": NOTES[spec["kind"]].format(platform=spec["platform"])})
        ids = [i["id"] for i in items]
        assert len(ids) == len(set(ids)), (gid, [i for i in ids if ids.count(i) > 1])
        meta["achievements"] = items
        meta["rarity_source"] = "Exophase"
        with open(os.path.join(DATA, gid + ".json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=1)
            f.write("\n")
        out_games[gid] = len(items)
        missing = [i["name"] for i in items if "rarity" not in i]
        print("%-20s %3d  %s%s" % (gid, len(items), meta["source"], ("  (no rarity: %d)" % len(missing)) if missing else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
