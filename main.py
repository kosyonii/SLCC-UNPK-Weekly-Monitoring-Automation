"""
UNPK Weekly Monitoring 파이프라인 CLI 오케스트레이터.

실행 흐름 (설계 문서 기준):
  0. 중복 실행 방지
  1. BigQuery 데이터 추출 (+ phase_name 확인)
  2. 검수 (날짜 / Global / 행수)
  3. 미리보기 산출물 생성
  4. 로깅

SharePoint append / 파일명 변경 / Slack 알림은 이 스크립트의 범위 밖이며 수동으로 진행한다.
"""
from __future__ import annotations

import sys

from duplicate_guard import already_ran_today
from extract import DataNotReadyError, run_extraction
from logger import Timer, log_run
from outlook_notifier import send_alert
from output_generator import print_summary, save_copy_paste_output
from phase_check import confirm_phase
from validate import run_all_validations


def _prompt_continue(message: str) -> bool:
    answer = input(f"{message} 계속 진행할까요? (y/n): ").strip().lower()
    return answer == "y"


def main() -> int:
    # 0. 중복 실행 방지
    if already_ran_today():
        print("[경고] 오늘 이미 성공적으로 처리된 실행 기록이 있습니다.")
        if not _prompt_continue("그래도"):
            print("실행을 중단합니다.")
            return 0

    # 1-1. Phase 확인
    if not confirm_phase():
        print("Phase 값을 다시 확인한 뒤 재실행해주세요. (sql/unpk_query.sql 직접 수정)")
        return 0

    # 1. BigQuery 추출
    with Timer() as timer:
        try:
            df = run_extraction()
        except DataNotReadyError as exc:
            send_alert(subject="[UNPK] D-1 데이터 적재 미완료", body=str(exc))
            log_run(status="failed", error=str(exc))
            print(f"[중단] {exc}")
            return 1

    # 2. 검수
    validations = run_all_validations(df)
    failed = {name: result for name, result in validations.items() if not result.passed}

    if failed:
        issues_text = "\n".join(
            f"[{name}] " + "; ".join(result.issues) for name, result in failed.items()
        )
        send_alert(subject="[UNPK] 검수 실패 / 이상치 발견", body=issues_text)
        print("[검수 실패/이상치]")
        print(issues_text)
        if not _prompt_continue("그래도"):
            log_run(
                status="aborted",
                row_count=len(df),
                error=issues_text,
                elapsed_seconds=timer.elapsed,
            )
            return 0

    # 3. 미리보기 산출물 생성
    output_path = save_copy_paste_output(df)
    print_summary(df)
    print(f"복붙용 산출물 저장 위치: {output_path}")

    # 4. 로깅
    log_run(status="success", row_count=len(df), elapsed_seconds=timer.elapsed)

    print("\n여기까지 자동화 완료. 이후 SharePoint append / 파일명 변경 / Slack 알림은 수동으로 진행하세요.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
