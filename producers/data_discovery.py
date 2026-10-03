import json

import websocket

# Counter batas penangkapan sampel
trade_count = 0
MAX_TRADES = 3

# Endpoint WebSocket Publik Binance untuk trade Bitcoin (BTCUSDT)
BINANCE_WS_URL = "wss://stream.binance.com/ws/btcusdt@trade"


def on_message(ws: websocket.WebSocketApp, message: str) -> None:
    """Callback yang dipanggil setiap kali ada pesan transaksi baru."""
    global trade_count
    trade_count += 1

    # Deserialisasi string JSON mentah dari WebSocket
    data = json.loads(message)

    print(
        f"\n==================== [SAMPEL DATA RAW #{trade_count}] ===================="
    )
    print(json.dumps(data, indent=2))

    # Jika target sampel terpenuhi, tutup koneksi secara elegan
    if trade_count >= MAX_TRADES:
        print("\n[INFO] Target 3 sampel data tercapai. Menutup koneksi...")
        ws.close()


def on_error(_ws: websocket.WebSocketApp, error: Exception) -> None:
    """Callback untuk menangani error koneksi."""
    print(f"[ERROR] Terjadi kesalahan: {error}")


def on_close(
    _ws: websocket.WebSocketApp, close_status_code: int, close_msg: str
) -> None:
    """Callback saat koneksi WebSocket ditutup."""
    print(
        f"[INFO] Koneksi WebSocket ditutup (Kode: {close_status_code}, Pesan: '{close_msg}')."
    )


def on_open(_ws: websocket.WebSocketApp) -> None:
    """Callback saat koneksi WebSocket pertama kali berhasil tersambung."""
    print(f"[INFO] Berhasil terhubung ke: {BINANCE_WS_URL}")
    print("[INFO] Menunggu aliran transaksi live dari pasar...")


if __name__ == "__main__":
    # Aktifkan pelacak socket untuk melihat detail IP dan handshake
    websocket.enableTrace(True)

    ws_client = websocket.WebSocketApp(
        BINANCE_WS_URL,
        on_open=on_open,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close,
    )
    ws_client.run_forever()
