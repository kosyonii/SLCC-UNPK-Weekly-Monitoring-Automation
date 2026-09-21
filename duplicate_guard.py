"""
당일 중복 실행 방지.
실행 로그(logs/run_log.jsonl)에서 오늘 날짜로 이미 성공 처리된 기록이 있는지 확인한다.
"""
from __future__ import annotations

import json
from datetime import date

from config import LOG_DIR

RUN_LOG_PATH = LOG_DIR / "run_log.jsonl"


def already_ran_today(today: date | None = None) -> bool:
    today = today or date.today()
    if not RUN_LOG_PATH.exists():
        return False

    with RUN_LOG_PATH.open(encoding="utf-8") as f:
        for line in f:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("date") == today.isoformat() and entry.get("status") == "success":
                return True

    return False
