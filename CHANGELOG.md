# Changelog

## [0.1.0] - 2026-09-21

### 추가
- 프로젝트 초기 스켈레톤 구성
- BigQuery 연결 모듈(db_connector.py) 구현
- D-1 데이터 적재 확인이 포함된 추출 쿼리 통합(sql/unpk_query.sql)
- 검수 로직(validate.py) 구현: 날짜 범위, Global 검증, 행수 범위 검증
- Phase 확인 체크포인트(phase_check.py) 구현
- 미리보기 산출물 생성(output_generator.py) 구현
- Outlook 알림(outlook_notifier.py) 구현: win32com 기반
- 중복 실행 방지(duplicate_guard.py) 구현
- 실행 로그 기록(logger.py) 구현
- CLI 오케스트레이터(main.py) 구현
