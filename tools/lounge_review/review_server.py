import json, subprocess, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).parent
OUT = ROOT / "lounge_review_batch.json"
DECISIONS = ROOT / "lounge_diverse_review_decisions.json"

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(ROOT), **kwargs)
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
    def do_POST(self):
        if self.path == "/api/save-review":
            try:
                size = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(size))
                saved = json.loads(DECISIONS.read_text(encoding="utf-8")) if DECISIONS.exists() else {"reviews": {}}
                saved.setdefault("reviews", {})[payload["batch_id"]] = payload
                DECISIONS.write_text(json.dumps(saved, indent=2), encoding="utf-8")
                self.send_response(204); self.end_headers()
            except Exception as error:
                self.send_error(400, str(error))
            return
        if self.path != "/api/generate-next": return self.send_error(404)
        try:
            count = len(json.loads(OUT.read_text()).get("items", [])) if OUT.exists() else 0
            subprocess.run([sys.executable, str(ROOT / "generate_batch.py"), str(count + 1)], cwd=ROOT, timeout=150, check=True)
            data = OUT.read_bytes()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
        except Exception as error:
            self.send_error(500, str(error))

class ReusableThreadingHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True

if __name__ == "__main__":
    server = ReusableThreadingHTTPServer(("127.0.0.1", 8765), Handler)
    print("Open http://127.0.0.1:8765")
    server.serve_forever()
