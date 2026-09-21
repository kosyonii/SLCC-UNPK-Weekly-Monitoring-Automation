-- ============================================================
-- UNPK Weekly Monitoring 추출 쿼리
-- 주의: Phase 변환이 아닌 이상 이 쿼리를 절대 수정하지 않는다.
-- Phase 변경이 필요할 때만 아래 params CTE의 phase_name 값을 직접 수정하고,
-- 실행 시 phase_check.py 가 보여주는 값이 맞는지 다시 확인한다.
-- ============================================================

WITH params AS (
  SELECT
    -- 기본 조회 기간
    --   월요일 실행: 직전 금요일~일요일
    --   화~일요일 실행: 전일 하루
    -- 수동 기간 조회가 필요하면 아래 start_date/end_date 두 식을
    -- DATE 'YYYY-MM-DD' 형태의 고정값으로 변경
    CASE
      WHEN EXTRACT(DAYOFWEEK FROM CURRENT_DATE('Asia/Seoul')) = 2
        THEN DATE_SUB(CURRENT_DATE('Asia/Seoul'), INTERVAL 3 DAY)
      ELSE DATE_SUB(CURRENT_DATE('Asia/Seoul'), INTERVAL 1 DAY)
    END AS start_date,
    DATE_SUB(CURRENT_DATE('Asia/Seoul'), INTERVAL 1 DAY) AS end_date,
    DATE '2026-07-22' AS unpack_date,
    CURRENT_DATE('Asia/Singapore') AS update_date,
    'QHB8' AS series_name,
    'Pre-Teaser' AS phase_name,
    'Global' AS subsidiary,
    'Global' AS region,
    'global' AS scope,
    'Kearney' AS data_n
),
-- ============================================================
-- 0. 전일(D-1) 적재 여부 확인
--    최종 조회 기간은 params에서 월요일 금~일 / 그 외 전일로 설정
-- ============================================================
target AS (
  SELECT
    DATE_SUB(CURRENT_DATE('Asia/Seoul'), INTERVAL 1 DAY) AS target_date
),

data_check AS (
  SELECT
    'quant_dashboard' AS table_name,
    COUNT(*) AS row_count
  FROM `slcc-buzz-agent-dev.agent_data.quant_dashboard` AS q
  CROSS JOIN target AS t
  WHERE q.date = t.target_date
    AND q.scope = 'global'
    AND q.sentiment_yn = 'n'

  UNION ALL

  SELECT
    'agent_data' AS table_name,
    COUNT(*) AS row_count
  FROM `slcc-buzz-agent-dev.agent_data.agent_data` AS ad
  CROSS JOIN target AS t
  WHERE DATE(ad.Created_Time, 'Asia/Seoul') = t.target_date

  UNION ALL

  SELECT
    'comention_quant_data' AS table_name,
    COUNT(*) AS row_count
  FROM `slcc-buzz-agent-dev.agent_data.comention_quant_data` AS cq
  CROSS JOIN target AS t
  WHERE cq.date = t.target_date
),

check_result AS (
  SELECT
    ANY_VALUE(t.target_date) AS target_date,
    COUNTIF(d.row_count = 0) = 0 AS is_ready,
    STRING_AGG(
      IF(d.row_count = 0, d.table_name, NULL),
      ', ' ORDER BY d.table_name
    ) AS missing_tables
  FROM data_check AS d
  CROSS JOIN target AS t
),


