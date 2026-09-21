"""
검수 통과 데이터를 SharePoint에 그대로 붙여넣을 수 있는 형태로 저장하고,
오늘 날짜 기준 예상 파일명을 계산한다.
"""
from __future__ import annotations

from datetime import date

import pandas as pd

from config import EXPECTED_COLUMNS, OUTPUT_DIR

# 접미사는 통상 유지되는 값이며, 바뀌어야 하는 주에는 사람이 이 값을 직접 고친다.
FILENAME_SUFFIX = "26.2H UNPK Weekly Monitoring +7W_v2.0"


def build_expected_filename(today: date | None = None) -> str:
    today = today or date.today()
    yymmdd = today.strftime("%y%m%d")
    return f"{yymmdd}_{FILENAME_SUFFIX}"


def save_copy_paste_output(df: pd.DataFrame, today: date | None = None) -> str:
    """
    헤더 없이, SharePoint 파일과 동일한 컬럼 순서로 CSV를 저장한다.
    반환값은 저장된 파일 경로(문자열).
    """
    ordered = df[EXPECTED_COLUMNS]
    filename = f"{build_expected_filename(today)}_append.csv"
    path = OUTPUT_DIR / filename
    ordered.to_csv(path, header=False, index=False, encoding="utf-8-sig")
    return str(path)


def print_summary(df: pd.DataFrame, today: date | None = None) -> None:
    print("=== 미리보기 요약 ===")
    print(f"행 수: {len(df)}")
    print(f"날짜 범위: {df['date'].min()} ~ {df['date'].max()}")
    print(f"예상 파일명: {build_expected_filename(today)}")
