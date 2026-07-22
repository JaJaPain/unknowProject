import json, subprocess, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).parent
OUT = ROOT / "lounge_review_batch.json"

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(ROOT), **kwargs)
    def do_POST(self):
        if self.path != "/api/generate-next": return self.send_error(404)
        try:
            count = len(json.loads(OUT.read_text()).get("items", [])) if OUT.exists() else 0
            subprocess.run([sys.executable, str(ROOT / "generate_batch.py"), str(count + 1)], cwd=ROOT, timeout=150, check=True)
            data = OUT.read_bytes()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
        except Exception as error:
            self.send_error(500, str(error))

if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 8765), Handler)
    print("Open http://127.0.0.1:8765")
    server.serve_forever()
