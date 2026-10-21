"""Compose exact, source-hash-bound Wrath corrections over reviewed candidates.

This does not publish, activate or approve guides. Parent recipes and candidate
receipts are mandatory; normal guides and historical recipes are never edited.
The existing builders subsequently verify every replacement against pinned raw
sources. All replacements remain explicit in the generated recipe for review.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class Editor:
    def __init__(self, body):
        self.body, self.edits = body, []

    def replace(self, old, new, reason):
        count = self.body.count(old)
        if not old or not 0 < count <= 100 or old == new:
            raise ValueError(f"Invalid exact replacement: {old[:100]}")
        self.edits.append(dict(from_=old, to=new, reason=reason, occurrences=count,
                               kind="wrath-publication-compatibility"))
        self.edits[-1]["from"] = self.edits[-1].pop("from_")
        self.body = self.body.replace(old, new)

    def lines(self, pattern, transform, reason):
        for old in dict.fromkeys(m[0] for m in re.finditer(pattern, self.body, re.M)):
            new = transform(old)
            if old != new:
                self.replace(old + "\n", new + "\n", reason)


FLIGHTS = {
    "A": {"Westfall": "Sentinel Hill", "Redridge Mountains": "Lakeshire",
          "Ashenvale": "Astranaar", "Felwood": "Talonbranch Glade",
          "Darnassus": "Rut'theran Village", "Dustwallow": "Theramore", "Stormwind City": "Stormwind"},
    "H": {"Felwood": "Bloodvenom Post", "The Supulcher": "The Sepulcher", "Spinebreaker Post": "Spinebreaker Ridge"},
}
WAYPOINTS = {
    "The Barrens,46.07,79,19,40,0": "The Barrens,46.07,79.19,40,0",
    "Undercity,59,91,11.32,20,0": "Undercity,59.91,11.32,20,0",
    "Un'Goro Crater,20.6,60,40,70,0": "Un'Goro Crater,20.6,60.40,70,0",
    "Un'Goro Crater,20.6,60,4,70,0": "Un'Goro Crater,20.6,60.4,70,0",
    "Un'Goro Crater,22.2,41,0,70,0": "Un'Goro Crater,22.2,41.0,70,0",
    "Un'Goro Crater,46,0,56.6,70,0": "Un'Goro Crater,46.0,56.6,70,0",
}
for point in ("49.6,55.4", "50.6,61.8", "55.4,54.6"):
    WAYPOINTS[f"Burning Steppes,{point},0,60,0"] = f"Burning Steppes,{point},60,0"
for point in ("51.60,16.40", "54.60,13.20", "58.40,13.60", "62.60,16.60", "61.40,21.60", "63.20,24.00",
              "64.80,28.20", "67.60,32.00", "60.60,30.60", "56.40,32.80", "53.00,28.00", "54.80,21.80"):
    WAYPOINTS[f"Silithus,{point},70,0,0"] = f"Silithus,{point},70,0"


def repair_jaina(e, family):
    if not re.search(r"\.(?:accept|turnin|abandon|isOnQuest|isQuestTurnedIn) 1122[23]\b", e.body):
        return
    name = re.search(r"^#name (.+)$", e.body, re.M)[1]
    if family != "tbc" or name not in ("38-40 Dustwallow Marsh", "45-45 Tanaris"):
        raise ValueError("Unreviewed Jaina route")
    reason = ("Pinned AC facts have no creature/gameobject quest relations for11222/11223 and no Jaina Stormwind transport action. "
              "Use the valid Theramore-Menethil boat, Dun Algaz roads and Tram; retain11142 and subsequent valid stops. "
              "No flight knowledge or ready hearthstone is assumed.")
    road = ("From Menethil Harbor, follow the Wetlands road east to Dun Algaz, then the tunnels south into Loch Modan. "
            "Follow the road west through Dun Morogh to Ironforge. Stay on the roads; no mountain or coastal shortcut is required.")
    if name == "38-40 Dustwallow Marsh":
        old = re.search(r"(?m)^\.accept 11222[^\n]*\n", e.body)[0]
        e.replace(old, ">>The old Warn Bolvar!/Return to Jaina continuation is unavailable on stock Wrath. Continue by ordinary transport after receiving Survey Alcaz Island's reward.\n", reason)
        steps = re.findall(r"(?ms)^step\b.*?(?=^step\b|\Z)", e.body)
        for step in steps:
            if ".gossip 4968,0" in step:
                travel = ("step\n>>Walk to Theramore's dock and take the boat to Menethil Harbor. " + road +
                          " Enter the Deeprun Tram in Tinker Town, ride to Stormwind, and exit into the city for the following quest rewards. "
                          "If resuming in Wetlands, Loch Modan, Dun Morogh or Ironforge, continue from there; if already in Stormwind, stay there.\n"
                          ".zone Stormwind City >>Reach Stormwind for the retained quest stops\n")
                e.replace(step, travel, reason)
            elif re.search(r"\.(?:abandon|turnin|accept) 1122[23]\b", step):
                e.replace(step, "", reason)
        # Only the second Theramore cast belonged to the removed Mage return.
        marker = e.body.index(".accept 1449")
        match = re.search(r"(?ms)^step << Mage\n#completewith next\n\.cast 49359.*?(?=^step\b)", e.body[marker:])
        if not match:
            raise ValueError("Missing obsolete Mage return")
        e.replace(match[0], "", reason)
        steps = re.findall(r"(?ms)^step\b.*?(?=^step\b|\Z)", e.body)
        tram = steps[-1]
        if ".zone Ironforge >> Enter the Deeprun Tram" not in tram:
            raise ValueError("Missing final Tram")
        e.replace(tram.rstrip("\n"), "", reason)
        trainer = next(s for s in steps if ".target Dink\n" in s)
        arrival = ("step\n>>From Stormwind, enter the Deeprun Tram in the Dwarven District and ride to Ironforge. "
                   "A Mage who has already teleported to Ironforge can continue there.\n.zone Ironforge >>Reach Ironforge\n")
        e.replace(trainer, arrival + trainer, reason)
        cast = next(s for s in steps if ".cast 3562 " in s)
        e.replace(cast, cast.replace(".usespell 3562\n", ".usespell 3562\n.train 3562,3\n"), reason)
    else:
        steps = re.findall(r"(?ms)^step\b.*?(?=^step\b|\Z)", e.body)
        for step in steps:
            if ".cast 18960 " in step:
                e.replace(step, step.replace("#completewith next\n", "#completewith next\n.bindlocation 513,1\n.cooldown item,6948,>2,1\n"),
                          "Only offer the Moonglade training detour when the authored Theramore return is bound and ready.")
            elif ".target Loganaar\n" in step:
                e.replace(step, step.replace(".target Loganaar\n", ".target Loganaar\n.zoneskip Moonglade,1\n"),
                          "Do not require the Moonglade trainer if the optional teleport detour was unavailable.")
        steps = re.findall(r"(?ms)^step\b.*?(?=^step\b|\Z)", e.body)
        start = next(i for i, s in enumerate(steps) if ".cast 3562 " in s)
        old = "".join(steps[start:])
        if ".accept 11222" not in old or ".target Dink\n" not in old:
            raise ValueError("Unexpected Tanaris travel tail")
        trainer = next(s for s in steps[start:] if ".target Dink\n" in s)
        new = ("step << Mage\n#optional\n.train 3562,3\n.cast 3562 >>If learned and supplied, teleport to Ironforge\n.usespell 3562\n.zoneskip Ironforge\n"
               "step\n#optional\n.bindlocation 513,1\n.cooldown item,6948,>2,1\n.subzoneskip 513\n"
               ".zoneskip Wetlands\n.zoneskip Loch Modan\n.zoneskip Dun Morogh\n"
               ".zoneskip Ironforge\n.zoneskip Stormwind City\n.hs >>Hearth to Theramore only if bound there and ready\n"
               "step << Shaman\n#optional\n.bindlocation 513,1\n.cooldown spell,556,>0,1\n.subzoneskip 513\n"
               ".zoneskip Wetlands\n.zoneskip Loch Modan\n.zoneskip Dun Morogh\n"
               ".zoneskip Ironforge\n.zoneskip Stormwind City\n.cast 556 >>Use Astral Recall to Theramore if available\n"
               "step\n#optional\n.zoneskip Tanaris,1\n.zoneskip Dustwallow Marsh\n.zoneskip Ironforge\n.zoneskip Stormwind City\n"
               ".goto Tanaris,51.006,29.345\n.fly Theramore >>Use this flight only if already learned; otherwise continue by road\n.target Bera Stonehammer\n"
               "step\n>>Without a usable hearth or flight, follow the road from Tanaris through Thousand Needles, take the Great Lift to the Barrens, "
               "then follow the road into Dustwallow Marsh and Theramore. Avoid the Horde guards at the lift; wait for a clear approach. "
               "If resuming in Moonglade, return through Timbermaw Hold to Felwood, follow the roads south through Ashenvale and the Barrens to Dustwallow Marsh. "
               "From Theramore, take the boat to Menethil Harbor. " + road +
               " If already in Stormwind, use the Deeprun Tram to Ironforge. If resuming along this journey, continue from your current zone.\n"
               ".zone Ironforge >>Reach Ironforge by ordinary travel or an available learned teleport\n" + trainer)
        e.replace(old.rstrip("\n"), new.rstrip("\n"), reason)
    if re.search(r"\.(?:accept|turnin|abandon|isOnQuest|isQuestTurnedIn) 1122[23]\b", e.body):
        raise ValueError("Residual unavailable Jaina action")


def repair(body, family, names):
    e = Editor(body)
    group = re.search(r"^#group (.+)$", body, re.M)[1]
    faction = "A" if group.endswith("(A)") else "H"
    for old, new in FLIGHTS[faction].items():
        e.lines(r"^[ \t]*\.(?:fp|fly) " + re.escape(old) + r"(?=\s*(?:>>|<<|$))[^\n]*",
                lambda line, old=old, new=new: line.replace(old, new, 1),
                "Use the exact faction node in bundled WotLK flightData; preserve learned-flight checks.")
    for old, new in WAYPOINTS.items():
        e.lines(r"^[ \t]*\.goto " + re.escape(old) + r"(?=\s*(?:>>|<<|$))[^\n]*",
                lambda line, old=old, new=new: line.replace(old, new, 1),
                "Repair the individually reviewed split decimal/redundant field; retain the intended radius and optional flag.")
    e.lines(r"^[ \t]*\.zoneskip 209,1[^\n]*", lambda line: line.replace(".zoneskip 209,1", ".subzoneskip 209,1"),
            "Shadowfang Keep uses AreaTable 209, not a supported legacy UI map ID.")
    for match in list(re.finditer(r"(?m)^([ \t]*)\.zoneskip 304\n[ \t]*\.zoneskip 305\n", e.body)):
        if match[0] in e.body:
            e.replace(match[0], match[1] + ".subzoneskip 796\n", "Scarlet Monastery uses localized AreaTable 796; preserve dungeon branch.")
    e.lines(r"^[ \t]*\.subzone (?:209|796),2[^\n]*", lambda line: line.replace(",2", "", 1),
            "Instance arrival must work with either a dungeon map or no map; require the actual localized subzone.")
    e.lines(r"^subzone 2618[^\n]*", lambda line: "." + line, "Restore the missing directive dot at the Felwood cave exit.")
    e.lines(r"^[ \t]*\.line Feralas,[^\n]*,$", lambda line: line[:-1], "Remove the reviewed Feralas polyline's empty final field.")
    e.lines(r"^[ \t]*\.isOnQuest 5867\s*$", lambda line: line.replace("5867", "1195"),
            "5867 is the Etched Phial item; the authored Sacred Flame quest is 1195.")
    # Do this before title-only corrections: Classic 1218 changes objectives.
    if family == "classic":
        for step in re.findall(r"(?ms)^step\b.*?(?=^step\b|\Z)", e.body):
            if re.search(r"\.collect 3713,3,1218,1\b", step):
                if re.search(r"\.(?:accept|turnin|complete|vendor|trainer)\b", step):
                    raise ValueError("Unexpected shared action in obsolete spice purchase")
                e.replace(step, "", "Quest 1218 requires frog legs in Wrath, not purchased spices; preserve unrelated spice purchases.")
        for step in re.findall(r"(?ms)^step\b.*?(?=^step\b|\Z)", e.body):
            if ".accept 1218 " not in step:
                continue
            if ".turnin 1218 " not in step or ".accept 1206 " not in step:
                raise ValueError("Unexpected Classic Jarl sequence")
            pickup = re.sub(r"(?m)^.*\.(?:turnin 1218|accept 1206)\b[^\n]*\n", "", step)
            pickup = pickup.replace("Accept Soothing Spices", "Accept Marsh Frog Legs")
            objective = ("step\n.isOnQuest 1218\n.goto Dustwallow Marsh,55.4,26.3,0\n"
                         ">>Kill Giant Marsh Frogs around Witch Hill and loot ten Marsh Frog Legs before returning to Jarl.\n"
                         ".complete 1218,1 --Marsh Frog Legs (10)\n.mob Giant Marsh Frog\n")
            reward = re.sub(r"(?m)^.*\.accept 1218\b[^\n]*\n", "", step).replace("Turn in Soothing Spices", "Turn in Marsh Frog Legs")
            e.replace(step, pickup + objective + reward,
                      "AC quest1218 requires item33202 x10; preserve Jarl's reward and prerequisite-gated quest1206 pickup.")
    for step in re.findall(r"(?ms)^step\b.*?(?=^step\b|\Z)", e.body):
        if ".turnin 64038" in step:
            if ".isOnQuest 64038" not in step or "#optional" not in step:
                raise ValueError("Unexpected legacy Dark Portal block")
            e.replace(step, "", "Remove only the unavailable optional quest64038 block; retain the following ordinary10119 pickup and Hellfire progression.")
    repair_jaina(e, family)
    # Canonical titles are operational data on a cold 3.3.5 quest cache.
    for line in list(dict.fromkeys(re.findall(r"^[ \t]*\.(?:accept|turnin) \d+[^\n]*", e.body, re.M))):
        m = re.match(r"(?P<head>\s*\.(?P<kind>accept|turnin) (?P<id>\d+).*?>>\s*)(?P<title>.*?)(?P<tail>\s*(?:<<|--).*)?$", line)
        if not m or int(m["id"]) not in names:
            continue
        title = re.sub(r"^(?:Accept|Turn in)\s+", "", m["title"], flags=re.I).strip()
        canonical = names[int(m["id"])]
        if title == canonical and (m["kind"] != "accept" or re.match(r"Accept\s+", m["title"])):
            continue
        if m["kind"] == "turnin" and (title.startswith(canonical) or not re.match(r"Turn in\b", m["title"], re.I)):
            # Reward prose can legitimately include additional instructions.
            continue
        advice = ""
        if "only if" in title or "only with" in title or "(optional" in title:
            advice = ">>Optional: " + title + ".\n"
        new = advice + m["head"] + ("Accept " if m["kind"] == "accept" else "Turn in ") + canonical + (m["tail"] or "")
        e.replace(line + "\n", new + "\n", f"Use pinned Wrath quest{m['id']} title verbatim for cold-cache matching; keep optional advice outside the title.")
    # Name-only NPC correction, after the quest's full title has been corrected.
    e.lines(r"^[ \t]*(?:>>|\.target )[^\n]*Maatparm[^\n]*", lambda line: line.replace("Maatparm", "Jessera of Mac'Aree"),
            "Pinned creature17663 is Jessera of Mac'Aree in Wrath; preserve the existing quest and vendor stops.")
    return e


def main(args):
    if args.output.exists():
        raise ValueError("Use a fresh candidate directory")
    facts = read(args.facts)
    names = {q["id"]: q["name"] for q in facts["quests"]}
    upstream = read(args.parents / "upstream.json")
    curated = read(args.parents / "curated.json")
    recipes = {"upstream": upstream, "curated": curated}
    entries = {kind: {e["id"]: e for e in data["guides"]} for kind, data in recipes.items()}
    records = {r["key"]: r for r in read(args.candidate / "upstream/compatibility-report.json")["guides"]}
    records.update({r["key"]: r for r in read(args.candidate / "curated/selected.json")})
    changes, counts = [], {}
    for family, file in (("classic", "Hardcore-Classic.lua"), ("tbc", "Hardcore-TBC.lua"), ("curated", "Hardcore-Curated.lua")):
        text = (args.guides / file).read_text(encoding="utf-8")
        count = 0
        for m in re.finditer(r"RXPGuides\.RegisterGuide\(\[\[(.*?)\]\]\)", text, re.S):
            body = m[1].strip() + "\n"
            group = re.search(r"^#group (.+)$", body, re.M)[1]
            name = re.search(r"^#name (.+)$", body, re.M)[1]
            record = records[group + "|" + name]
            if sha(body) != record["outputHash"]:
                raise ValueError(f"Candidate hash differs: {name}")
            e = repair(body, family, names)
            kind = "curated" if family == "curated" else "upstream"
            source = record.get("source", record.get("id"))
            entry = entries[kind].get(source)
            if e.edits:
                if entry is None:
                    entry = {"id": source, "sourceHash": record["sourceHash"], "replacements": []}
                    recipes[kind]["guides"].append(entry)
                    entries[kind][source] = entry
                if entry["sourceHash"] != record["sourceHash"]:
                    raise ValueError("Parent source differs")
                entry["replacements"].extend(e.edits)
                if kind == "curated":
                    entry["reviewedHash"] = ""
                changes.append({"family": family, "id": source, "before": sha(body), "after": sha(e.body), "edits": e.edits})
            count += 1
        counts[family] = count
    if counts != {"classic": 92, "tbc": 77, "curated": 89}:
        raise ValueError("Chapter inventory differs")
    args.output.mkdir(parents=True)
    for kind, data in {**recipes, "repairs": changes}.items():
        with (args.output / (kind + ".json")).open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(data, stream, ensure_ascii=True, separators=(",", ":"))
            stream.write("\n")
    print(f"Composed {sum(len(c['edits']) for c in changes)} exact repairs in {len(changes)} chapters; not publication approval.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parents", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--guides", type=Path, required=True)
    parser.add_argument("--facts", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    main(parser.parse_args())
