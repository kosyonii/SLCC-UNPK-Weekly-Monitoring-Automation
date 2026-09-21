"""
파이프라인 전역 설정.
.env에서 값을 읽어 다른 모듈에 상수로 제공한다.
"""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

# --- GCP / BigQuery ---
GCP_PROJECT_ID: str = os.getenv("GCP_PROJECT_ID", "slcc-buzz-agent-dev")

# --- 검수 임계값 (하루당 행 수 기준) ---
ROW_COUNT_MIN: int = int(os.getenv("ROW_COUNT_MIN", "2000"))
ROW_COUNT_MAX: int = int(os.getenv("ROW_COUNT_MAX", "2400"))

# --- 알림 ---
OUTLOOK_RECIPIENT: str = os.getenv("OUTLOOK_RECIPIENT", "")

# --- 경로 ---
BASE_DIR: Path = Path(__file__).resolve().parent
SQL_QUERY_PATH: Path = BASE_DIR / os.getenv("SQL_QUERY_PATH", "sql/unpk_query.sql")
OUTPUT_DIR: Path = BASE_DIR / os.getenv("OUTPUT_DIR", "output")
LOG_DIR: Path = BASE_DIR / os.getenv("LOG_DIR", "logs")

OUTPUT_DIR.mkdir(exist_ok=True)
LOG_DIR.mkdir(exist_ok=True)

# 최종 결과 컬럼 순서 (SharePoint 파일과 동일해야 함)
EXPECTED_COLUMNS: list[str] = [
    "date", "series", "phase", "mentions",
    "product_yn", "sentiment_yn", "source_yn", "feature_yn",
    "product", "source_lv1", "source_lv2", "source_lv3", "htr",
    "feature_lv1", "feature_lv2", "sentiment",
    "subsidiary", "region", "scope",
]
