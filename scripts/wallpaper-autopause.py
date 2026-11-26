#!/usr/bin/env python3
"""Pause/resume live wallpaper daemons automatically when a fullscreen window or game covers an output."""

from __future__ import annotations

import atexit
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

COVER_TOLERANCE = 8
WALLPAPER_BINS = {
    "ryoku-livewall",
    "livewall",
    "mpvpaper",
    ".mpvpaper-wrapped",
    "linux-wallpaperengine",
}
GAME_APP_PREFIXES = ("steam_app_", "gamescope")
REFRESH_EVENTS = {
    "WorkspacesChanged",
    "WorkspaceActivated",
    "WindowsChanged",
    "WindowOpenedOrChanged",
    "WindowClosed",
    "WindowLayoutsChanged",
    "WindowFocusChanged",
    "OverviewOpenedOrClosed",
}


def niri_json(*args: str):
    proc = subprocess.run(
        ["niri", "msg", "-j", *args],
        capture_output=True,
        text=True,
        timeout=2.0,
        check=False,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def find_wallpaper_pids() -> list[int]:
    pids: list[int] = []
    proc_root = Path("/proc")
    for entry in proc_root.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmdline_raw = (entry / "cmdline").read_bytes()
            if not cmdline_raw:
                continue
            argv0 = cmdline_raw.split(b"\x00", 1)[0].decode("utf-8", errors="ignore")
            base = os.path.basename(argv0)
            if base in WALLPAPER_BINS:
                pids.append(int(entry.name))
        except OSError:
            continue
    return pids


def should_pause(overview_open: bool) -> bool:
    if overview_open:
        return False

    outputs = niri_json("outputs")
    workspaces = niri_json("workspaces")
    windows = niri_json("windows")
    if not isinstance(outputs, dict) or not isinstance(workspaces, list) or not isinstance(windows, list):
        return False

    output_sizes: dict[str, tuple[int, int]] = {}
    for name, info in outputs.items():
        if not isinstance(info, dict):
            continue
        logical = info.get("logical") or {}
        w, h = int(logical.get("width") or 0), int(logical.get("height") or 0)
        if w > 0 and h > 0:
            output_sizes[name] = (w, h)

    active_ws: dict[int, str] = {}
    for ws in workspaces:
        if isinstance(ws, dict) and ws.get("is_active") and ws.get("id") is not None:
            active_ws[int(ws["id"])] = str(ws.get("output") or "")

    for win in windows:
        if not isinstance(win, dict):
            continue
        ws_id = win.get("workspace_id")
        if ws_id is None or int(ws_id) not in active_ws:
            continue
        app_id = str(win.get("app_id") or "").lower()
        if app_id.startswith(GAME_APP_PREFIXES):
            return True
        if win.get("is_floating"):
            continue
        out_name = active_ws[int(ws_id)]
        out_geom = output_sizes.get(out_name)
        if not out_geom:
            continue
        out_w, out_h = out_geom
        layout = win.get("layout") or {}
        win_size = layout.get("window_size") or [0, 0]
        if len(win_size) < 2:
            continue
        win_w, win_h = float(win_size[0]), float(win_size[1])
        full_width = win_w * 10 >= out_w * 9
        covers_height = win_h + COVER_TOLERANCE >= out_h
        if full_width and covers_height:
            return True

    return False


class PauseController:
    def __init__(self) -> None:
        self.paused = False

    def apply(self, want_pause: bool) -> None:
        if want_pause == self.paused:
            return
        sig = signal.SIGSTOP if want_pause else signal.SIGCONT
        for pid in find_wallpaper_pids():
            try:
                os.kill(pid, sig)
            except OSError:
                pass
        self.paused = want_pause

    def resume_all(self) -> None:
        for pid in find_wallpaper_pids():
            try:
                os.kill(pid, signal.SIGCONT)
            except OSError:
                pass
        self.paused = False


def main() -> int:
    ctrl = PauseController()
    atexit.register(ctrl.resume_all)

    def handle_exit(_signum, _frame) -> None:
        ctrl.resume_all()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_exit)
    signal.signal(signal.SIGINT, handle_exit)

    overview_open = False

    while True:
        ctrl.apply(should_pause(overview_open))
        try:
            proc = subprocess.Popen(
                ["niri", "msg", "-j", "event-stream"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
        except OSError:
            time.sleep(2.0)
            continue

        assert proc.stdout is not None
        try:
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(ev, dict):
                    continue
                if "OverviewOpenedOrClosed" in ev:
                    overview_open = bool(ev["OverviewOpenedOrClosed"].get("is_open", False))
                if any(k in ev for k in REFRESH_EVENTS):
                    ctrl.apply(should_pause(overview_open))
        finally:
            proc.kill()
            proc.wait()

        ctrl.resume_all()
        time.sleep(1.0)


if __name__ == "__main__":
    sys.exit(main())
