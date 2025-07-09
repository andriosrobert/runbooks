#!/usr/bin/env python3
"""
CloudWatch Logs – Relative Window Fetcher
Author  : Andrios @ hoopdev
Purpose : Pull events from a log group for a preset relative window
          (5 m … 4 w), matching the AWS-console buttons – and print them
          in a console-like, columnar format.
Requires: boto3, AWS creds with logs:FilterLogEvents
Optional : colorama  (for faint/bright colourisation)
"""

import boto3
import time
import datetime as dt
import os
import re
import sys
import json
from textwrap import shorten
from datetime import timezone

# ───────── UI parameters (no free-text numbers) ─────────
# {{ .logGroupName | type "select" | description "Choose CloudWatch log group" | options "/aws/containerinsights/hoop-prod/application" "/aws/containerinsights/hoop-prod/dataplane" "/aws/eks/hoop-prod/cluster" "/aws/lambda/logdna_cloudwatch" "/aws/rds/instance/hoopdb/postgresql" | asenv "LOG_GROUP_NAME" }}
# {{ .relativeWindow | type "select" | description "Time window duration" | options "5m" "10m" "15m" "30m" "45m" "1h" "2h" "3h" "6h" "8h" "12h" "1d" "2d" "3d" "4d" "5d" "6d" "1w" "2w" "3w" "4w" | default "5m" | asenv "RELATIVE_WINDOW" }}
# {{ .specificMonth | type "select" | description "Month (optional - leave as 'current' for relative mode)" | options "current" "January" "February" "March" "April" "May" "June" "July" "August" "September" "October" "November" "December" | default "current" | asenv "SPECIFIC_MONTH" }}
# {{ .specificDay | type "select" | description "Day of month (optional - use with month selection)" | options "current" "1" "2" "3" "4" "5" "6" "7" "8" "9" "10" "11" "12" "13" "14" "15" "16" "17" "18" "19" "20" "21" "22" "23" "24" "25" "26" "27" "28" "29" "30" "31" | default "current" | asenv "SPECIFIC_DAY" }}

# Get values from environment variables (with defaults for local testing)
log_group_name = os.environ.get('LOG_GROUP_NAME', '/aws/containerinsights/hoop-prod/application')
relative_window = os.environ.get('RELATIVE_WINDOW', '5m')
specific_month = os.environ.get('SPECIFIC_MONTH', 'current')
specific_day = os.environ.get('SPECIFIC_DAY', 'current')

# ────────────────────────────────────────────────────────

# ────────── optional colours (falls back gracefully) ──────────
try:
    from colorama import Fore, Style, init as _init_colour
    _init_colour()
    _USE_COLOURS = True
except ImportError:                       # keep running if colour not present
    class _Faux:                          # dummy attrs so references still work
        def __getattr__(self, _n): return ""
    Fore = Style = _Faux()
    _USE_COLOURS = False

_DIM   = Fore.LIGHTBLACK_EX if _USE_COLOURS else ""
_BOLD  = Fore.WHITE          if _USE_COLOURS else ""
_HEAD  = Fore.CYAN           if _USE_COLOURS else ""

def _c(text: str, colour: str) -> str:
    """Wrap `text` in `colour` if colour output enabled."""
    return f"{colour}{text}{Style.RESET_ALL}" if _USE_COLOURS else text

# ───────────────────────── helpers ────────────────────────────
def window_to_seconds(win: str) -> int:
    """Convert a window like '15m' / '3h' / '2w' → seconds."""
    m = re.fullmatch(r"(\d+)([mhdw])", win)
    if not m:
        sys.exit(f"❌ Unsupported window: {win}")
    n, unit = int(m.group(1)), m.group(2)
    return n * {"m": 60, "h": 3600, "d": 86_400, "w": 604_800}[unit]

def _extract_msg(raw: str) -> str:
    """
    If `raw` is JSON, show its 'log'/'message'/'msg' field;
    otherwise return the string as-is (trimmed).
    """
    raw = raw.strip()
    if raw.startswith("{") and raw.endswith("}"):
        try:
            payload = json.loads(raw)
            for k in ("log", "message", "msg"):
                if k in payload:
                    return str(payload[k]).rstrip()
        except json.JSONDecodeError:
            pass
        return shorten(raw, width=120, placeholder=" … ")
    return raw

def month_name_to_number(month_name: str) -> int:
    """Convert month name to number (1-12)."""
    months = {
        "january": 1, "february": 2, "march": 3, "april": 4,
        "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12
    }
    return months.get(month_name.lower(), 0)

# ─────────────────────────  main  ─────────────────────────────
def main() -> None:
    now = dt.datetime.now(timezone.utc)
    window_seconds = window_to_seconds(relative_window)
    
    # Determine if we're using specific date or relative mode
    use_specific_date = (specific_month != "current" or 
                        specific_day != "current")
    
    if use_specific_date:
        # Build the specific date
        year = now.year
        month = month_name_to_number(specific_month) if specific_month != "current" else now.month
        day = int(specific_day) if specific_day != "current" else now.day
        
        try:
            # Create the end datetime at the end of the specified day (23:59:59)
            end_date = dt.datetime(year, month, day, 23, 59, 59, 999999, tzinfo=timezone.utc)
            # Ensure we don't query future dates
            if end_date > now:
                end_date = now
            end_ms = int(end_date.timestamp() * 1000)
            
            # Start time is the window duration before the end of that day
            start_ms = end_ms - (window_seconds * 1000)
            
            window_desc = f"{relative_window} window on {end_date.strftime('%Y-%m-%d')}"
        except ValueError as e:
            sys.exit(f"❌ Invalid date: {e}")
    else:
        # Original relative mode - window ending at current time
        end_ms = int(now.timestamp() * 1000)
        start_ms = end_ms - (window_seconds * 1000)
        window_desc = f"last {relative_window}"

    client = boto3.client("logs")
    params = dict(
        logGroupName = log_group_name,
        startTime    = start_ms,
        endTime      = end_ms,
    )

    print(
        f"⏱️  Window : {window_desc}  "
        f"({dt.datetime.utcfromtimestamp(start_ms/1000):%Y-%m-%d %H:%M:%S}Z → "
        f"{dt.datetime.utcfromtimestamp(end_ms/1000):%Y-%m-%d %H:%M:%S}Z)\n"
        f"📒 Group  : {log_group_name}\n"
        "🔍 Pattern: (none)\n"
    )

    events, token = [], None
    while True:
        resp   = client.filter_log_events(**params, nextToken=token) if token else client.filter_log_events(**params)
        events.extend(resp.get("events", []))
        token  = resp.get("nextToken")
        if not token:
            break

    print(f"✅ {len(events)} event(s) retrieved\n")

    # — AWS-console-style table header —
    print(_c(f"{'Event time':<24} {'Ingestion':<24} Message", _HEAD))

    for ev in events:
        ts_event = dt.datetime.fromtimestamp(ev["timestamp"]      / 1000, tz=timezone.utc)
        ts_ing   = dt.datetime.fromtimestamp(ev["ingestionTime"]  / 1000, tz=timezone.utc) \
                   if "ingestionTime" in ev else None

        col_event = ts_event.isoformat(timespec="milliseconds").replace("+00:00", "Z")
        col_ing   = ts_ing.isoformat(timespec="milliseconds").replace("+00:00", "Z") if ts_ing else ""

        print(
            f"{_c(f'{col_event:<24}', _DIM)} "
            f"{_c(f'{col_ing:<24}',   _DIM)} "
            f"{_c(_extract_msg(ev['message']), _BOLD)}"
        )

if __name__ == "__main__":
    main()
