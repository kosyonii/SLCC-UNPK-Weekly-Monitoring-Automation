"""
쿼리 파일 내 phase_name 값을 확인하는 사람 확인 체크포인트.
값 변경이 필요하면 sql/unpk_query.sql 을 직접 수정하도록 안내만 하고,
자동 변경 로직은 후순위로 남겨둔다.
"""
from __future__ import annotations

import re

from config import SQL_QUERY_PATH

_PHASE_PATTERN = re.compile(r"'(?P<phase>[^']+)'\s+AS\s+phase_name", re.IGNORECASE)


def get_current_phase() -> str:
    text = SQL_QUERY_PATH.read_text(encoding="utf-8")
    match = _PHASE_PATTERN.search(text)
    if not match:
        raise RuntimeError(
            f"{SQL_QUERY_PATH} 에서 phase_name 값을 찾지 못했습니다. 쿼리 형식을 확인하세요."
        )
    return match.group("phase")


def confirm_phase(auto_confirm: bool = False) -> bool:
    """
    현재 phase_name 값을 보여주고 진행 여부를 확인받는다.
    Phase 변경이 필요하면 쿼리 파일을 직접 수정한 뒤 다시 실행해야 한다.
    """
    phase = get_current_phase()
    print(f"[Phase 확인] 현재 쿼리의 phase_name = '{phase}'")

    if auto_confirm:
        return True

    answer = input("이 값이 맞습니까? 그대로 진행할까요? (y/n): ").strip().lower()
    return answer == "y"