-- ============================================================
-- 1. 기존 쿼리: quant_dashboard의 sentiment_yn = 'n' 데이터
--    params의 start_date/end_date를 동일하게 적용
-- ============================================================
dashboard_result AS (
  SELECT
    q.date,
    q.series,
    q.phase,
    q.mentions,
    q.product_yn,
    q.sentiment_yn,
    q.channel_yn AS source_yn,
    q.feature_yn,
    q.product,
    q.channel_lv1 AS source_lv1,
    q.channel_lv2 AS source_lv2,
    q.channel_lv3 AS source_lv3,
    q.htr,
    q.feature_lv1,
    q.feature_lv2,
    q.sentiment,
    q.subsidiary,
    q.region,
    q.scope,
    q.unpk_week,
    q.unpk_day,
    q.data,
    q.update_date,

    0 AS _sentiment_order,
    CASE
      WHEN q.feature_yn = 'n' THEN 1
      WHEN q.feature_lv2 IS NULL OR q.feature_lv2 = 'Total' THEN 2
      ELSE 3
    END AS _summary_order,
    CAST(NULL AS STRING) AS _type_order,
    CASE q.product
      WHEN 'Foldable' THEN 1
      WHEN 'Fold8+Fold8Ultra' THEN 2
      WHEN 'Fold8Ultra' THEN 3
      WHEN 'Fold8' THEN 4
      WHEN 'Flip8' THEN 5
      WHEN 'Watch9+Ultra2' THEN 6
      WHEN 'WatchUltra2' THEN 7
      ELSE 9
    END AS _product_order
  FROM `slcc-buzz-agent-dev.agent_data.quant_dashboard` AS q
  CROSS JOIN params AS p
  WHERE q.date BETWEEN p.start_date AND p.end_date
    AND q.scope = p.scope
    AND q.sentiment_yn = 'n'
    -- 실제 소셜 채널(Facebook/X 등) breakdown 행은 구스키마에 대응 개념이 없으므로 제외
    AND NOT (q.source_yn = 'y' AND q.channel_yn = 'n')
),

base AS (
  SELECT
    DATE(SAFE_CAST(t.Created_Time AS TIMESTAMP), 'Asia/Seoul') AS dt,
    COALESCE(SAFE_CAST(t.mentions AS NUMERIC), 0) AS mention_cnt,
    t.*
  FROM `slcc-buzz-agent-dev.agent_data.agent_data` AS t
  CROSS JOIN params AS p
  WHERE SAFE_CAST(t.Created_Time AS TIMESTAMP) >= TIMESTAMP(p.start_date, 'Asia/Seoul')
    AND SAFE_CAST(t.Created_Time AS TIMESTAMP) < TIMESTAMP(DATE_ADD(p.end_date, INTERVAL 1 DAY), 'Asia/Seoul')
    AND t.overall_sentiment IS NOT NULL
    AND t.region = 'Global'
    AND t.subsi = 'Global'
    AND SAFE_CAST(t.HTR AS INT64) = 0
    AND COALESCE(CAST(t.source AS STRING), '') NOT IN ('News', 'Radio', 'Print', 'TV')
),

product_base AS (
  SELECT
    b.*,
    p.type,
    p.product
  FROM base AS b
  CROSS JOIN UNNEST([
    -- append yaml token mapping 기준:
    --   Q     = Product_Wide8__SUM_
    --   H     = Product_Fold8__SUM_
    --   B     = Product_Flip8__SUM_
    --   Watch = Product_GW9_Family__SUM_
    --   Watch Ultra 2 = Product_GW_Ultra2__SUM_
    STRUCT('Mobile' AS type, 'Fold8Ultra' AS product, IF(COALESCE(SAFE_CAST(b.`Product_Wide8__SUM_` AS INT64), 0) = 1, 1, 0) AS product_flag),
    STRUCT('Mobile' AS type, 'Fold8' AS product, IF(COALESCE(SAFE_CAST(b.`Product_Fold8__SUM_` AS INT64), 0) = 1, 1, 0) AS product_flag),
    STRUCT('Mobile' AS type, 'Flip8' AS product, IF(COALESCE(SAFE_CAST(b.`Product_Flip8__SUM_` AS INT64), 0) = 1, 1, 0) AS product_flag),
    STRUCT('Wearable' AS type, 'Watch9+Ultra2' AS product, IF(COALESCE(SAFE_CAST(b.`Product_GW9_Family__SUM_` AS INT64), 0) = 1, 1, 0) AS product_flag),
    STRUCT('Wearable' AS type, 'WatchUltra2' AS product, IF(COALESCE(SAFE_CAST(b.`Product_GW_Ultra2__SUM_` AS INT64), 0) = 1, 1, 0) AS product_flag),

    -- QH8 / QHB8는 append 쿼리와 동일하게 OR 기준으로 1회 집계
    STRUCT('Mobile' AS type, 'Fold8+Fold8Ultra' AS product, IF(
      COALESCE(SAFE_CAST(b.`Product_Wide8__SUM_` AS INT64), 0) = 1
      OR COALESCE(SAFE_CAST(b.`Product_Fold8__SUM_` AS INT64), 0) = 1,
      1, 0
    ) AS product_flag),
    STRUCT('Mobile' AS type, 'Foldable' AS product, IF(
      COALESCE(SAFE_CAST(b.`Product_Wide8__SUM_` AS INT64), 0) = 1
      OR COALESCE(SAFE_CAST(b.`Product_Fold8__SUM_` AS INT64), 0) = 1
      OR COALESCE(SAFE_CAST(b.`Product_Flip8__SUM_` AS INT64), 0) = 1,
      1, 0
    ) AS product_flag)
  ]) AS p
  WHERE p.product_flag = 1
),

