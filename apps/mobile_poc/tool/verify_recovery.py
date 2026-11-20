"""Check synthetic SQLite snapshots before/after app and emulator restarts."""
import json
import sqlite3
import sys
from pathlib import Path


def read_snapshot(filename):
    db = sqlite3.connect(Path(filename).resolve().as_uri() + "?mode=ro", uri=True)
    try:
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        preferences = dict(db.execute("SELECT key, value FROM preferences"))
        assert preferences.get("fixture") == "100 messages; final message deliberately pending"
        assert preferences["selected"] == "yue"
        roles = db.execute("SELECT id, name, description FROM characters ORDER BY id").fetchall()
        rows = db.execute("SELECT id, character_id, author, text, status, reply_to FROM messages ORDER BY id").fetchall()
        assert len(roles) == 2 and len(rows) == 100
        assert [r[0] for r in rows] == list(range(1, 101))
        assert sum(r[1] == "xing" for r in rows) == 50
        assert sum(r[1] == "yue" for r in rows) == 50
        for i, row in enumerate(rows):
            assert row[3] == f"本地恢复验证样例 {i} · 中文🙂"
        return roles, rows
    finally:
        db.close()


def main():
    if len(sys.argv) != 4:
        raise SystemExit("Usage: python verify_recovery.py before.db after-app.db after-emulator.db")
    before_roles, before = read_snapshot(sys.argv[1])
    assert before[-1][4] in {"pending", "interrupted"}
    assert all(row[4] == "complete" for row in before[:-1])
    for filename in sys.argv[2:]:
        roles, rows = read_snapshot(filename)
        assert roles == before_roles
        assert rows[:-1] == before[:-1]
        expected = list(before[-1])
        expected[4] = "interrupted"
        assert rows[-1] == tuple(expected)
    print(json.dumps({"result": "passed", "snapshots": 3, "roles": 2,
        "messages": 100, "per_role": 50, "restored_selected_role": "yue",
        "pending_transition_observed_in_this_run": before[-1][4] == "pending",
        "final_reply_status": "interrupted", "lost_or_duplicated_messages": 0}, ensure_ascii=False))


if __name__ == "__main__":
    main()
