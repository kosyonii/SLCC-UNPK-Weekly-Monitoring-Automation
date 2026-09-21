"""
추출 기간 결정과 사람 확인.

기본 규칙 (마지막 성공 실행 기준):
  시작일 = 마지막으로 성공한 실행의 period_end + 1일
  종료일 = 어제 (Asia/Seoul 기준 D-1)

공휴일/휴무 등으로 실행하지 않은 날이 있어도 그 날짜가 빠지지 않는다.
성공 기록(period_end 포함)이 없으면 요일 규칙(월요일=직전 금~일, 그 외=전일)으로 되돌린다.

주의: 로그의 success는 미리보기 산출물을 만들었다는 뜻이지 SharePoint에 append했다는 뜻이 아니다.
그래서 실행 전에 항상 기간을 사람에게 보여주고 확인받으며, 시작일을 직접 고칠 수 있게 한다.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from config import MAX_PERIOD_DAYS
from logger import RUN_LOG_PATH

# 쿼리(sql/unpk_query.sql)의 기준 시간대와 동일해야 한다.
KST = ZoneInfo("Asia/Seoul")


@dataclass(frozen=True)
class Period:
    start: date
    end: date
    note: str  # 기간을 이렇게 잡은 근거 (사람에게 보여주는 설명)

    @property
    def days(self) -> int:
        return (self.end - self.start).days + 1


def today_kst() -> date:
    return datetime.now(KST).date()


def weekday_rule_start(today: date) -> date:
    """요일 규칙의 시작일. 월요일이면 직전 금요일, 그 외엔 전일."""
    if today.weekday() == 0:  # Monday
        return today - timedelta(days=3)
    return today - timedelta(days=1)


def _read_success_periods() -> list[tuple[date, date]]:
    """로그에서 기간(period_start/period_end)이 기록된 성공 실행만 읽는다."""
    if not RUN_LOG_PATH.exists():
        return []

    periods: list[tuple[date, date]] = []
    with RUN_LOG_PATH.open(encoding="utf-8") as f:
        for line in f:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("status") != "success":
                continue
            start, end = entry.get("period_start"), entry.get("period_end")
            if not (start and end):
                continue  # 기간 기록이 도입되기 전의 로그
            try:
                periods.append((date.fromisoformat(start), date.fromisoformat(end)))
            except ValueError:
                continue
    return periods


def resolve_period(today: date | None = None) -> Period:
    today = today or today_kst()
    end = today - timedelta(days=1)

    periods = _read_success_periods()
    if not periods:
        return Period(
            start=weekday_rule_start(today),
            end=end,
            note="성공 실행 기록이 없어 요일 규칙 적용 (월요일=직전 금~일, 그 외=전일)",
        )

    # 종료일이 가장 늦은 성공 실행 (같으면 로그상 나중 것)
    last_start, last_end = periods[0]
    for start, end_ in periods[1:]:
        if end_ >= last_end:
            last_start, last_end = start, end_

    if last_end == end:
        return Period(
            start=last_start,
            end=last_end,
            note=f"이미 {last_end}까지 처리됨, 직전 성공 기간을 재추출",
        )
    if last_end > end:
        return Period(
            start=weekday_rule_start(today),
            end=end,
            note=f"마지막 성공 기록의 종료일({last_end})이 어제보다 늦어 요일 규칙 적용",
        )

    return Period(
        start=last_end + timedelta(days=1),
        end=end,
        note=f"마지막 성공 실행의 종료일({last_end}) 다음 날부터 어제까지",
    )


def confirm_period(period: Period, max_days: int = MAX_PERIOD_DAYS) -> Period | None:
    """
    추출 기간을 보여주고 확인받는다.
    y=그대로 진행, n=중단(None 반환), YYYY-MM-DD=시작일을 직접 지정하고 다시 확인.
    """
    original_start = period.start
    while True:
        print(f"[기간 확인] 이번 추출 기간: {period.start} ~ {period.end} ({period.days}일)")
        print(f"  근거: {period.note}")
        if period.days > max_days:
            print(f"  [경고] {max_days}일을 넘는 긴 기간입니다. 누락 없이 맞는 기간인지 확인하세요.")
        if period.start > original_start:
            print(
                f"  [경고] 시작일을 {original_start}보다 늦췄습니다. "
                f"{original_start}~{period.start - timedelta(days=1)} 구간이 누락될 수 있습니다."
            )

        answer = input(
            "이 기간이 맞습니까? (y=진행 / n=중단 / 시작일 직접 입력 YYYY-MM-DD): "
        ).strip()
        if answer.lower() == "y":
            return period
        if answer.lower() == "n":
            return None

        try:
            new_start = date.fromisoformat(answer)
        except ValueError:
            print("y, n 또는 YYYY-MM-DD 형식의 날짜를 입력하세요.")
            continue
        if new_start > period.end:
            print(f"시작일({new_start})이 종료일({period.end})보다 늦을 수 없습니다.")
            continue
        period = Period(start=new_start, end=period.end, note="사용자가 시작일을 직접 지정")
