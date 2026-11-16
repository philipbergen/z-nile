import json, sys, os, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
PORT=int(sys.argv[1]); MODEF=sys.argv[2]; LOG=sys.argv[3]
def mode():
    try: return open(MODEF).read().strip()
    except Exception: return 'ok'
def log(s):
    open(LOG,'a').write(s+'\n')
def chunk(delta=None, finish=None, usage=None):
    c={"id":"c1","object":"chat.completion.chunk","created":1,"model":"m","choices":[] if usage else [{"index":0,"delta":delta or {},"finish_reason":finish}]}
    if usage: c["usage"]=usage
    return 'data: '+json.dumps(c)+'\n\n'
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_POST(self):
        n=int(self.headers.get('content-length',0)); body=json.loads(self.rfile.read(n) or b'{}')
        msgs=body.get('messages',[]); m=mode()
        last=msgs[-1] if msgs else {}
        text=json.dumps(msgs)
        log(f"REQ mode={m} nmsg={len(msgs)} lastrole={last.get('role')} tools={'tools' in body} first_user={str([x for x in msgs if x.get('role')=='user'][:1])[:120]}")
        if m.startswith('429'):
            self.send_response(429)
            if m=='429retry': self.send_header('retry-after','400')
            self.send_header('content-type','application/json'); self.end_headers()
            self.wfile.write(json.dumps({"error":{"message":"Rate limit exceeded: too many requests","type":"rate_limit_error"}}).encode()); return
        self.send_response(200); self.send_header('content-type','text/event-stream'); self.end_headers()
        out=[]
        istitle='tools' not in body
        if istitle:
            out=[chunk({"role":"assistant","content":"Title"}),chunk({}, "stop"),chunk(usage={"prompt_tokens":11,"completion_tokens":1,"total_tokens":12})]
        elif last.get('role')=='tool':
            out=[chunk({"role":"assistant","content":"all done"}),chunk({}, "stop"),chunk(usage={"prompt_tokens":100,"completion_tokens":5,"total_tokens":105})]
        elif 'CHILDWORK' in str(msgs[:2]) and 'TOOL:' not in str([x for x in msgs if x.get('role')=='user'][:1]):
            out=[chunk({"role":"assistant","content":"child done"}),chunk({}, "stop"),chunk(usage={"prompt_tokens":5000,"completion_tokens":50,"total_tokens":5050})]
        elif 'TOOL:bash' in text or 'TOOL:par' in text:
            cmd="command -v git; git status --short | head -3; sleep 1"
            tcs=[{"index":0,"id":"call_1","type":"function","function":{"name":"bash","arguments":json.dumps({"command":cmd,"description":"probe"})}}]
            if 'TOOL:par' in text:
                tcs.append({"index":1,"id":"call_2","type":"function","function":{"name":"bash","arguments":json.dumps({"command":"sleep 8; echo long","description":"long"})}})
            out=[chunk({"role":"assistant","tool_calls":tcs}),chunk({}, "tool_calls"),chunk(usage={"prompt_tokens":100,"completion_tokens":20,"total_tokens":120})]
        elif 'TOOL:task' in text:
            args=json.dumps({"description":"child","prompt":"CHILDWORK do the child thing","subagent_type":"general"})
            out=[chunk({"role":"assistant","tool_calls":[{"index":0,"id":"call_t","type":"function","function":{"name":"task","arguments":args}}]}),chunk({}, "tool_calls"),chunk(usage={"prompt_tokens":100,"completion_tokens":20,"total_tokens":120})]
        else:
            out=[chunk({"role":"assistant","content":"ok"}),chunk({}, "stop"),chunk(usage={"prompt_tokens":100,"completion_tokens":2,"total_tokens":102})]
        for o in out: self.wfile.write(o.encode()); self.wfile.flush()
        self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
ThreadingHTTPServer(('127.0.0.1',PORT),H).serve_forever()
