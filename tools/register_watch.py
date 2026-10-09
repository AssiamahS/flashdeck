#!/usr/bin/env python3
"""Register the iPhone's paired Apple Watch for ad hoc builds, then rebuild install.html.

Run with the iPhone on USB (companion lookup is refused over Wi-Fi sync):
    python3 tools/register_watch.py            # read UDID from the phone
    python3 tools/register_watch.py <watchUDID> # or pass it yourself
"""
import json, re, subprocess, sys

sys.path.insert(0, "/Users/djsly/asc-mcp")
import server as asc  # same ASC key/issuer the asc MCP uses

REPO = "AssiamahS/flashdeck"


def watch_udid() -> str:
    out = subprocess.run(["pymobiledevice3", "companion", "list"],
                         capture_output=True, text=True, timeout=60)
    ids = re.findall(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9a-f]{40}", out.stdout)
    if not ids:
        sys.exit(f"no paired watch found (is the iPhone on USB and unlocked?)\n{out.stdout}{out.stderr}")
    return ids[0]


def main() -> None:
    udid = sys.argv[1] if len(sys.argv) > 1 else watch_udid()
    print("watch UDID:", udid)
    st, d = asc.api("GET", "/v1/devices?limit=200")
    if any(x["attributes"]["udid"].lower() == udid.lower() for x in d.get("data", [])):
        print("already registered")
    else:
        st, d = asc.api("POST", "/v1/devices", {"data": {"type": "devices", "attributes": {
            "name": "watch", "udid": udid, "platform": "IOS"}}})
        print("register:", st, json.dumps(d)[:300])
        if st >= 300:
            sys.exit(1)
    subprocess.run(["gh", "variable", "set", "ADHOC_WATCH", "-b", "1", "-R", REPO], check=True)
    subprocess.run(["gh", "workflow", "run", "ios.yml", "-R", REPO], check=True)
    print("ADHOC_WATCH=1 set, iOS workflow dispatched; install.html updates in ~15 min")


if __name__ == "__main__":
    main()
