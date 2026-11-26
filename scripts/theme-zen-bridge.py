#!/usr/bin/env python3
"""Localhost SSE bridge serving Zen Browser live theme palettes on 127.0.0.1:47616."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = "127.0.0.1"
PORT = int(os.environ.get("THEME_ZEN_BRIDGE_PORT", "47616"))
HOME = Path(os.environ.get("HOME", Path.home()))
PALETTE_PATH = Path(
    os.environ.get(
        "THEME_ZEN_PALETTE_JSON",
        str(HOME / ".cache/theme-manager/zen-palette.json"),
    )
)


class PaletteState:
    def __init__(self) -> None:
        self._cond = threading.Condition()
        self._version = 0
        self._payload = b""
        self._last_sig: tuple[int, int] | None = None

    def load_file(self, force: bool = False) -> bool:
        try:
            st = PALETTE_PATH.stat()
            sig = (st.st_mtime_ns, st.st_size)
            if not force and sig == self._last_sig and self._payload:
                return False
            raw = PALETTE_PATH.read_text(encoding="utf-8")
            parsed = json.loads(raw)
            if not isinstance(parsed, dict) or not parsed.get("primary") or not parsed.get("surface"):
                return False
            compact = json.dumps(parsed, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        except (OSError, json.JSONDecodeError):
            return False

        with self._cond:
            self._last_sig = sig
            if compact == self._payload:
                return False
            self._payload = compact
            self._version += 1
            self._cond.notify_all()
            return True

    def snapshot(self) -> tuple[int, bytes]:
        with self._cond:
            return self._version, self._payload

    def wait_next(self, seen_version: int, timeout: float = 30.0) -> tuple[int, bytes, bool]:
        with self._cond:
            if self._version == seen_version:
                self._cond.wait(timeout=timeout)
            return self._version, self._payload, self._version != seen_version


STATE = PaletteState()


class BridgeHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        return

    def _send_cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Private-Network", "true")

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(HTTPStatus.NO_CONTENT)
        self._send_cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path in ("/v1/palette", "/colors.json"):
            version, payload = STATE.snapshot()
            if not payload:
                self.send_response(HTTPStatus.SERVICE_UNAVAILABLE)
                self._send_cors()
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self.send_response(HTTPStatus.OK)
            self._send_cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("ETag", f'"{version}"')
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        if path == "/v1/events":
            self.send_response(HTTPStatus.OK)
            self._send_cors()
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()

            seen_version, payload = STATE.snapshot()
            try:
                if payload:
                    frame = f"id: {seen_version}\ndata: ".encode("utf-8") + payload + b"\n\n"
                    self.wfile.write(frame)
                    self.wfile.flush()
                while True:
                    next_ver, next_payload, changed = STATE.wait_next(seen_version, timeout=30.0)
                    if changed and next_payload:
                        seen_version = next_ver
                        frame = f"id: {seen_version}\ndata: ".encode("utf-8") + next_payload + b"\n\n"
                        self.wfile.write(frame)
                        self.wfile.flush()
                    else:
                        self.wfile.write(b": keepalive\n\n")
                        self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, OSError):
                return

        self.send_response(HTTPStatus.NOT_FOUND)
        self._send_cors()
        self.send_header("Content-Length", "0")
        self.end_headers()


class ReusableHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def watcher_loop(stop_event: threading.Event) -> None:
    while not stop_event.is_set():
        STATE.load_file()
        stop_event.wait(0.35)


def ensure_initial_palette() -> None:
    import shlex
    import shutil

    if STATE.load_file(force=True):
        return
    env_cmd = os.environ.get("THEME_ZEN_INJECTOR", "").strip()
    if env_cmd:
        subprocess.run(shlex.split(env_cmd), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        STATE.load_file(force=True)
        return
    injector = shutil.which("theme-inject-zen") or str(HOME / ".local/bin/theme-inject-zen")
    if Path(injector).is_file():
        subprocess.run([injector], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        STATE.load_file(force=True)


def main() -> int:
    ensure_initial_palette()
    stop_event = threading.Event()
    server = ReusableHTTPServer((HOST, PORT), BridgeHandler)

    def handle_usr1(_signum, _frame) -> None:
        STATE.load_file(force=True)

    def handle_term(_signum, _frame) -> None:
        stop_event.set()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGUSR1, handle_usr1)
    signal.signal(signal.SIGTERM, handle_term)
    signal.signal(signal.SIGINT, handle_term)

    watcher = threading.Thread(target=watcher_loop, args=(stop_event,), daemon=True)
    watcher.start()

    try:
        server.serve_forever()
    finally:
        stop_event.set()
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
