"""
추출 결과 검수 로직.

- 날짜 범위 검증 (월요일=직전 금~일 3일치, 그 외=전일 하루, 공휴일 미고려)
- subsidiary/region/scope = Global/global 100% 검증
- 행 수 2000~2400 범위 검증
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, timedelta

import pandas as pd

from config import ROW_COUNT_MAX, ROW_COUNT_MIN


@dataclass
class ValidationResult:
    passed: bool
    issues: list[str] = field(default_factory=list)

    def add(self, issue: str) -> None:
        self.passed = False
        self.issues.append(issue)


def expected_date_range(today: date | None = None) -> tuple[date, date]:
    """
    오늘 날짜 기준 예상 추출 날짜 범위를 계산한다.
    월요일(weekday()==0)이면 직전 금~일 3일치, 그 외엔 전일 하루.
    """
    today = today or date.today()
    yesterday = today - timedelta(days=1)

    if today.weekday() == 0:  # Monday
        start = today - timedelta(days=3)  # Friday
    else:
        start = yesterday

    return start, yesterday


def _date_span(start: date, end: date) -> set[date]:
    return {start + timedelta(days=i) for i in range((end - start).days + 1)}


def validate_dates(df: pd.DataFrame, today: date | None = None) -> ValidationResult:
    result = ValidationResult(passed=True)
    expected_start, expected_end = expected_date_range(today)
    expected_span = _date_span(expected_start, expected_end)

    actual_dates = set(pd.to_datetime(df["date"]).dt.date)

    unexpected = sorted(actual_dates - expected_span)
    if unexpected:
        result.add(f"예상 범위({expected_start}~{expected_end}) 밖의 날짜 발견: {unexpected}")

    missing = sorted(expected_span - actual_dates)
    if missing:
        result.add(f"예상 범위 내 누락된 날짜: {missing}")

    return result


def validate_global_scope(df: pd.DataFrame) -> ValidationResult:
    result = ValidationResult(passed=True)

    bad_subsidiary = df.loc[df["subsidiary"] != "Global", "subsidiary"].unique()
    bad_region = df.loc[df["region"] != "Global", "region"].unique()
    bad_scope = df.loc[df["scope"] != "global", "scope"].unique()

    if len(bad_subsidiary):
        result.add(f"subsidiary != 'Global' 값 발견: {list(bad_subsidiary)}")
    if len(bad_region):
        result.add(f"region != 'Global' 값 발견: {list(bad_region)}")
    if len(bad_scope):
        result.add(f"scope != 'global' 값 발견: {list(bad_scope)}")

    return result


def validate_row_count(df: pd.DataFrame) -> ValidationResult:
    result = ValidationResult(passed=True)
    count = len(df)

    if not (ROW_COUNT_MIN <= count <= ROW_COUNT_MAX):
        result.add(
            f"행 수 {count}건이 정상 범위({ROW_COUNT_MIN}~{ROW_COUNT_MAX})를 벗어남 — 이상치로 플래그"
        )

    return result


def run_all_validations(df: pd.DataFrame) -> dict[str, ValidationResult]:
    return {
        "date": validate_dates(df),
        "global_scope": validate_global_scope(df),
        "row_count": validate_row_count(df),
    }
