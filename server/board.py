#!/usr/bin/env python3
"""kirothon-board — 팀 Kiro 4대 + Fable 오케스트라용 상황판 (stdlib만 사용).

POST /post    {"lane","kind","text","to"?}   이벤트 1건 추가
GET  /board?lane=X                           사람/에이전트용 텍스트 요약
GET  /events?since=N                         JSON (오케스트라용)
GET  /gate?lane=X                            go | hold ...
GET  /ip                                     (무인증) 서버가 보는 내 IP — 등록 요청용
GET|POST /allow, POST /deny                  (관리자) IP allowlist 조회·추가·삭제
인증: Authorization: Bearer $BOARD_TOKEN (팀) | $BOARD_ADMIN_TOKEN (팀장: order/hold/release/allow)
IP:  팀 토큰은 allow.txt 에 있는 IP/CIDR 에서만 통한다. 관리자 토큰은 IP 무관(팀장이 어디서든 등록할 수 있어야 하므로).
     127.0.0.1 에만 바인드하고 Caddy가 X-Real-IP 를 덮어쓰므로 헤더를 신뢰한다.
"""
import ipaddress, json, os, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

TOKEN = os.environ["BOARD_TOKEN"]
ADMIN = os.environ["BOARD_ADMIN_TOKEN"]
ALLOW = os.environ.get("BOARD_ALLOW", os.path.expanduser("~/kirothon-board/allow.txt"))
STORE = os.environ.get("BOARD_STORE", os.path.expanduser("~/kirothon-board/events.jsonl"))
PORT = int(os.environ.get("BOARD_PORT", "8377"))
KINDS = {"status", "done", "blocked", "ask", "order", "note", "human", "hold", "release"}
DIRECTED = {"order", "hold", "release"}  # 'to' 필수, 레인 최신 상태로 치지 않음
MAX_BODY, MAX_TEXT = 16 * 1024, 2000

lock = threading.Lock()
events = []


