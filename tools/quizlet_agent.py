# /// script
# requires-python = ">=3.11"
# dependencies = ["curl_cffi>=0.7", "websockets>=13"]
# ///
"""Mac side of flashdeck-relay: fetches Quizlet sets for the web import page.

Quizlet captchas datacenter IPs and non-browser TLS, so the fetch has to come
from a home connection with a browser fingerprint (curl_cffi impersonate).
Keeps a websocket to the relay Worker; each message is {rid, setId}, each
reply is {rid, title, cards:[{front, back, image?, backImage?}]} or {rid, error}.

Run:  uv run tools/quizlet_agent.py            (launchd: com.sly.flashdeck-quizlet)
Test: uv run tools/quizlet_agent.py --set 220018802
"""
import asyncio
import json
import os
import subprocess
import sys

import websockets
from curl_cffi import requests

RELAY = os.environ.get("FD_RELAY", "wss://flashdeck-relay.sylvesterassiamahpm.workers.dev/agent")
API = "https://quizlet.com/webapi/3.4"
PER_PAGE = 500  # Quizlet's cap


def agent_key() -> str:
    if os.environ.get("FD_AGENT_KEY"):
        return os.environ["FD_AGENT_KEY"]
    return subprocess.run(
        ["security", "find-generic-password", "-s", "flashdeck-relay-key", "-w"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def get(url: str) -> dict:
    r = requests.get(url, impersonate="chrome", timeout=30)
    if r.status_code == 403:
        raise RuntimeError("Quizlet showed a captcha to the Mac too — try again in a minute.")
    if r.status_code == 404:
        raise RuntimeError("Quizlet says that set doesn’t exist (or it’s private).")
    r.raise_for_status()
    return r.json()


def side(item: dict, label: str) -> tuple[str, str | None]:
    for s in item.get("cardSides", []):
        if s.get("label") == label:
            text = " ".join(m.get("plainText", "") for m in s.get("media", []) if m.get("type") == 1).strip()
            image = next((m.get("url") for m in s.get("media", []) if m.get("type") == 2 and m.get("url")), None)
            return text, image
    return "", None


def fetch_set(set_id: str) -> dict:
    meta = get(f"{API}/sets/{set_id}")["responses"][0]["models"]["set"][0]
    items, page, token = [], 1, None
    while True:
        url = (f"{API}/studiable-item-documents?filters%5BstudiableContainerId%5D={set_id}"
               f"&filters%5BstudiableContainerType%5D=1&perPage={PER_PAGE}&page={page}")
        if token:
            url += f"&pagingToken={token}"
        resp = get(url)["responses"][0]
        batch = resp["models"].get("studiableItem", [])
        items += batch
        paging = resp.get("paging") or {}
        token = paging.get("token")
        if not batch or len(items) >= paging.get("total", 0) or page >= 20:
            break
        page += 1
    cards = []
    for item in sorted(items, key=lambda i: i.get("rank", 0)):
        if item.get("isDeleted"):
            continue
        front, image = side(item, "word")
        back, back_image = side(item, "definition")
        if not front and image:
            front = "(picture)"
        if not back and back_image:
            back = "(picture)"
        if not front or not back:
            continue
        card = {"front": front, "back": back}
        if image:
            card["image"] = image
        if back_image:
            card["backImage"] = back_image
        cards.append(card)
    return {"title": meta.get("title", ""), "cards": cards}


async def serve() -> None:
    url = f"{RELAY}?key={agent_key()}"
    delay = 2
    while True:
        try:
            async with websockets.connect(url, ping_interval=None, max_size=None) as ws:
                print("connected", flush=True)
                delay = 2

                async def keepalive():
                    while True:
                        await asyncio.sleep(30)
                        await ws.send("ping")

                ka = asyncio.create_task(keepalive())
                try:
                    async for raw in ws:
                        if raw == "pong":
                            continue
                        msg = json.loads(raw)
                        try:
                            result = await asyncio.to_thread(fetch_set, str(msg["setId"]))
                            print(f"set {msg['setId']}: {len(result['cards'])} cards", flush=True)
                        except Exception as e:  # report every failure back to the page
                            result = {"error": str(e)}
                            print(f"set {msg.get('setId')}: {e}", flush=True)
                        await ws.send(json.dumps({"rid": msg["rid"], **result}))
                finally:
                    ka.cancel()
        except Exception as e:
            print(f"disconnected: {e}; retry in {delay}s", flush=True)
        await asyncio.sleep(delay)
        delay = min(delay * 2, 60)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--set":
        r = fetch_set(sys.argv[2])
        print(r["title"], len(r["cards"]), "cards")
        print(json.dumps(r["cards"][:3], ensure_ascii=False, indent=1))
    else:
        asyncio.run(serve())
