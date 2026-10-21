"""Path-independent regressions for committed Wrath facts and SQL extraction."""
import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("quest_facts", ROOT / "tools/extract_hardcore_quest_facts335.py")
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)


class QuestFacts(unittest.TestCase):
    def test_selected_sql_rows_are_decoded_not_executed(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fixture.sql"
            path.write_text("CREATE TABLE `fixture` (\n  `id` int,\n  `name` text,\n  `count` int\n);\n"
                            "(1,'Jarl\\'s \\\"legs\\\"',10),\n(2,'unselected',3);\n", encoding="utf-8")
            self.assertEqual(list(extractor.read_rows(path, lambda q: q == 1)),
                             [{"id": 1, "name": 'Jarl\'s "legs"', "count": 10}])
            path.write_text("CREATE TABLE `fixture` (\n  `id` int\n);\n(1,2);\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                list(extractor.read_rows(path, lambda _: True))

    def test_committed_targeted_facts(self):
        facts = json.loads((ROOT / "tools/data/Hardcore-QuestFacts335.json").read_text(encoding="utf-8"))
        self.assertEqual(facts["schemaVersion"], 1)
        self.assertEqual(facts["sourceRevision"], extractor.REVISION)
        self.assertEqual(len(facts["sources"]), 8)
        for table, digest in facts["sources"].items():
            self.assertRegex(table, r"^[a-z_]+$")
            self.assertRegex(digest, r"^[a-f0-9]{64}$")
        names = {q["id"]: q["name"] for q in facts["quests"]}
        self.assertEqual(len(names), len(facts["quests"]))
        self.assertEqual(names[1218], "Marsh Frog Legs")
        self.assertEqual(names[9648], "Mac'Aree Mushroom Menagerie")
        self.assertIn(64038, facts["absent"])
        detail = next(q for q in facts["details"] if q["ID"] == 1218)
        self.assertEqual((detail["RequiredItemId1"], detail["RequiredItemCount1"]), (33202, 10))
        self.assertEqual(next(q for q in facts["prerequisites"] if q["ID"] == 1206)["PrevQuestID"], 1218)
        for table, rows in facts["relations"].items():
            self.assertFalse(any(q["quest"] in (11222, 11223) for q in rows), table)
        self.assertIn({"id": 4968, "quest": 11142}, facts["relations"]["creature_questender"])
        self.assertIn({"id": 17663, "name": "Jessera of Mac'Aree"}, facts["npcs"])
        # Action62 is SmartAI teleport. Combat spell20682 is not evidence of a
        # player-facing Stormwind transport and must not be mistaken for one.
        self.assertFalse(any(r["action_type"] == 62 for r in facts["jainaActions"]))
        text = json.dumps(facts)
        self.assertIsNone(re.search(r"[A-Za-z]:\\|CREATE TABLE|INSERT INTO", text))


if __name__ == "__main__":
    unittest.main()
