import base64
import json
import logging
import os
import urllib.error
import urllib.request
from decimal import Decimal
from typing import Any

import boto3
from botocore.exceptions import BotoCoreError, ClientError

# Setup logger standar AWS Lambda
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Konfigurasi Environment Variables dari Terraform
DYNAMODB_TABLE_NAME = os.environ.get(
    "DYNAMODB_TABLE_NAME", "de-streaming-project-binance-whale-alerts"
)
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
WHALE_THRESHOLD_USD = float(os.environ.get("WHALE_THRESHOLD_USD", "100000.0"))

# Inisialisasi resource DynamoDB
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(DYNAMODB_TABLE_NAME)


def send_telegram_alert(trade: dict[str, Any]) -> None:
    """Mengirim pesan notifikasi push instan ke Telegram via urllib (tanpa external library)."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        logger.warning("Telegram Bot Token atau Chat ID belum disetel!")
        return

    symbol = trade["symbol"]
    val_usd = float(trade["trade_value_usd"])
    price = float(trade["price"])
    qty = float(trade["quantity"])
    buyer_maker = "SELL" if trade["buyer_is_maker"] else "BUY"

    message_text = (
        f"🚨 <b>WHALE TRADE DETECTED!</b> 🐋\n\n"
        f"🪙 <b>Aset:</b> {symbol}\n"
        f"💰 <b>Total Nilai:</b> ${val_usd:,.2f}\n"
        f"🏷 <b>Harga:</b> ${price:,.2f}\n"
        f"📊 <b>Jumlah:</b> {qty:,.4f}\n"
        f"🎯 <b>Arah Order:</b> {buyer_maker}\n"
        f"🆔 <b>Trade ID:</b> {trade['trade_id']}\n"
    )

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = json.dumps(
        {
            "chat_id": TELEGRAM_CHAT_ID,
            "text": message_text,
            "parse_mode": "HTML",
        }
    ).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            if resp.status == 200:
                logger.info(f"Telegram alert terkirim untuk trade {trade['trade_id']}")
    except (urllib.error.URLError, TimeoutError, OSError) as err:
        logger.error(f"Gagal mengirim Telegram alert: {err}")


def save_to_dynamodb(trade: dict[str, Any]) -> None:
    """Menyimpan record paus ke DynamoDB (<5ms latency) tanpa risiko overwrite."""
    try:
        # Sort Key komposit: menjamin 100% unik dan tetap terurut berdasarkan waktu
        trade_time_id = f"{trade['trade_time_ms']}#{trade['trade_id']}"

        item = {
            "symbol": trade["symbol"],
            "trade_time_id": trade_time_id,  # Sort Key Baru (Unik 100%)
            "trade_time_ms": int(
                trade["trade_time_ms"]
            ),  # Tetap disimpan sebagai angka
            "trade_id": str(trade["trade_id"]),
            "price": Decimal(str(trade["price"])),
            "quantity": Decimal(str(trade["quantity"])),
            "trade_value_usd": Decimal(str(trade["trade_value_usd"])),
            "buyer_is_maker": bool(trade["buyer_is_maker"]),
            "event_time_ms": int(trade.get("event_time_ms", trade["trade_time_ms"])),
            "alert_type": "WHALE_TRADE",
        }
        table.put_item(Item=item)
        logger.info(
            f"Berhasil simpan ke DynamoDB: {trade['symbol']} | ${trade['trade_value_usd']}"
        )
    except (ClientError, BotoCoreError) as err:
        logger.error(f"Gagal simpan ke DynamoDB: {err}")


def lambda_handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    """
    Entrypoint AWS Lambda yang dipicu otomatis oleh Kinesis Event Source Mapping.
    Menerima batch record dari shard Kinesis.
    """
    records = event.get("Records", [])
    logger.info(f"Menerima {len(records)} record dari Kinesis Stream.")

    whale_count = 0

    for record in records:
        try:
            # Payload Kinesis dikodekan dalam base64
            encoded_data = record["kinesis"]["data"]
            decoded_bytes = base64.b64decode(encoded_data)
            trade = json.loads(decoded_bytes.decode("utf-8"))

            trade_value = float(trade.get("trade_value_usd", 0.0))

            # Filter Logika Bisnis: Apakah transaksi ini tergolong Paus?
            if trade_value >= WHALE_THRESHOLD_USD:
                whale_count += 1
                logger.info(
                    f"🚨 PAUS DITEMUKAN! {trade['symbol']} bernilai ${trade_value:,.2f}"
                )

                # Jalankan 2 aksi Hot Path secara paralel/sekuensial
                save_to_dynamodb(trade)
                send_telegram_alert(trade)

        except (json.JSONDecodeError, KeyError, ValueError, TypeError) as err:
            logger.error(f"Gagal memproses record Kinesis (payload tidak valid): {err}")
        except Exception as err:  # noqa: BLE001 - Mencegah poison pill menghentikan batch consumer loop
            logger.error(f"Gagal memproses record Kinesis (unexpected error): {err}")

    return {
        "statusCode": 200,
        "processed_records": len(records),
        "whales_detected": whale_count,
    }
