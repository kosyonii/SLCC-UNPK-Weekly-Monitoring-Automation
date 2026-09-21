"""
BigQuery 쿼리 실행 및 결과 추출.

sql/unpk_query.sql 은 쿼리 내부에 D-1 데이터 적재 여부 확인(check_result CTE)이
이미 포함되어 있어, 적재가 안 된 경우 쿼리 스스로 ERROR()를 던진다.
이 모듈은 그 에러를 그대로 캐치해 상위(main.py)로 전달한다.
"""
from __future__ import annotations

import pandas as pd
from google.api_core.exceptions import BadRequest

from config import SQL_QUERY_PATH
from db_connector import get_client


class DataNotReadyError(Exception):
    """D-1 데이터 미적재 등, 쿼리 자체 검증에서 발생한 에러."""


def load_query() -> str:
    return SQL_QUERY_PATH.read_text(encoding="utf-8")


def run_extraction() -> pd.DataFrame:
    """
    쿼리를 실행하고 결과를 DataFrame으로 반환한다.

    Raises:
        DataNotReadyError: 쿼리 내 ERROR()가 발생한 경우 (예: D-1 데이터 미적재)
    """
    client = get_client()
    query = load_query()

    try:
        job = client.query(query)
        df = job.result().to_dataframe()
    except BadRequest as exc:
        # 쿼리 내 ERROR() 메시지를 그대로 보존해서 올린다.
        raise DataNotReadyError(str(exc)) from exc

    return df
