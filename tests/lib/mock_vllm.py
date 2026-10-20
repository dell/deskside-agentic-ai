#!/usr/bin/env python3
"""Minimal OpenAI/vLLM-shaped mock for readiness/health/monitoring tests (no GPU).
env: MOCK_MODEL, MOCK_PORT=8000, MOCK_READY_AFTER=0 (s until /health=200; <0 never),
     MOCK_DIE_AFTER=0 (>0: exit(1) after N s)"""
import json, os, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
MODEL = os.environ.get("MOCK_MODEL", "mock-model"); PORT = int(os.environ.get("MOCK_PORT", "8000"))
READY = float(os.environ.get("MOCK_READY_AFTER", "0")); DIE = float(os.environ.get("MOCK_DIE_AFTER", "0"))
T0 = time.time(); GEN = [0]; PRO = [0]
def ready(): return READY >= 0 and time.time() - T0 >= READY
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, body, ctype="application/json"):
        b = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path == "/health": self._send(200 if ready() else 503, b"")
        elif self.path == "/v1/models": self._send(200, {"object": "list", "data": [{"id": MODEL, "max_model_len": 4096}]}) if ready() else self._send(503, {})
        elif self.path == "/metrics":
            self._send(200, ('vllm:generation_tokens_total{engine="0",model_name="%s"} %d\nvllm:prompt_tokens_total{engine="0",model_name="%s"} %d\n'
                'vllm:num_requests_running{engine="0",model_name="%s"} 0\nvllm:num_requests_waiting{engine="0",model_name="%s"} 0\n'
                'vllm:kv_cache_usage_perc{engine="0",model_name="%s"} 0.1\n' % (MODEL, GEN[0], MODEL, PRO[0], MODEL, MODEL, MODEL)).encode(), "text/plain")
        else: self._send(404, {})
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); self.rfile.read(n)
        if not ready(): return self._send(503, {})
        GEN[0] += 5; PRO[0] += 10
        self._send(200, {"choices": [{"message": {"role": "assistant", "content": "", "reasoning_content": "OK"}, "finish_reason": "stop"}]})
if DIE > 0:
    def die(): time.sleep(DIE); print("mock: fatal: simulated crash (CUDA error: out of memory)", flush=True); os._exit(1)
    threading.Thread(target=die, daemon=True).start()
print("mock vllm listening", PORT, flush=True)
ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
