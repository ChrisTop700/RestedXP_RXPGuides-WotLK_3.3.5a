"""Extract small, attributed facts from SQL text; never connect to a database.

Only regeneration needs an explicitly supplied AzerothCore checkout. CI reads
the committed result. Dump headers, account data and machine paths are omitted.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

REVISION = "93ab9ad63e7e75cc5f41dd7955a95d58776d3752"
TOKEN = re.compile(r"(?:\(|,)(?P<v>'(?:\\.|''|[^'\\])*'|NULL|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)(?=,|\))")
QUEST_DIRECTIVE = re.compile(r"^\s*\.(?:accept|turnin|complete|abandon|isOnQuest|isNotOnQuest|isQuestAvailable|isQuestComplete|isQuestNotComplete|isQuestTurnedIn|skipOnQuest|acceptmultiple)\s+(-?\d+)", re.M)


def decode(value):
    if value == "NULL":
        return None
    if not value.startswith("'"):
        return float(value) if any(c in value for c in ".eE") else int(value)
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "r": "\r", "t": "\t", "0": "\0"}.get(m[1], m[1]), value[1:-1].replace("''", "'"))


def read_rows(path, select):
    columns, schema = [], False
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            if line.startswith("CREATE TABLE "):
                if columns:
                    raise ValueError("Multiple schemas")
                schema = True
            elif schema:
                field = re.match(r"\s+`([^`]+)`\s", line)
                if field:
                    columns.append(field[1])
                elif line.startswith(")"):
                    schema = False
            elif line.startswith("("):
                prefix = re.match(r"\((-?\d+),", line)
                if not prefix or not columns:
                    raise ValueError("Unsupported SQL row")
                if not select(int(prefix[1])):
                    continue
                fields, pos = [], 0
                while (match := TOKEN.match(line, pos)):
                    fields.append(decode(match["v"]))
                    pos = match.end()
                if len(fields) != len(columns) or line[pos:].strip() not in (");", "),"):
                    raise ValueError(f"Unsupported selected row {prefix[1]} in {path.name}")
                yield dict(zip(columns, fields))
    if schema or not columns:
        raise ValueError("Incomplete schema")


def extract(sql_root, guide_root):
    needed = {1218, 1206, 11142, 11222, 11223, 1195, 10119, 9648, 64038, 5867}
    for guide in sorted(guide_root.glob("*.lua")):
        needed.update(abs(int(m[1])) for m in QUEST_DIRECTIVE.finditer(guide.read_text(encoding="utf-8")))
    sources = {}

    def rows(table, predicate):
        path = sql_root / (table + ".sql")
        sources[table] = hashlib.sha256(path.read_bytes()).hexdigest()
        return list(read_rows(path, predicate))

    quests = rows("quest_template", lambda q: q in needed)
    facts = [{"id": q["ID"], "name": q["LogTitle"]} for q in quests]
    details = []
    detailed_ids = {1218, 1206, 11142, 11222, 11223, 1195, 10119, 9648}
    for q in quests:
        if q["ID"] in detailed_ids:
            fields = ["ID", "LogTitle", "MinLevel", "QuestLevel", "AllowableRaces", "RewardNextQuest"]
            fields += [k for k in q if k.startswith(("RequiredNpcOrGo", "RequiredItem", "ObjectiveText"))]
            details.append({k: q[k] for k in fields if k in q})
    relations = {}
    for table in ("creature_queststarter", "creature_questender", "gameobject_queststarter", "gameobject_questender"):
        relations[table] = sorted((r for r in rows(table, lambda _: True) if r["quest"] in detailed_ids), key=lambda r: (r["quest"], r["id"]))
    addons = rows("quest_template_addon", lambda q: q in detailed_ids)
    npcs = rows("creature_template", lambda q: q in {4792, 4968, 17663})
    scripts = rows("smart_scripts", lambda q: q in {4968, 496800})
    # Record actions/conditions, not arbitrary scripts or dialogue prose.
    scripts = [{k: v for k, v in r.items() if k != "comment"} for r in scripts]
    return {
        "schemaVersion": 1, "sourceRevision": REVISION,
        "source": f"https://github.com/azerothcore/azerothcore-wotlk/tree/{REVISION}/data/sql/base/db_world",
        "attribution": "AzerothCore contributors; AGPL-3.0 source. Selected quest/name/relation facts only.",
        "scope": "Template presence is not proof a quest is offered. Targeted relation and script facts accompany changed Wrath instructions.",
        "sources": dict(sorted(sources.items())),
        "quests": sorted(facts, key=lambda r: r["id"]),
        "absent": sorted(needed - {q["ID"] for q in quests}),
        "details": sorted(details, key=lambda r: r["ID"]),
        "prerequisites": [{k: r[k] for k in ("ID", "PrevQuestID", "NextQuestID", "ExclusiveGroup")} for r in addons],
        "relations": relations,
        "npcs": [{"id": r["entry"], "name": r["name"]} for r in npcs],
        "jainaActions": scripts,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sql-root", type=Path, required=True)
    parser.add_argument("--guide-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = extract(args.sql_root, args.guide_root)
    locked = Path(__file__).resolve().parent / "data/Hardcore-QuestFacts335.json"
    if locked.exists():
        previous = json.loads(locked.read_text(encoding="utf-8"))
        if previous["sourceRevision"] != REVISION or previous["sources"] != result["sources"]:
            raise ValueError("Pinned SQL sources changed; explicit source review is required")
    with args.output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(result, stream, ensure_ascii=True, indent=2)
        stream.write("\n")
    print(f"Extracted {len(result['quests'])} quest names and targeted Wrath facts; {len(result['absent'])} absent IDs.")
