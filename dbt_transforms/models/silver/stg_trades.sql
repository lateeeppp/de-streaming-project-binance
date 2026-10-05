{{ config(
    materialized='table',
    table_type='iceberg',
    format='parquet',
    s3_data_dir='s3://de-streaming-project-binance-bucket/lakehouse/silver/'
) }}

WITH source_data AS (
    SELECT
        trade_id,
        symbol,
        price,
        quantity,
        trade_value_usd,
        buyer_is_maker,
        trade_time_ms,
        event_time_ms
    FROM {{ source('bronze_source', 'bronze_trades') }}
),

-- 1. Deduplikasi transaksi streaming (at-least-once delivery)
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY trade_id 
            ORDER BY event_time_ms DESC
        ) AS row_num
    FROM source_data
),

-- 2. Pembersihan tipe data & kalkulasi bisnis
cleaned AS (
    SELECT
        CAST(trade_id AS VARCHAR) AS trade_id,
        UPPER(TRIM(symbol)) AS symbol,
        CAST(price AS DOUBLE) AS price_usd,
        CAST(quantity AS DOUBLE) AS quantity,
        CAST(trade_value_usd AS DOUBLE) AS trade_value_usd,
        CASE 
            WHEN buyer_is_maker THEN 'SELL' 
            ELSE 'BUY' 
        END AS taker_side,
        from_unixtime(trade_time_ms / 1000.0) AS trade_timestamp,
        date(from_unixtime(trade_time_ms / 1000.0)) AS trade_date,
        from_unixtime(event_time_ms / 1000.0) AS event_timestamp,
        CASE 
            WHEN trade_value_usd >= 50000.0 THEN true 
            ELSE false 
        END AS is_whale_trade
    FROM deduplicated
    WHERE row_num = 1
      AND price > 0
      AND quantity > 0
      AND trade_value_usd > 0
)

SELECT * FROM cleaned