long AS (
  -- 0) 전체 sentiment: overall_sentiment 기준
  SELECT
    dt,
    type,
    product,
    'overall' AS summary_level,
    'Overall' AS feature_1lv,
    CAST(NULL AS STRING) AS feature_2lv,
    CAST(overall_sentiment AS STRING) AS sentiment_raw,
    mention_cnt
  FROM product_base

  UNION ALL

  -- 1) feature sentiment:
  --    Mobile product에는 Mobile feature만 붙임
  --    Wearable product에는 Wearable feature만 붙임
  --    TWS feature는 이 목록에서 아예 제외함
  --    2lv sentiment도 자기 부모 1lv sentiment 컬럼을 사용함
  SELECT
    b.dt,
    b.type,
    b.product,
    f.summary_level,
    f.feature_1lv,
    f.feature_2lv,
    f.sentiment_raw,
    b.mention_cnt
  FROM product_base AS b
  CROSS JOIN UNNEST([
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'AP/Memory' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AP_Memory` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AP_Memory` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AP/Memory' AS feature_1lv, 'AP Performance' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AP_Memory_2lv_AP_Performance` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AP_Memory` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AP/Memory' AS feature_1lv, 'RAM' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AP_Memory_2lv_RAM` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AP_Memory` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AP/Memory' AS feature_1lv, 'Cooling System' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AP_Memory_2lv_Cooling_System` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AP_Memory` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'AI' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Writing Assist' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Writing_Assist` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'AI select' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_AI_select` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Browsing Assist' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Browsing_Assist` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Interpreter' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Interpreter` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Call Assist' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Call_Assist` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Now Brief' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Now_Brief` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'AI Agent' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_AI_Agent` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Photo Assist' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Photo_Assist` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Transcript Assist' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Transcript_Assist` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Search with finder' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Search_with_finder` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Health Assist' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Health_Assist` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Note Assist' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Note_Assist` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Now Nudge' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Now_Nudge` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Creative Studio' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Creative_Studio` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Circle to Search' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Circle_to_Search` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Personalized AI' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_Personalized_AI` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'My FanCam' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_AI_2lv_My_FanCam` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_AI` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'UI/UX' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_UI_UX` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'UI/UX' AS feature_1lv, 'OS' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_UI_UX_2lv_OS` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'UI/UX' AS feature_1lv, 'UI' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_UI_UX_2lv_UI` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'UI/UX' AS feature_1lv, 'Keyboard' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_UI_UX_2lv_Keyboard` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'UI/UX' AS feature_1lv, 'Customize' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_UI_UX_2lv_Customize` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'UI/UX' AS feature_1lv, 'UX' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_UI_UX_2lv_UX` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'S-Pen' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_S_Pen` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_S_Pen` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'S-Pen' AS feature_1lv, 'Additionals' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_S_Pen_2lv_Additionals` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_S_Pen` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'S-Pen' AS feature_1lv, 'Handwriting' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_S_Pen_2lv_Handwriting` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_S_Pen` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'S-Pen' AS feature_1lv, 'Drawing' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_S_Pen_2lv_Drawing` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_S_Pen` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Security' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Security` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Security` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Security' AS feature_1lv, 'Privacy' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Security_2lv_Privacy` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Security` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Security' AS feature_1lv, 'AI' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Security_2lv_AI` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Security` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Security' AS feature_1lv, 'Knox' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Security_2lv_Knox` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Security` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Security' AS feature_1lv, 'Protection' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Security_2lv_Protection` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Security` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Price' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Price` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Price` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Price' AS feature_1lv, 'Expensive' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Price_2lv_Expensive` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Price` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Price' AS feature_1lv, 'Affordable' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Price_2lv_Affordable` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Price` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Price' AS feature_1lv, 'Trade-in' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Price_2lv_Trade_in` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Price` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Game' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Game` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Game` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Game' AS feature_1lv, 'Performance' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Game_2lv_Performance` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Game` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Game' AS feature_1lv, 'Game Launcher' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Game_2lv_Game_Launcher` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Game` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Game' AS feature_1lv, 'Heat Control' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Game_2lv_Heat_Control` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Game` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Game' AS feature_1lv, 'Game Pass' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Game_2lv_Game_Pass` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Game` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Game' AS feature_1lv, 'Game Title' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Game_2lv_Game_Title` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Game` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Durability' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Durability` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Durability` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Durability' AS feature_1lv, 'Resistance' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Durability_2lv_Resistance` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Durability` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Durability' AS feature_1lv, 'SC+/Repair' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Durability_2lv_SC__Repair` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Durability` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Durability' AS feature_1lv, 'Protection' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Durability_2lv_Protection` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Durability` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Durability' AS feature_1lv, 'Crease' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Durability_2lv_Crease` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Durability` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Display' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Display' AS feature_1lv, 'Brightness' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display_2lv_Brightness` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Display' AS feature_1lv, 'Refresh Rate' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display_2lv_Refresh_Rate` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Display' AS feature_1lv, 'Bezel' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display_2lv_Bezel` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Display' AS feature_1lv, 'Screen Size' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display_2lv_Screen_Size` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Display' AS feature_1lv, 'Personalize' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display_2lv_Personalize` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Display' AS feature_1lv, 'Resolution' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display_2lv_Resolution` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Display' AS feature_1lv, 'Flexwindow' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display_2lv_Flexwindow` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Display' AS feature_1lv, 'Privacy Display' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display_2lv_Privacy_Display` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Display' AS feature_1lv, 'Flex Titanium' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Display_2lv_Flex_Titanium` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Display` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Design' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Design` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Design` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Case' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Durability_2lv_Case` AS INT64), 0) * COALESCE(SAFE_CAST(b.`Feature_Design` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Design` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Material' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Design_2lv_Material` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Design` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Color' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Design_2lv_Color` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Design` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Form Factor' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Design_2lv_Form_Factor` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Design` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Weight' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Design_2lv_Weight` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Design` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Size' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Design_2lv_Size` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Design` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Connected Exp.' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Connected_Exp` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Connected Exp.' AS feature_1lv, 'Network' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Connected_Exp_2lv_Network` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Connected Exp.' AS feature_1lv, 'Sharing' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Connected_Exp_2lv_Sharing` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Connected Exp.' AS feature_1lv, 'Service' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Connected_Exp_2lv_Service` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Connected Exp.' AS feature_1lv, 'Ecosystem' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Connected_Exp_2lv_Ecosystem` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Camera' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Document Scan' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Document_Scan` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Portrait' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Portrait` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Directors View' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Director_s_View` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Log Video' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Log_Video` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Super Steady' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Super_Steady` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Macro' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Macro` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Pro Mode' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Pro_Mode` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Expert Raw' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Expert_Raw` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'ProVisual_Engine' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_ProVisual_Engine` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Slow Motion (Hyperlapse)' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Slow_Motion__Hyperlapse_` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'FlexCam' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_FlexCam` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Generative Edit' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Generative_Edit` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Resolution' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Resolution` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Nightography' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Nightography` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Zoom' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Zoom` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'My FanCam' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_My_FanCam` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Camera' AS feature_1lv, 'Mirror View' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Camera_2lv_Mirror_View` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Camera` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Battery' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Battery` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Battery` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Battery' AS feature_1lv, 'Charger' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Battery_2lv_Charger` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Battery` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Battery' AS feature_1lv, 'Charging' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Battery_2lv_Charging` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Battery` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Battery' AS feature_1lv, 'Life Time' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Battery_2lv_Life_Time` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Battery` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_1lv' AS summary_level, 'Audio' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Audio` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Audio` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Audio' AS feature_1lv, 'Noise Control' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Audio_2lv_Noise_Control` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Audio` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Audio' AS feature_1lv, 'Mic' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Audio_2lv_Mic` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Audio` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Audio' AS feature_1lv, 'Call' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Audio_2lv_Call` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Audio` AS STRING) AS sentiment_raw),
    STRUCT('Mobile' AS feature_type, 'feature_2lv' AS summary_level, 'Audio' AS feature_1lv, 'Speaker' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Audio_2lv_Speaker` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_Audio` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_1lv' AS summary_level, 'Health' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Health` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Health` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Health' AS feature_1lv, 'Safety' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Health_2lv_Safety` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Health` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Health' AS feature_1lv, 'Fitness' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Health_2lv_Fitness` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Health` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Health' AS feature_1lv, 'Monitoring' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Health_2lv_Monitoring` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Health` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Health' AS feature_1lv, 'Sleep' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Health_2lv_Sleep` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Health` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_1lv' AS summary_level, 'Design' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Design` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Design` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Color' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Design_2lv_Color` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Design` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Form Factor' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Design_2lv_Form_Factor` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Design` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Material' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Design_2lv_Material` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Design` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Size' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Design_2lv_Size` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Design` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Strap' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Design_2lv_Strap` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Design` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Design' AS feature_1lv, 'Weight' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Design_2lv_Weight` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Design` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_1lv' AS summary_level, 'AI' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_AI` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_AI` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Bixby' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_AI_2lv_Bixby` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_AI` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Call Assist' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_AI_2lv_Call_Assist` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_AI` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'AI' AS feature_1lv, 'Health Assist' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_AI_2lv_Health_Assist` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_AI` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_1lv' AS summary_level, 'Connected Exp.' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Connected_Exp` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Connected Exp.' AS feature_1lv, 'App' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Connected_Exp_2lv_App` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Connected Exp.' AS feature_1lv, 'Ecosystem' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Connected_Exp_2lv_Ecosystem` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Connected Exp.' AS feature_1lv, 'Network' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Connected_Exp_2lv_Network` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Connected Exp.' AS feature_1lv, 'Service' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Connected_Exp_2lv_Service` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Connected Exp.' AS feature_1lv, 'Sharing' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Connected_Exp_2lv_Sharing` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Connected_Exp` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_1lv' AS summary_level, 'UI/UX' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_UI_UX` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'UI/UX' AS feature_1lv, 'Gesture' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_UI_UX_2lv_Gesture` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'UI/UX' AS feature_1lv, 'OS' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_UI_UX_2lv_OS` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'UI/UX' AS feature_1lv, 'UI' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_UI_UX_2lv_UI` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'UI/UX' AS feature_1lv, 'UX' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_UI_UX_2lv_UX` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_UI_UX` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_1lv' AS summary_level, 'Price' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Price` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Price` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Price' AS feature_1lv, 'Affordable' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Price_2lv_Affordable` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Price` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Price' AS feature_1lv, 'Expensive' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Price_2lv_Expensive` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Price` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Price' AS feature_1lv, 'Trade-in' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Price_2lv_Trade_in` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Price` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_1lv' AS summary_level, 'H/W' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_H_W` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_H_W` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'H/W' AS feature_1lv, 'Display' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_H_W_2lv_Display` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_H_W` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'H/W' AS feature_1lv, 'Processor' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_H_W_2lv_Processor` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_H_W` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'H/W' AS feature_1lv, 'Sensor' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_H_W_2lv_Sensor` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_H_W` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_1lv' AS summary_level, 'Durability' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Durability` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Durability` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Durability' AS feature_1lv, 'Protection' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Durability_2lv_Protection` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Durability` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Durability' AS feature_1lv, 'Resistance' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Durability_2lv_Resistance` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Durability` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Durability' AS feature_1lv, 'SC+/Repair' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Durability_2lv_SC__Repair` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Durability` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_1lv' AS summary_level, 'Battery' AS feature_1lv, CAST(NULL AS STRING) AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Battery` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Battery` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Battery' AS feature_1lv, 'Charger' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Battery_2lv_Charger` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Battery` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Battery' AS feature_1lv, 'Charging' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Battery_2lv_Charging` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Battery` AS STRING) AS sentiment_raw),
    STRUCT('Wearable' AS feature_type, 'feature_2lv' AS summary_level, 'Battery' AS feature_1lv, 'Life Time' AS feature_2lv, COALESCE(SAFE_CAST(b.`Feature_Wearable_Battery_2lv_Life_Time` AS INT64), 0) AS flag, CAST(b.`feature_sentiments_wearable_Battery` AS STRING) AS sentiment_raw)
  ]) AS f
  WHERE f.flag > 0
    AND f.feature_type = b.type
),

