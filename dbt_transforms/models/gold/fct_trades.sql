{{ config(
    materialized='table',
    table_type='iceberg',
    format='parquet',
    partitioned_by=['trade_date'],
    s3_data_dir='s3://de-streaming-project-binance-bucket/lakehouse/gold/fct_trades/'
) }}

WITH silver_trades AS (
    SELECT *
    FROM {{ ref('stg_trades') }}
),

crypto_assets AS (
    SELECT crypto_asset_sk, symbol
    FROM {{ ref('dim_crypto_assets') }}
),

dates AS (
    SELECT date_sk, calendar_date
    FROM {{ ref('dim_date') }}
)

SELECT
    t.trade_id,
    
    -- Foreign Keys (Surrogate Keys *_sk)
    a.crypto_asset_sk,
    d.date_sk,
    
    -- Measures & Context
    t.trade_date,
    t.trade_timestamp,
    t.price_usd,
    t.quantity,
    t.trade_value_usd,
    t.taker_side,
    t.is_whale_trade,
    t.event_timestamp
FROM silver_trades t
INNER JOIN crypto_assets a ON t.symbol = a.symbol
INNER JOIN dates d ON t.trade_date = d.calendar_date