"""
Vertex-Proxy für MiroFish.

Nimmt OpenAI-kompatible Chat-Anfragen an (POST /v1/chat/completions) und leitet sie
mit einem OAuth-Token an Gemini auf Vertex AI weiter. Das Token kommt aus den
Application Default Credentials: auf der VM vom angehängten Service-Account
(Metadata-Server, keine Schlüsseldatei), lokal aus `gcloud auth application-default login`.

Zusätzlich:
- setzt `reasoning_effort`, wenn die Anfrage keinen mitbringt (Denkbudget begrenzen)
- wiederholt bei 429/5xx mit Backoff (Vertex teilt Kapazität dynamisch zu)
- protokolliert Tokens und geschätzte Kosten je Aufruf (JSONL)
- verweigert neue Aufrufe, sobald MAX_USD erreicht ist (Notbremse; Budget-Alarme kommen erst Stunden später)
"""

import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import google.auth
import requests
from google.auth.transport.requests import Request
from requests.adapters import HTTPAdapter

PROJECT = os.environ["VERTEX_PROJECT"]
LOCATION = os.environ.get("VERTEX_LOCATION", "eu")
if LOCATION == "global":
    HOST = "aiplatform.googleapis.com"
elif LOCATION in ("eu", "us"):
    # Multiregion mit Datenverarbeitung innerhalb der EU bzw. USA
    HOST = f"aiplatform.{LOCATION}.rep.googleapis.com"
else:
    HOST = f"{LOCATION}-aiplatform.googleapis.com"
UPSTREAM = f"https://{HOST}/v1/projects/{PROJECT}/locations/{LOCATION}/endpoints/openapi/chat/completions"

PROXY_TOKEN = os.environ.get("PROXY_TOKEN", "")
DEFAULT_REASONING_EFFORT = os.environ.get("DEFAULT_REASONING_EFFORT", "low")
PRICE_IN = float(os.environ.get("PRICE_IN_PER_M", "0.50"))
PRICE_OUT = float(os.environ.get("PRICE_OUT_PER_M", "3.00"))
MAX_USD = float(os.environ.get("MAX_USD", "0"))  # 0 = kein Limit
MAX_RETRIES = int(os.environ.get("MAX_RETRIES", "6"))
USAGE_LOG = os.environ.get("USAGE_LOG", "usage.jsonl")
PORT = int(os.environ.get("PORT", "8080"))

_creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
_token_lock = threading.Lock()
_usage_lock = threading.Lock()
_session = requests.Session()
_session.mount("https://", HTTPAdapter(pool_connections=4, pool_maxsize=64))


def _load_spent() -> float:
    try:
        with open(USAGE_LOG, encoding="utf-8") as f:
            return sum(json.loads(line).get("usd", 0) for line in f if line.strip())
    except FileNotFoundError:
        return 0.0


_spent = _load_spent()


def _token() -> str:
    with _token_lock:
        if not _creds.valid:
            _creds.refresh(Request())
        return _creds.token


def _headers() -> dict:
    headers = {"Authorization": f"Bearer {_token()}"}
    # Nur Nutzer-Credentials (lokal) brauchen ein Abrechnungsprojekt im Header, der VM-Service-Account nicht
    quota_project = getattr(_creds, "quota_project_id", None)
    if quota_project:
        headers["x-goog-user-project"] = quota_project
    return headers


def _record(model: str, usage: dict, seconds: float, retries: int) -> None:
    global _spent
    tokens_in = usage.get("prompt_tokens", 0) or 0
    # Gemini rechnet Denk-Tokens als Output ab, sie stecken nur in total_tokens
    tokens_out = (usage.get("total_tokens", 0) or 0) - tokens_in
    usd = tokens_in / 1e6 * PRICE_IN + tokens_out / 1e6 * PRICE_OUT
    with _usage_lock:
        _spent += usd
        with open(USAGE_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({
                "t": round(time.time(), 3), "model": model, "in": tokens_in, "out": tokens_out,
                "usd": round(usd, 6), "s": round(seconds, 2), "retries": retries,
            }) + "\n")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: int, message: str) -> None:
        self._send(status, json.dumps({"error": {"message": message, "code": status}}).encode())

    def do_GET(self):
        if self.path == "/health":
            self._send(200, json.dumps({"ok": True, "spent_usd": round(_spent, 4), "max_usd": MAX_USD}).encode())
        else:
            self._error(404, "not found")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
        if not self.path.rstrip("/").endswith("/chat/completions"):
            return self._error(404, "nur /v1/chat/completions wird unterstützt")
        if PROXY_TOKEN and self.headers.get("Authorization") != f"Bearer {PROXY_TOKEN}":
            return self._error(401, "falsches Proxy-Token")
        if MAX_USD and _spent >= MAX_USD:
            return self._error(429, f"Budget-Notbremse: {_spent:.2f} $ von {MAX_USD:.2f} $ verbraucht")

        payload = json.loads(body or b"{}")
        if payload.get("stream"):
            return self._error(400, "Streaming wird vom Proxy nicht unterstützt")
        model = payload.get("model", "")
        if not model.startswith("google/"):
            payload["model"] = model = f"google/{model}"
        if DEFAULT_REASONING_EFFORT:
            payload.setdefault("reasoning_effort", DEFAULT_REASONING_EFFORT)

        started = time.time()
        resp = None
        for attempt in range(MAX_RETRIES + 1):
            try:
                resp = _session.post(
                    UPSTREAM, json=payload, timeout=300,
                    headers=_headers(),
                )
            except requests.RequestException as e:
                if attempt == MAX_RETRIES:
                    return self._error(502, f"Vertex nicht erreichbar: {e}")
            else:
                if resp.status_code not in (429, 500, 502, 503, 504) or attempt == MAX_RETRIES:
                    break
            time.sleep(min(2 ** attempt, 30))

        content = resp.content
        # Vertex liefert Fehler teils als Liste [{"error": ...}], der OpenAI-Client erwartet ein Objekt
        if resp.status_code >= 400 and content.startswith(b"["):
            try:
                content = json.dumps(json.loads(content)[0]).encode()
            except (ValueError, IndexError):
                pass
        if resp.status_code == 200:
            try:
                _record(model, json.loads(content).get("usage", {}), time.time() - started, attempt)
            except ValueError:
                pass
        self._send(resp.status_code, content)

    def log_message(self, fmt, *args):
        pass  # Zugriffslog unnötig, Kosten stehen im USAGE_LOG


if __name__ == "__main__":
    print(f"Vertex-Proxy auf :{PORT} -> {UPSTREAM} (bisher {_spent:.2f} $)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