normalized AS (
  SELECT
    dt,
    type,
    product,
    summary_level,
    feature_1lv,
    feature_2lv,
    CASE
      WHEN LOWER(TRIM(sentiment_raw)) IN ('1', 'positive', 'pos', '긍정') THEN 'positive'
      WHEN LOWER(TRIM(sentiment_raw)) IN ('0', 'neutral', 'neu', '중립') THEN 'neutral'
      WHEN LOWER(TRIM(sentiment_raw)) IN ('-1', 'negative', 'neg', '부정') THEN 'negative'
      ELSE 'unknown'
    END AS sentiment,
    mention_cnt
  FROM long
),

summary AS (
  -- 여기까지가 기존 original 형태와 같은 집계 단위
  SELECT
    dt,
    type,
    product,
    summary_level,
    feature_1lv,
    feature_2lv,
    SUM(CASE WHEN sentiment = 'positive' THEN mention_cnt ELSE 0 END) AS positive_mentions,
    SUM(CASE WHEN sentiment = 'neutral'  THEN mention_cnt ELSE 0 END) AS neutral_mentions,
    SUM(CASE WHEN sentiment = 'negative' THEN mention_cnt ELSE 0 END) AS negative_mentions,
    SUM(CASE WHEN sentiment = 'unknown'  THEN mention_cnt ELSE 0 END) AS unknown_mentions,
    SUM(mention_cnt) AS total_mentions
  FROM normalized
  GROUP BY
    dt,
    type,
    product,
    summary_level,
    feature_1lv,
    feature_2lv
),

