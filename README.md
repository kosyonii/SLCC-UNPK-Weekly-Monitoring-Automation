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
├── period.py            # 추출 기간 결정 및 확인 프롬프트
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

## 추출 기간

공휴일 등으로 실행하지 않은 날이 있어도 날짜가 빠지지 않도록, 기간은 요일이 아니라 **마지막 성공 실행 기준**으로 정한다.

- 시작일 = 마지막 성공 실행의 종료일(`logs/run_log.jsonl`의 `period_end`) + 1일
- 종료일 = 어제 (Asia/Seoul 기준)
- 성공 기록이 없으면 요일 규칙으로 되돌린다 (월요일=직전 금~일, 그 외=전일)
- 오늘 이미 처리했다면 직전 성공 기간을 그대로 재추출한다

실행할 때마다 계산된 기간과 근거를 보여주고 확인을 받는다.

- `y` 진행 / `n` 중단 / `YYYY-MM-DD` 입력 시 그 날짜를 시작일로 바꿔 다시 확인
- 기간이 `MAX_PERIOD_DAYS`(기본 5일)를 넘으면 경고
- 시작일을 계산값보다 늦추면 누락 구간을 경고

주의: 로그의 `success`는 산출물을 만들었다는 뜻이지 SharePoint에 append했다는 뜻이 아니다. append를 하지 않고 스크립트만 돌렸다면, 다음 실행 때 기간 확인 프롬프트에서 시작일을 직접 입력해 되돌린다. 로그(`logs/`)는 실행한 PC에만 남는다.

## 검수 규칙

- 날짜: 데이터의 날짜가 위에서 확인한 추출 기간(시작일~종료일)과 정확히 일치해야 함 (누락/초과 모두 플래그)
- subsidiary/region/scope: 전 행이 Global/global 이어야 함
- 행 수: 하루당 2000~2400건 기준, 추출 기간의 일수를 곱해 비교 (3일치면 6000~7200). 벗어나면 이상치로 플래그. 기준값은 `.env`의 `ROW_COUNT_MIN` / `ROW_COUNT_MAX`로 조정

## Phase 변경

`sql/unpk_query.sql` 의 `AS phase_name` 줄을 직접 수정한 뒤 실행한다. 실행 시 현재 값을 보여주고 확인을 받는다.

## 자동화 범위

BigQuery 추출 → 검수 → 미리보기 산출물 생성까지만 자동화한다. SharePoint append, 파일명 변경, Slack 알림은 수동으로 진행한다.
