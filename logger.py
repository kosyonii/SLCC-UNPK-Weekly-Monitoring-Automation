"""
실행 로그 관리.
실행 로그는 logs/run_log.jsonl 에 한 줄씩(JSON Lines) 누적한다.
CHANGELOG.md는 코드 변경 이력을 별도로 기록하며, 이 모듈이 아닌 커밋 시점에 수동 관리한다.
"""
from __future__ import annotations

import json
import time
from datetime import date, datetime

from config import LOG_DIR

RUN_LOG_PATH = LOG_DIR / "run_log.jsonl"


def log_run(
    status: str,
    row_count: int | None = None,
    error: str | None = None,
    elapsed_seconds: float | None = None,
    today: date | None = None,
    period_start: date | None = None,
    period_end: date | None = None,
) -> None:
    """period_start/end는 추출 기간. status가 success인 기록의 period_end가 다음 실행의 시작일 기준이 된다."""
    entry = {
        "date": (today or date.today()).isoformat(),
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "status": status,  # "success" | "failed" | "aborted"
        "row_count": row_count,
        "error": error,
        "elapsed_seconds": elapsed_seconds,
        "period_start": period_start.isoformat() if period_start else None,
        "period_end": period_end.isoformat() if period_end else None,
    }
    with RUN_LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


class Timer:
    """with 블록으로 감싸 단계별 소요시간을 잰다."""

    elapsed: float = 0.0

    def __enter__(self) -> "Timer":
        self._start = time.monotonic()
        return self

    def __exit__(self, *exc_info) -> None:
        self.elapsed = time.monotonic() - self._start
