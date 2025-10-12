#!/usr/bin/env python3
import json, os, signal, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from datetime import datetime

DATA_FILE = "blockchain.json"
HOST, PORT = "0.0.0.0", 21801

# --- Simple blockchain store ---
def load_chain():
    if not os.path.exists(DATA_FILE):
        genesis = {
            "index": 0,
            "timestamp": str(datetime.utcnow()),
            "data": "Genesis Block",
            "prev_hash": "0"
        }
        save_chain([genesis])
        return [genesis]
    with open(DATA_FILE, "r") as f:
        return json.load(f)

def save_chain(chain):
    with open(DATA_FILE, "w") as f:
        json.dump(chain, f, indent=2)

chain = load_chain()

# --- Web server ---
class NodeHandler(BaseHTTPRequestHandler):
    def _send(self, code, data):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        if self.path == "/ping":
            self._send(200, {"status": "ok", "msg": "pong"})
        elif self.path == "/status":
            self._send(200, {
                "node": "EAGL Node v0.1",
                "blocks": len(chain),
                "last_block": chain[-1]
            })
        elif self.path == "/block":
            self._send(200, chain[-1])
        else:
            self._send(404, {"error": "Not found"})

def run_server():
    httpd = HTTPServer((HOST, PORT), NodeHandler)
    print(f"🚀 EAGL Node online at http://{HOST}:{PORT}")
    print("Press Ctrl+C to stop.")
    def shutdown(sig, frame):
        print("\n🛑 Node shutting down...")
        httpd.server_close()
        sys.exit(0)
    signal.signal(signal.SIGINT, shutdown)
    httpd.serve_forever()

if __name__ == "__main__":
    run_server()
