"""
BigQuery 연결.
gcloud CLI 기반 OAuth(Application Default Credentials)를 사용한다.
최초 1회 `gcloud auth application-default login` 실행이 필요하며,
이후에는 캐싱된 토큰으로 재인증 없이 동작한다.
"""
from __future__ import annotations

from google.auth.exceptions import DefaultCredentialsError
from google.cloud import bigquery

from config import GCP_PROJECT_ID


def get_client() -> bigquery.Client:
    """
    BigQuery 클라이언트를 생성한다.

    인증 정보가 없으면(ADC 미설정) 안내 메시지와 함께 예외를 다시 던진다.
    """
    try:
        return bigquery.Client(project=GCP_PROJECT_ID)
    except DefaultCredentialsError as exc:
        raise RuntimeError(
            "BigQuery 인증 정보를 찾을 수 없습니다. "
            "터미널에서 `gcloud auth application-default login` 을 먼저 실행하세요."
        ) from exc
