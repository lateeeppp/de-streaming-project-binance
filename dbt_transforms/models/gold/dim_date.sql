{{ config(
    materialized='table',
    table_type='iceberg',
    format='parquet',
    s3_data_dir='s3://de-streaming-project-binance-bucket/lakehouse/gold/dim_date/'
) }}

WITH distinct_dates AS (
    SELECT DISTINCT trade_date
    FROM {{ ref('stg_trades') }}
)

SELECT
    -- Surrogate Key (*_sk)
    CAST(date_format(trade_date, '%Y%m%d') AS INTEGER) AS date_sk,
    
    -- Natural Date & Attributes
    trade_date AS calendar_date,
    EXTRACT(YEAR FROM trade_date) AS year,
    EXTRACT(MONTH FROM trade_date) AS month,
    EXTRACT(DAY FROM trade_date) AS day,
    date_format(trade_date, '%W') AS day_name,
    CASE 
        WHEN day_of_week(trade_date) IN (6, 7) THEN true 
        ELSE false 
    END AS is_weekend
FROM distinct_dates