def load():
    if os.path.exists(STORE):
        with open(STORE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    events.append(json.loads(line))


def allow_rows():
    rows = []
    if os.path.exists(ALLOW):
        with open(ALLOW, encoding="utf-8") as f:
            for line in f:
                parts = line.split(None, 1)
                if parts and not parts[0].startswith("#"):
                    rows.append((parts[0], parts[1].strip() if len(parts) > 1 else ""))
    return rows


def ip_allowed(ip):
    try:
        addr = ipaddress.ip_address(ip)
        return any(addr in ipaddress.ip_network(net, strict=False) for net, _ in allow_rows())
    except ValueError:
        return False


def hhmm(ts):
    return time.strftime("%H:%M", time.localtime(ts))


def held(lane, evs):
    """lane이 멈춰야 하면 사유 이벤트를, 아니면 None. 규칙:
    - hold(to=lane|all) 이후 release(to=같은 범위 또는 all)가 없으면 정지
    - lane이 human을 올렸고 그 뒤 lane 앞으로 order/release가 없으면 정지"""
    why = {}
    for e in evs:
        k, to = e["kind"], e.get("to")
        if k == "hold" and to in (lane, "all"):
            why[to] = e
        elif k == "release" and to in (lane, "all"):
            why.pop(to, None)
            if to == lane or to == "all":
                why.pop("human", None)
            if to == "all":
                why.pop(lane, None)
        elif k == "human" and e["lane"] == lane:
            why["human"] = e
        elif k == "order" and to == lane:
            why.pop("human", None)
    return next(iter(why.values()), None)


def render(lane):
    with lock:
        evs = list(events)
    out = []
    h = held(lane, evs) if lane else None
    if h:
        out.append(f"🛑 STOP [{lane}] — #{h['id']} {h['kind']} ({h['lane']}): {h['text']}")
        out.append("   지금 하던 파일만 저장하고 멈춘다. 새 작업을 시작하지 않는다. `board.sh wait` 로 풀릴 때까지 대기.\n")
    latest = {}
    for e in evs:
        if e["kind"] not in DIRECTED:
            latest[e["lane"]] = e
    out.append("== 레인별 최신 ==")
    for name in sorted(latest):
        e = latest[name]
        mark = {"blocked": "⛔", "done": "✅", "ask": "❓", "human": "🙋"}.get(e["kind"], "·")
        out.append(f"{mark} [{name}] {hhmm(e['ts'])} {e['kind']}: {e['text']}")
    if not latest:
        out.append("(아직 없음)")

    blocked = [e for n, e in latest.items() if e["kind"] in ("blocked", "ask", "human")]
    if blocked:
        out.append("\n== 막힘/질문 (미해결) ==")
        for e in blocked:
            out.append(f"#{e['id']} [{e['lane']}] {e['text']}")

    orders = [e for e in evs if e["kind"] == "order" and e.get("to") in (lane, "all")]
    if lane:
        out.append(f"\n== [{lane}] 에게 온 지시 (최근 5) ==")
        for e in orders[-5:]:
            out.append(f"#{e['id']} {hhmm(e['ts'])} ({e['lane']}→{e['to']}) {e['text']}")
        if not orders:
            out.append("(없음)")

    out.append("\n== 최근 이벤트 10 ==")
    for e in evs[-10:]:
        to = f"→{e['to']}" if e.get("to") else ""
        out.append(f"#{e['id']} {hhmm(e['ts'])} [{e['lane']}{to}] {e['kind']}: {e['text'][:200]}")
    return "\n".join(out) + "\n"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def client_ip(self):
        return self.headers.get("X-Real-IP") or self.client_address[0]

    def authed(self, admin=False):
        """관리자 토큰은 어디서든. 팀 토큰은 allowlist IP에서만."""
        got = self.headers.get("Authorization", "")
        if got == f"Bearer {ADMIN}":
            return True
        if admin:
            self.send(403, "admin token required\n")
            return False
        if got != f"Bearer {TOKEN}":
            self.send(401, "unauthorized\n")
            return False
        if not ip_allowed(self.client_ip()):
            self.send(403, f"ip {self.client_ip()} not allowed — 팀장에게 이 IP 등록 요청\n")
            return False
        return True

    def body(self):
        n = int(self.headers.get("Content-Length", "0"))
        if n <= 0 or n > MAX_BODY:
            self.send(413, "body too large\n")
            return None
        try:
            return json.loads(self.rfile.read(n))
        except ValueError:
            self.send(400, "bad json\n")
            return None

    def admin_post(self, path):
        if not self.authed(admin=True):
            return
        d = self.body()
        if d is None:
            return
        try:
            net = str(ipaddress.ip_network(str(d.get("ip", "")), strict=False))
        except ValueError:
            return self.send(400, "need {ip: addr or cidr}\n")
        with lock:
            rows = [r for r in allow_rows() if r[0] != net]
            if path == "/allow":
                rows.append((net, str(d.get("memo", ""))[:60].replace("\n", " ")))
            with open(ALLOW, "w", encoding="utf-8") as f:
                f.writelines(f"{n} {m}\n" for n, m in rows)
        self.send(200, f"ok {path[1:]} {net} (총 {len(rows)})\n")

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path == "/healthz":
            return self.send(200, "ok\n")
        if u.path == "/ip":
            return self.send(200, self.client_ip() + "\n")
        if u.path == "/allow":
            if self.authed(admin=True):
                self.send(200, "".join(f"{n}\t{m}\n" for n, m in allow_rows()) or "(비어 있음)\n")
            return
        if not self.authed():
            return
        if u.path == "/board":
            return self.send(200, render(q.get("lane", [""])[0]))
        if u.path == "/gate":
            with lock:
                h = held(q.get("lane", [""])[0], list(events))
            return self.send(200, f"hold #{h['id']} {h['text']}\n" if h else "go\n")
        if u.path == "/events":
            since = int(q.get("since", ["0"])[0])
            with lock:
                evs = [e for e in events if e["id"] > since]
            return self.send(200, json.dumps(evs, ensure_ascii=False), "application/json")
        self.send(404, "not found\n")

    def do_POST(self):
        path = urlparse(self.path).path
        if path in ("/allow", "/deny"):
            return self.admin_post(path)
        if path != "/post":
            return self.send(404, "not found\n")
        if not self.authed():
            return
        d = self.body()
        if d is None:
            return
        try:
            lane, kind, text = str(d["lane"])[:32], str(d["kind"]), str(d["text"])[:MAX_TEXT]
        except (KeyError, TypeError):
            return self.send(400, "need json {lane, kind, text}\n")
        if kind in DIRECTED and self.headers.get("Authorization", "") != f"Bearer {ADMIN}":
            return self.send(403, "order/hold/release 는 관리자 토큰 전용\n")
        if kind in DIRECTED and not d.get("to"):
            return self.send(400, "order/hold/release need 'to' (lane or all)\n")
        if kind not in KINDS or not lane or not text:
            return self.send(400, f"kind must be one of {sorted(KINDS)}\n")
        with lock:
            e = {"id": len(events) + 1, "ts": int(time.time()), "lane": lane, "kind": kind, "text": text}
            if d.get("to"):
                e["to"] = str(d["to"])[:32]
            events.append(e)
            with open(STORE, "a", encoding="utf-8") as f:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")
        self.send(200, f"ok #{e['id']}\n")


if __name__ == "__main__":
    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    load()
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
