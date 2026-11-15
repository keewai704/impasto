#!/usr/bin/env python3
"""Print, as one JSON line, the OpenCode Go plan's usage windows.

Usage: opencode_usage.py

Asks `https://opencode.ai/zen/go/v1/usage` with the API key read from
$OPENCODE_API_KEY_FILE (by default /run/agenix/opencode-api-key). Each window (five hours, week, month) comes back as a percentage
and the time it resets; without a key or a network the report says only
`available: false`.
"""

import json
import os
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

KEY_FILE = Path(os.environ.get("OPENCODE_API_KEY_FILE", "/run/agenix/opencode-api-key"))
URL = "https://opencode.ai/zen/go/v1/usage"
WINDOWS = [("rolling", "5 hours", 300), ("weekly", "Week", 10080), ("monthly", "Month", 43200)]


def main() -> None:
    try:
        key = KEY_FILE.read_text().strip()
        request = urllib.request.Request(URL, headers={
            "Authorization": f"Bearer {key}",
            # The default Python-urllib agent is refused with 403.
            "User-Agent": "impasto",
        })
        with urllib.request.urlopen(request, timeout=15) as response:
            usage = json.load(response)["usage"]
    except Exception as error:
        print(f"opencode_usage: {error}", file=sys.stderr)
        print(json.dumps({"available": False}))
        return

    limits = []
    for field, name, minutes in WINDOWS:
        window = usage.get(field)
        if not window:
            continue
        resets = datetime.fromisoformat(window["resetsAt"].replace("Z", "+00:00")).timestamp()
        limits.append({
            "name": name,
            "minutes": minutes,
            "used": window["percent"] / 100,
            "resets": resets,
            "limited": window.get("status", "ok") != "ok",
        })
    print(json.dumps({"available": True, "limits": limits}))


if __name__ == "__main__":
    main()
