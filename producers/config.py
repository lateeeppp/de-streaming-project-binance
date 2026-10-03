"""Konfigurasi parameter streaming producer."""

# Konfigurasi AWS
AWS_REGION = "ap-southeast-3"
AWS_PROFILE = "de-streaming-project-binance"
KINESIS_STREAM_NAME = "crypto-trades-stream"

# Konfigurasi Binance WebSocket
# Kita dengarkan 3 simbol sekaligus: BTC, ETH, dan SOL
CRYPTO_SYMBOLS = ["btcusdt", "ethusdt", "solusdt"]
STREAMS_PARAM = "/".join([f"{s}@trade" for s in CRYPTO_SYMBOLS])

# Endpoint resmi Binance Combined Streams (Port 443)
BINANCE_WS_URL = f"wss://stream.binance.com:443/stream?streams={STREAMS_PARAM}"