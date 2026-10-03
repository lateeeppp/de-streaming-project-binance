import json
import logging
from typing import Any, Dict
import boto3
import websocket
from producers.config import (
    AWS_PROFILE,
    AWS_REGION,
    BINANCE_WS_URL,
    KINESIS_STREAM_NAME,
)

# Konfigurasi Logging standar industri
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# Inisialisasi Kinesis Client menggunakan profil AWS resmi Anda
session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
kinesis_client = session.client("kinesis")


def transform_raw_trade(raw_payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Mengubah payload mentah Binance menjadi format Data Contract standar.
    
    Catatan Arsitektur:
    Pada Binance Combined Stream, payload dibungkus dalam key 'data'.
    Fungsi ini mengekstrak data transaksi dan menghitung trade_value_usd.
    """
    data = raw_payload.get("data", raw_payload)
    price = float(data["p"])
    quantity = float(data["q"])
    trade_value_usd = round(price * quantity, 2)

    return {
        "trade_id": str(data["t"]),
        "symbol": data["s"],
        "price": price,
        "quantity": quantity,
        "trade_value_usd": trade_value_usd,
        "buyer_is_maker": data["m"],
        "trade_time_ms": data["T"],
        "event_time_ms": data["E"],
    }

def send_to_kinesis(trade_record: Dict[str, Any]) -> None:
    """Mengirim record transaksi yang sudah terstandarisasi ke Amazon Kinesis."""
    try:
        payload_bytes = json.dumps(trade_record).encode("utf-8")

        # Partition Key = symbol (BTCUSDT, ETHUSDT, SOLUSDT)
        # Menjamin transaksi dari aset yang sama selalu masuk ke shard yang konsisten
        response = kinesis_client.put_record(
            StreamName=KINESIS_STREAM_NAME,
            Data=payload_bytes,
            PartitionKey=trade_record["symbol"],
        )

        symbol = trade_record["symbol"]
        val_usd = trade_record["trade_value_usd"]
        shard_id = response.get("ShardId", "unknown")

        logger.info(
            f"Kinesis Ingested | {symbol:<8} | Val: ${val_usd:>10,.2f} | Shard: {shard_id}"
        )

    except Exception as err:
        logger.error(f"Gagal mengirim ke Kinesis: {err}")


def on_message(_ws: websocket.WebSocketApp, message: str) -> None:
    """Callback pemroses setiap ada transaksi live baru dari WebSocket."""
    try:
        raw_data = json.loads(message)
        standardized_trade = transform_raw_trade(raw_data)
        send_to_kinesis(standardized_trade)
    except Exception as err:
        logger.error(f"Error memproses pesan transaksi: {err}")


def on_error(_ws: websocket.WebSocketApp, error: Exception) -> None:
    logger.error(f"WebSocket error: {error}")


def on_close(_ws: websocket.WebSocketApp, close_code: int, close_msg: str) -> None:
    logger.info(f"WebSocket ditutup (Kode: {close_code}, Pesan: '{close_msg}')")


def on_open(_ws: websocket.WebSocketApp) -> None:
    logger.info(f"Terhubung ke Binance Combined Streams! Mengalirkan ke Kinesis: '{KINESIS_STREAM_NAME}'...")


if __name__ == "__main__":
    logger.info("Memulai Binance to Kinesis Streaming Producer...")
    ws_app = websocket.WebSocketApp(
        BINANCE_WS_URL,
        on_open=on_open,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close,
    )
    ws_app.run_forever()