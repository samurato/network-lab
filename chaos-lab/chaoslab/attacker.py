"""The attacker side of a route hijack: attacker1 claims the hijacked address and answers with a fake page,
so hijacked users get a 200 with the wrong content (interception, not just an outage)."""
import base64

from chaoslab import config, guard, state

# The fake bank, served by attacker1: the real site's evil twin, so a hijack is obvious on screen.
# Every response, including /health, contains the marker word (probes.py checks for it). Base64 keeps
# the page out of the python -c quoting.
PAGE = r'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Fox Den Savings &amp; Loan</title>
<style>
:root{--bg:#1a0b05;--ink:#fff3e6;--fox:#ff6b1a;--mute:#c9a58c}
*{box-sizing:border-box}html{background:var(--bg)}body{margin:0;min-height:100vh;background:radial-gradient(circle at 50% 0,#4a1a06,var(--bg) 70%) fixed;color:var(--ink);font:16px/1.5 system-ui,sans-serif;text-align:center;overflow-x:hidden}
.banner{background:repeating-linear-gradient(45deg,#ffcc00 0 18px,#111 18px 36px);color:#111;font-weight:900;letter-spacing:.2em;padding:6px;animation:flash 1s steps(2) infinite}
.banner span,.banner b{background:#ffcc00;padding:2px 10px}@keyframes flash{50%{filter:invert(1)}}
.fox{font-size:120px;line-height:1;margin:28px 0 0;display:inline-block;animation:bob 1.2s ease-in-out infinite}@keyframes bob{50%{transform:translateY(-12px) rotate(-6deg)}}
h1{font-size:clamp(28px,6vw,54px);margin:8px 16px 0;color:var(--fox);text-shadow:0 0 24px #ff6b1a88}
.laugh{font-size:clamp(22px,4vw,34px);font-weight:800;margin:6px 0 18px}
.laugh i{display:inline-block;font-style:normal;animation:ha .6s ease-in-out infinite}
.laugh i:nth-child(2){animation-delay:.1s}.laugh i:nth-child(3){animation-delay:.2s}.laugh i:nth-child(4){animation-delay:.3s}
@keyframes ha{50%{transform:translateY(-8px) scale(1.15)}}
.card{max-width:560px;margin:0 auto 18px;background:#ffffff10;border:2px dashed var(--fox);border-radius:14px;padding:16px 20px;text-align:left}
.card h2{margin:0 0 6px;color:var(--fox);font-size:18px}.card li{margin:4px 0}
.bal{font-size:44px;font-weight:900;color:#ff3b3b;margin:4px 0}
button{background:var(--fox);color:#1a0b05;border:0;border-radius:999px;padding:12px 26px;font-weight:800;font-size:16px;cursor:pointer}
#nope{min-height:24px;color:#ffcc00;font-weight:700;margin-top:8px}
.foot{color:var(--mute);font-size:13px;max-width:600px;margin:18px auto 28px;padding:0 16px}
.foot code{color:var(--ink)}
.feather{position:fixed;top:-40px;font-size:26px;animation:fall linear infinite;pointer-events:none}
@keyframes fall{to{transform:translateY(110vh) rotate(540deg)}}
</style></head><body>
<div class="banner"><span>HIJACKED</span> <b>&#9888; THIS BANK IS UNDER NEW MANAGEMENT &#9888;</b> <span>HIJACKED</span></div>
<div class="fox">&#129418;</div>
<h1>Nest Egg Savings &amp; Loan is now<br>FOX DEN SAVINGS &amp; LOAN</h1>
<div class="laugh"><i>HA</i> <i>HA</i> <i>HA</i> <i>HAAA!</i></div>
<div class="card"><h2>Your account (formerly yours)</h2>
<div class="bal">0 seeds</div>
<ul><li>&#129370; Nest eggs: <b>eaten</b></li><li>&#129713; Worm loans: <b>called in, with interest</b></li>
<li>&#128038; Barnaby the pigeon: <b>tied up in the vault</b> (he is fine, mostly)</li>
<li>&#128176; New interest rate: <b>-100% APY</b>, compounding hourly</li></ul></div>
<button onclick="document.getElementById('nope').textContent=['Nice try, birdie.','Withdrawals are closed. Forever.','The fox says no.','Have you tried flying south?'][Math.floor(Math.random()*4)]">Withdraw my seeds</button>
<div id="nope"></div>
<p class="foot">&#128373; This is a <b>chaos-lab drill</b>: a BGP route hijack. A WAN router announced
<code>192.0.2.10/32</code> as its own, so this answer came from <code>attacker1</code>, not the bank.
The real web app never saw your request, and its dashboards stay green. HIJACKED.</p>
<script>for(let i=0;i<14;i++){const f=document.createElement('div');f.className='feather';f.textContent=['\u{1FAB6}','\u{1F426}','\u{1FAB6}'][i%3];
f.style.left=Math.random()*100+'vw';f.style.animationDuration=(4+Math.random()*5)+'s';f.style.animationDelay=(Math.random()*5)+'s';document.body.appendChild(f)}</script>
</body></html>'''

SERVER = '''# chaoslab-fake-web
import base64, http.server
PAGE = base64.b64decode("%(page)s")
TEXT = b"%(marker)s: this response came from attacker1, not the web app\\n"
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        html = not (self.path.startswith("/health") or self.path.startswith("/api"))
        body = PAGE if html else TEXT
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8" if html else "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
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
    config.sh(["docker", "exec", "-d", ctr, "python3", "-c", SERVER % {"ip": ip, "marker": marker, "page": base64.b64encode(PAGE.replace("HIJACKED", marker).encode()).decode()}])
    return what
