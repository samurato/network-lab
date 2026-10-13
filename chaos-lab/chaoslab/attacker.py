"""The attacker side of a route hijack: attacker1 claims the hijacked address and answers with a fake page,
so hijacked users get a 200 with the wrong content (interception, not just an outage)."""
from chaoslab import config, guard, state

SERVER = '''# chaoslab-fake-web
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"%(marker)s: this response came from attacker1, not the web app\\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
http.server.ThreadingHTTPServer(("%(ip)s", 80), H).serve_forever()
'''


def fake_web(ip: str, node: str = "attacker1", marker: str = "HIJACKED", **_) -> str:
    """Chaos Toolkit action: put `ip` on attacker1's loopback and serve a fake page on :80."""
    guard.check_node(node)
    guard.check_prefix(ip)
    ctr = config.container(node)
    what = f"{node}: fake web server on {ip}:80"
    state.register({"kind": "cmd", "argv": [
        "docker", "exec", ctr, "sh", "-c",
        f"pkill -f 'chaoslab[-]fake-web'; ip address del {ip}/32 dev lo; true"]}, what)   # [-]: not this sh
    config.sh(["docker", "exec", ctr, "ip", "address", "add", f"{ip}/32", "dev", "lo"])
    config.sh(["docker", "exec", "-d", ctr, "python3", "-c", SERVER % {"ip": ip, "marker": marker}])
    return what
