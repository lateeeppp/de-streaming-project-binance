{{ config(
    materialized='table',
    table_type='iceberg',
    format='parquet',
    s3_data_dir='s3://de-streaming-project-binance-bucket/lakehouse/gold/dim_crypto_assets/'
) }}

WITH distinct_symbols AS (
    SELECT DISTINCT symbol
    FROM {{ ref('stg_trades') }}
)

SELECT
    -- Surrogate Key (*_sk)
    {{ dbt_utils.generate_surrogate_key(['symbol']) }} AS crypto_asset_sk,
    
    -- Natural Key
    symbol,
    
    -- Attributes
    CASE 
        WHEN symbol = 'BTCUSDT' THEN 'BTC'
        WHEN symbol = 'ETHUSDT' THEN 'ETH'
        WHEN symbol = 'SOLUSDT' THEN 'SOL'
        ELSE symbol
    END AS base_asset,
    'USDT' AS quote_asset,
    CASE 
        WHEN symbol = 'BTCUSDT' THEN 'Bitcoin'
        WHEN symbol = 'ETHUSDT' THEN 'Ethereum'
        WHEN symbol = 'SOLUSDT' THEN 'Solana'
        ELSE 'Unknown'
    END AS asset_name,
    'Layer-1 Blockchain' AS asset_category
FROM distinct_symbols