"""
추출 결과 검수 로직.

- 날짜 범위 검증 (period.py 가 정한 추출 기간 start~end 와 데이터의 날짜가 정확히 일치해야 함)
- subsidiary/region/scope = Global/global 100% 검증
- 행 수 검증 (하루당 2000~2400, 추출 일수만큼 곱해서 비교)
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


def _date_span(start: date, end: date) -> set[date]:
    return {start + timedelta(days=i) for i in range((end - start).days + 1)}


def validate_dates(df: pd.DataFrame, start: date, end: date) -> ValidationResult:
    result = ValidationResult(passed=True)
    expected_span = _date_span(start, end)

    actual_dates = set(pd.to_datetime(df["date"]).dt.date)

    unexpected = sorted(actual_dates - expected_span)
    if unexpected:
        result.add(f"예상 범위({start}~{end}) 밖의 날짜 발견: {unexpected}")

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


def validate_row_count(df: pd.DataFrame, start: date, end: date) -> ValidationResult:
    """ROW_COUNT_MIN/MAX는 하루당 기준이므로 추출 기간의 일수를 곱해 비교한다."""
    result = ValidationResult(passed=True)
    count = len(df)

    days = (end - start).days + 1
    total_min = ROW_COUNT_MIN * days
    total_max = ROW_COUNT_MAX * days

    if not (total_min <= count <= total_max):
        result.add(
            f"행 수 {count}건이 정상 범위({total_min}~{total_max}, "
            f"하루 {ROW_COUNT_MIN}~{ROW_COUNT_MAX} x {days}일)를 벗어남 — 이상치로 플래그"
        )

    return result


def run_all_validations(df: pd.DataFrame, start: date, end: date) -> dict[str, ValidationResult]:
    return {
        "date": validate_dates(df, start, end),
        "global_scope": validate_global_scope(df),
        "row_count": validate_row_count(df, start, end),
    }