final AS (
  -- original의 positive/neutral/negative/total 컬럼을 new 스키마처럼 행으로 펼침
  SELECT
    s.dt AS date,
    p.series_name AS series,
    p.phase_name AS phase,
    u.mentions,

    'y' AS product_yn,
    u.sentiment_yn,
    'n' AS source_yn,
    CASE
      WHEN u.sentiment IS NOT NULL AND s.summary_level = 'overall' THEN 'n'
      ELSE 'y'
    END AS feature_yn,

    s.product,
    CAST(NULL AS STRING) AS source_lv1,
    CAST(NULL AS STRING) AS source_lv2,
    CAST(NULL AS STRING) AS source_lv3,
    CAST(NULL AS STRING) AS htr,

    CASE
      WHEN u.sentiment IS NOT NULL AND s.summary_level = 'overall' THEN CAST(NULL AS STRING)
      ELSE s.feature_1lv
    END AS feature_lv1,
    CASE
      -- feature_lv1이 NULL인 row는 feature_lv2도 NULL로 맞춤
      WHEN u.sentiment IS NOT NULL AND s.summary_level = 'overall' THEN CAST(NULL AS STRING)
      WHEN s.feature_1lv IS NULL THEN CAST(NULL AS STRING)
      ELSE COALESCE(s.feature_2lv, 'Total')
    END AS feature_lv2,
    u.sentiment,

    p.subsidiary,
    p.region,
    p.scope,

    CASE
      WHEN DATE_DIFF(s.dt, p.unpack_date, DAY) = 0 THEN '0W'
      WHEN DATE_DIFF(s.dt, p.unpack_date, DAY) > 0 THEN CONCAT('+', CAST(CAST(CEIL(ABS(DATE_DIFF(s.dt, p.unpack_date, DAY)) / 7.0) AS INT64) AS STRING), 'W')
      ELSE CONCAT('-', CAST(CAST(CEIL(ABS(DATE_DIFF(s.dt, p.unpack_date, DAY)) / 7.0) AS INT64) AS STRING), 'W')
    END AS unpk_week,
    CONCAT(
      CASE WHEN DATE_DIFF(s.dt, p.unpack_date, DAY) > 0 THEN '+' ELSE '' END,
      CAST(DATE_DIFF(s.dt, p.unpack_date, DAY) AS STRING),
      'D'
    ) AS unpk_day,

    p.data_n AS data,
    p.update_date,

    u.sentiment_order AS _sentiment_order,
    CASE s.summary_level
      WHEN 'overall' THEN 1
      WHEN 'feature_1lv' THEN 2
      WHEN 'feature_2lv' THEN 3
      ELSE 9
    END AS _summary_order,
    s.type AS _type_order,
    CASE s.product
      WHEN 'Foldable' THEN 1
      WHEN 'Fold8+Fold8Ultra' THEN 2
      WHEN 'Fold8Ultra' THEN 3
      WHEN 'Fold8' THEN 4
      WHEN 'Flip8' THEN 5
      WHEN 'Watch9+Ultra2' THEN 6
      WHEN 'WatchUltra2' THEN 7
      ELSE 9
    END AS _product_order
  FROM summary AS s
  CROSS JOIN params AS p
  CROSS JOIN UNNEST([
    -- sentiment_yn = 'y' 인 Positive / Neutral / Negative 행만 생성
    STRUCT('Positive' AS sentiment, 'y' AS sentiment_yn, s.positive_mentions AS mentions, 1 AS sentiment_order),
    STRUCT('Neutral'  AS sentiment, 'y' AS sentiment_yn, s.neutral_mentions  AS mentions, 2 AS sentiment_order),
    STRUCT('Negative' AS sentiment, 'y' AS sentiment_yn, s.negative_mentions AS mentions, 3 AS sentiment_order)
  ]) AS u
),

