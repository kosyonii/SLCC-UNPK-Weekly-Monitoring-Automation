# SLCC UNPK Weekly Monitoring Automation

BigQuery 추출부터 검수, SharePoint 반영용 산출물 생성까지 자동화하는 Python 파이프라인.
SharePoint 반영, 파일명 변경, Slack 알림은 수동으로 진행한다 (Phase 1 범위).

## 설치

```bash
pip install -r requirements.txt
cp .env.example .env  # 값 채워넣기
gcloud auth application-default login  # 최초 1회
```

## 실행

```bash
python main.py
```

## 구조

```
.
├── config.py            # 설정값 로드
├── db_connector.py      # BigQuery 연결
├── extract.py           # 쿼리 실행 및 추출
├── validate.py          # 검수 로직
├── phase_check.py       # phase_name 확인
├── output_generator.py  # 미리보기 산출물 생성
├── outlook_notifier.py  # 에러/이상치 메일 발송
├── duplicate_guard.py   # 중복 실행 방지
├── logger.py            # 실행 로그
├── main.py              # CLI 오케스트레이터
├── sql/unpk_query.sql   # BigQuery 쿼리 (Phase 변경 시에만 직접 수정)
├── requirements.txt
├── .env.example
└── CHANGELOG.md
```

## 검수 규칙

- 날짜: 월요일 실행 시 직전 금~일 3일치, 그 외엔 전일 하루 (공휴일 미고려)
- subsidiary/region/scope: 전 행이 Global/global 이어야 함
- 행 수: 하루당 2000~2400건 기준, 추출 일수를 곱해 비교 (월요일 3일치면 6000~7200). 벗어나면 이상치로 플래그. 기준값은 `.env`의 `ROW_COUNT_MIN` / `ROW_COUNT_MAX`로 조정

## Phase 변경

`sql/unpk_query.sql` 의 `AS phase_name` 줄을 직접 수정한 뒤 실행한다. 실행 시 현재 값을 보여주고 확인을 받는다.

## 자동화 범위

BigQuery 추출 → 검수 → 미리보기 산출물 생성까지만 자동화한다. SharePoint append, 파일명 변경, Slack 알림은 수동으로 진행한다.
