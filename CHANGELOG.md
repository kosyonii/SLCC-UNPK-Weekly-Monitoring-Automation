# Changelog

## [Unreleased]

### 변경
- 복붙용 산출물 CSV에 헤더 행 포함 (기존: 헤더 없음)
- 복붙용 산출물 파일명을 `<추출날짜YYMMDD>_UNPK_Monitoring.csv`로 단순화
- 행 수 검수를 하루당 기준으로 변경: 월요일(3일치)에는 임계값에 3을 곱해 비교

### 추가
- requirements.txt에 db-dtypes 추가 (BigQuery 결과 DataFrame 변환에 필요)

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
