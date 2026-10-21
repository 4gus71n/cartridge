"""Evaluate JS in the app's game WebView over CDP: python3 tools/webview_eval.py '<expr>' [port]."""
import json
import sys
import urllib.request

import websocket  # type: ignore  # pip: websocket-client

port = sys.argv[2] if len(sys.argv) > 2 else "9333"
pages = json.load(urllib.request.urlopen(f"http://localhost:{port}/json"))
ws = websocket.create_connection(pages[0]["webSocketDebuggerUrl"], timeout=10, suppress_origin=True)
ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                    "params": {"expression": sys.argv[1], "returnByValue": True, "awaitPromise": True}}))
while True:
    msg = json.loads(ws.recv())
    if msg.get("id") == 1:
        print(json.dumps(msg.get("result", msg), indent=None)[:2000])
        break