-- ============================================================
-- 2. 기존 quant_dashboard 결과 + 현재 생성 쿼리 결과
-- ============================================================
combined AS (
  SELECT
    d.*,
    0 AS _dataset_order
  FROM dashboard_result AS d

  UNION ALL

  SELECT
    f.*,
    1 AS _dataset_order
  FROM final AS f
)

SELECT
  c.date,
  c.series,
  c.phase,
  c.mentions,
  c.product_yn,
  c.sentiment_yn,
  c.source_yn,
  c.feature_yn,
  c.product,
  c.source_lv1,
  c.source_lv2,
  c.source_lv3,
  c.htr,
  c.feature_lv1,
  c.feature_lv2,
  c.sentiment,
  c.subsidiary,
  c.region,
  c.scope
--  c.unpk_week,
--  c.unpk_day,
--  c.data,
--  c.update_date
FROM combined AS c
CROSS JOIN check_result AS r
WHERE IF(
  r.is_ready,
  TRUE,
  ERROR(
    CONCAT(
      'D-1 데이터 적재 미완료 [',
      CAST(r.target_date AS STRING),
      ']: ',
      COALESCE(r.missing_tables, '확인 불가')
    )
  )
)
ORDER BY
  c.date,
  c._dataset_order,
  c._sentiment_order,
  c._type_order,
  c._product_order,
  c.product,
  c._summary_order,
  c.feature_lv1,
  c.feature_lv2;
