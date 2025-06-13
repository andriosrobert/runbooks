#!/usr/bin/env python3
"""
Runbook – CloudWatch Logs Time-window Fetcher
Author : Andrios @ hoopdev
Purpose: Pull log events from a log-group for either a *relative* period
         (e.g. last 30 min) or an *absolute* UTC range. Supports
         CloudWatch filter-patterns for extra precision.
Requires: boto3, AWS CLI creds/profile with logs:FilterLogEvents
"""

import boto3
import datetime as dt
import time
import sys

# ───────── Parameters (UI controls) ─────────
log_group_name = '''
{{ .logGroupName    | type "select"
                    | description "Select AWS CloudWatch log group"
                    | options   "/aws/containerinsights/hoop-prod/application"
                                "/aws/containerinsights/hoop-prod/dataplane"
                                "/aws/eks/hoop-prod/cluster"
                                "/aws/lambda/logdna_cloudwatch"
                                "/aws/rds/instance/hoopdb/postgresql"
}}
'''.strip()

time_mode = '''
{{ .timeMode | type "select"
             | description "Time selector mode"
             | options "Relative" "Absolute"
             | default "Relative"
}}
'''.strip()

# —— Relative fields ——
relative_value = '''
{{ .relativeValue | description "Relative amount (integer)" | default "5" }}
'''.strip()

relative_unit = '''
{{ .relativeUnit | type "select"
                 | description "Unit"
                 | options "Minutes" "Hours" "Days"
                 | default "Minutes"
}}
'''.strip()

# —— Absolute fields ——
start_time_iso = '''
{{ .startTime | description "Start time (YYYY-MM-DDTHH:MM:SSZ)" }}
'''.strip()

end_time_iso = '''
{{ .endTime | description "End time   (YYYY-MM-DDTHH:MM:SSZ). Leave blank = now()" }}
'''.strip()

# —— Optional pattern & profile ——
filter_pattern = '''
{{ .filterPattern | description "Optional CloudWatch Logs filter-pattern" }}
'''.strip()

aws_profile = '''
{{ .profile | description "AWS CLI profile (leave blank for default)" }}
'''.strip()
# ────────────────────────────────────────────


# ───────── Helpers ─────────
def iso_to_epoch_ms(iso_str: str) -> int:
    """Convert ISO-8601 (UTC) to epoch milliseconds."""
    try:
        dt_obj = dt.datetime.strptime(iso_str, "%Y-%m-%dT%H:%M:%SZ")
        return int(dt_obj.replace(tzinfo=dt.timezone.utc).timestamp() * 1000)
    except ValueError as exc:
        sys.exit(f"❌ Invalid ISO-8601 timestamp: {iso_str!r} → {exc}")

def relative_to_epoch_ms(value: int, unit: str) -> int:
    """Return epoch ms for 'now − value unit'."""
    seconds = {
        "Minutes": 60,
        "Hours"  : 3600,
        "Days"   : 86400,
    }.get(unit)
    if seconds is None:
        sys.exit(f"❌ Unsupported unit: {unit}")
    return int((time.time() - value * seconds) * 1000)


# ───────── Derive time window ─────────
now_ms = int(time.time() * 1000)

if time_mode == "Relative":
    if not relative_value.isdigit():
        sys.exit("❌ relativeValue must be an integer")
    start_ms = relative_to_epoch_ms(int(relative_value), relative_unit)
    end_ms   = now_ms
else:  # Absolute
    if not start_time_iso:
        sys.exit("❌ startTime is required for Absolute mode")
    start_ms = iso_to_epoch_ms(start_time_iso)
    end_ms   = iso_to_epoch_ms(end_time_iso) if end_time_iso else now_ms

if start_ms >= end_ms:
    sys.exit("❌ Start-time must be earlier than end-time")

# ───────── Call CloudWatch Logs ─────────
session_kwargs = {"profile_name": aws_profile} if aws_profile else {}
session   = boto3.Session(**session_kwargs)
client    = session.client("logs")

print(
    f"⏱️  Fetching events from {dt.datetime.utcfromtimestamp(start_ms/1000):%Y-%m-%d %H:%M:%S}Z "
    f"→ {dt.datetime.utcfromtimestamp(end_ms/1000):%Y-%m-%d %H:%M:%S}Z\n"
    f"📒 Log group  : {log_group_name}\n"
    f"🔎 Filter-pat : {filter_pattern or '(none)'}\n"
)

params = {
    "logGroupName": log_group_name,
    "startTime"   : start_ms,
    "endTime"     : end_ms,
}
if filter_pattern:
    params["filterPattern"] = filter_pattern

events = []
next_token = None
while True:
    if next_token:
        params["nextToken"] = next_token
    resp = client.filter_log_events(**params)
    events.extend(resp.get("events", []))
    next_token = resp.get("nextToken")
    if not next_token:
        break

print(f"✅ Retrieved {len(events)} event(s)\n-----\n")

for ev in events:
    ts = dt.datetime.utcfromtimestamp(ev['timestamp']/1000).isoformat() + "Z"
    print(f"[{ts}] {ev['message'].rstrip()}")  # trim trailing newline if any
