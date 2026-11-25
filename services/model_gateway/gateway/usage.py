"""Content-free metering for authenticated v3 and voice-preview provider calls."""
import asyncio
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass
import math
import os
import time


@dataclass
class Measurement:
    quantity: float | None = None


_active = ContextVar('provider_measurement', default=None)
# Configuration is CNY per thousand tokens, characters, or seconds, respectively.
MODELS = {'model': 'deepseek_model', 'tts': 'voice_model', 'asr': 'asr_model'}


def record_tokens(value):
    meter = _active.get()
    if meter is not None and type(value) is int and value >= 0:
        meter.quantity = value


def initialize(db):
    db.executescript("""CREATE TABLE IF NOT EXISTS provider_usage(
        id INTEGER PRIMARY KEY, created INTEGER NOT NULL, mode TEXT NOT NULL,
        kind TEXT NOT NULL, model TEXT NOT NULL, outcome TEXT NOT NULL,
        quantity REAL, rate REAL);
        CREATE INDEX IF NOT EXISTS provider_usage_by_time ON provider_usage(created);
    """)


@contextmanager
def call(store, settings, kind):
    meter = Measurement()
    if store is None:
        yield meter
        return
    mode = settings.mode
    try:
        rate = float(os.getenv('COMMUNITY_RATE_' + kind.upper(), ''))
        if not math.isfinite(rate) or rate < 0:
            rate = None
    except ValueError:
        rate = None
    with store.db:
        row = store.db.execute("""INSERT INTO provider_usage(created,mode,kind,model,outcome,rate)
            VALUES (?,?,?,?, 'running', ?)""",
            (int(time.time()), mode, kind, getattr(settings, MODELS[kind]), rate)).lastrowid
    outcome = 'failed'
    token = _active.set(meter)
    try:
        yield meter
        outcome = 'complete'
    except asyncio.CancelledError:
        outcome = 'interrupted'
        raise
    finally:
        _active.reset(token)
        with store.db:
            store.db.execute('UPDATE provider_usage SET quantity=?,outcome=? WHERE id=?',
                             (meter.quantity, outcome, row))


def totals(db, since, until):
    rows = db.execute("""SELECT mode,kind,model,count(*) AS calls,
        sum(outcome='failed') AS failed, sum(outcome='interrupted') AS interrupted,
        sum(outcome='running') AS unfinished, sum(quantity) AS quantity,
        sum(quantity IS NULL) AS unknown_quantity, sum(rate IS NULL) AS unknown_rate,
        CASE WHEN mode='mock' THEN 0 WHEN count(rate)=count(*) AND count(quantity)=count(*)
             THEN sum(rate*quantity/1000.0) END AS estimated_cny
        FROM provider_usage WHERE created BETWEEN ? AND ?
        GROUP BY mode,kind,model ORDER BY mode,kind,model""", (since, until))
    return [dict(row) for row in rows]
