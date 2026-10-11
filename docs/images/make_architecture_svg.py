#!/usr/bin/env python3
"""Draw docs/images/architecture.svg: the whole system on one page (fabric -> k8s -> IaC -> telemetry).

   python3 docs/images/make_architecture_svg.py docs/images/architecture.svg

Hand-placed layout (Mermaid cannot lay this out on one page). Update it when the design changes."""
import html
import sys

W, H = 1600, 1040
out = []
C = {
    "git": ("#eef4ff", "#3b6fd8"), "iac": ("#f3eeff", "#7a4fd1"), "lab": ("#f7f9fb", "#5b6b7c"),
    "dc": ("#eefaf3", "#2f8f5b"), "wan": ("#fff6e8", "#c7781a"), "edge": ("#fdeff0", "#c0424e"),
    "k8s": ("#e8f4ff", "#1f6fb2"), "obs": ("#fff8e0", "#b38a00"), "node": ("#ffffff", "#8a97a6"),
}


def esc(t):
    return html.escape(t)


def box(x, y, w, h, kind, title=None, lines=(), r=8, title_size=15, size=12, bold_first=False, fill=None):
    f, s = C[kind]
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill or f}" stroke="{s}" stroke-width="1.5"/>')
    ty = y + 20
    if title:
        out.append(f'<text x="{x + 10}" y="{ty}" font-size="{title_size}" font-weight="700" fill="{s}">{esc(title)}</text>')
        ty += 18
    for i, line in enumerate(lines):
        weight = ' font-weight="600"' if bold_first and i == 0 else ""
        out.append(f'<text x="{x + w / 2}" y="{ty + i * (size + 3)}" font-size="{size}" text-anchor="middle"{weight} fill="#1f2933">{esc(line)}</text>')


def node(x, y, w, h, lines, kind="node", size=12):
    f, s = C[kind]
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{f if kind != "node" else "#ffffff"}" stroke="{s}" stroke-width="1.2"/>')
    top = y + h / 2 - (len(lines) - 1) * (size + 2) / 2 + size / 3
    for i, line in enumerate(lines):
        weight = ' font-weight="600"' if i == 0 else ""
        out.append(f'<text x="{x + w / 2}" y="{top + i * (size + 2)}" font-size="{size if i == 0 else size - 1}" text-anchor="middle"{weight} fill="#1f2933">{esc(line)}</text>')


def line(x1, y1, x2, y2, color="#5b6b7c", dash=False, arrow=True, width=1.6):
    d = ' stroke-dasharray="6 4"' if dash else ""
    m = ' marker-end="url(#arrow)"' if arrow else ""
    out.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}"{d}{m}/>')


def path(d, color="#5b6b7c", dash=False, arrow=True, width=1.6):
    da = ' stroke-dasharray="6 4"' if dash else ""
    m = ' marker-end="url(#arrow)"' if arrow else ""
    out.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}"{da}{m}/>')


def label(x, y, text, size=11, color="#3d4a57", anchor="middle", weight="400", bg=True):
    if bg:
        w = len(text) * size * 0.56 + 8
        bx = x - w / 2 if anchor == "middle" else (x - 4 if anchor == "start" else x - w + 4)
        out.append(f'<rect x="{bx}" y="{y - size}" width="{w}" height="{size + 5}" rx="3" fill="#ffffff" opacity="0.92"/>')
    out.append(f'<text x="{x}" y="{y}" font-size="{size}" text-anchor="{anchor}" font-weight="{weight}" fill="{color}">{esc(text)}</text>')


# ---------------------------------------------------------------- header
out.append(f'<text x="24" y="38" font-size="24" font-weight="700" fill="#1f2933">netops-lab: from the repository to the network, the cluster and the agent</text>')
out.append(f'<text x="24" y="60" font-size="13" fill="#52606d">Dual-DC Arista EVPN-VXLAN multi-site fabric · k3s Kubernetes across both DCs · infrastructure as code · GitOps · telemetry to Elastic</text>')

# ---------------------------------------------------------------- ① Git
box(20, 85, 250, 560, "git", "① Git: source of truth")
node(36, 130, 218, 92, ["network/", "switches, VLANs / VRFs, routing", "policy (route-maps), WAN,", "servers, traffic generators"], "git")
node(36, 236, 218, 92, ["kubernetes/", "cluster.yml: nodes, /31s, AS,", "pod CIDRs, VIP pools", "terraform/: Cilium, BGP, apps"], "git")
node(36, 342, 218, 62, ["docs/", "architecture + role guides"], "git")
node(36, 430, 218, 112, ["GitHub Actions", "PR → build check + plan comment", "merge → apply, Terraform,", "verify, change event", "every 15 min → drift issue"], "git")
node(36, 556, 218, 72, ["CODEOWNERS", "a network engineer approves", "every change (also the agent's)"], "git")

# ---------------------------------------------------------------- ② IaC
box(300, 85, 250, 560, "iac", "② Infrastructure as code")
node(316, 130, 218, 86, ["render.py + Arista AVD", "make build (offline)", "EOS configs, FRR configs,", "containerlab topology, docs"], "iac")
node(316, 236, 218, 76, ["containerlab", "containers + veth cabling", "make up / redeploy / down"], "iac")
node(316, 330, 218, 76, ["Ansible", "make plan / make apply", "EOS config replace, FRR reload"], "iac")
node(316, 424, 218, 92, ["Terraform", "make k8s: pod CIDRs, Cilium", "(Helm), BGP sessions, VIP", "pools, apps, image loading"], "iac")
node(316, 534, 218, 92, ["verify.sh", "make verify: OSPF, BGP, EVPN", "isolation, pings, VRF handoff,", "k8s routes, VIPs, telemetry"], "iac")

line(270, 176, 314, 176, C["git"][1])
line(270, 282, 314, 182, C["git"][1])
line(270, 282, 314, 470, C["git"][1])

# ---------------------------------------------------------------- ③ Lab
LX, LY, LW, LH = 580, 85, 760, 900
box(LX, LY, LW, LH, "lab", "③ Lab host 192.168.20.56 · containerlab (one Linux host, every box a container)")

# edge sites
box(600, 125, 720, 92, "edge", "WAN-side sites (VRF PROD)", title_size=13)
node(616, 152, 190, 52, ["attacker1  203.0.113.66", "nping / iperf3, 20 Mbit/s cap"], "edge")
node(826, 152, 190, 52, ["wan-k8s-cp3  10.30.40.1", "k3s control plane, tie-breaker"], "k8s")
node(1036, 152, 190, 52, ["inet-k6  198.51.100.11", "k6: 10 req/s → 192.0.2.10"], "edge")
label(1290, 170, "netem:", 11, anchor="end", bg=False)
label(1290, 184, "delay, loss", 11, anchor="end", bg=False)

# WAN
box(600, 235, 720, 92, "wan", "WAN / DCI (FRR)", title_size=13)
node(700, 262, 200, 52, ["wan1  AS 64901", "eth1-4 → the four BGWs"], "wan")
node(1020, 262, 200, 52, ["wan2  AS 64902", "eth1-4 → the four BGWs"], "wan")
line(900, 288, 1020, 288, C["wan"][1], arrow=False, width=3)
label(960, 282, "eth5", 10, bg=False)
line(711, 204, 770, 262, C["edge"][1], arrow=False)
line(921, 204, 840, 262, C["k8s"][1], arrow=False)
line(1131, 204, 1120, 262, C["edge"][1], arrow=False)
label(740, 236, "eth7", 10, bg=False)
label(892, 236, "eth6", 10, bg=False)
label(1140, 236, "eth7", 10, bg=False)

# DCs
def dc(x, name, asn, leaves, servers, k8s, k8s_note, pods, vtep):
    box(x, 355, 350, 590, "dc", f"{name} · AS {asn}", title_size=14)
    node(x + 25, 390, 140, 44, [f"{name.lower()}-bgw1", "EVPN gateway"], "dc")
    node(x + 185, 390, 140, 44, [f"{name.lower()}-bgw2", "EVPN gateway"], "dc")
    node(x + 25, 470, 140, 44, [f"{name.lower()}-spine1", "route reflector"], "dc")
    node(x + 185, 470, 140, 44, [f"{name.lower()}-spine2", "route reflector"], "dc")
    for a in (95, 255):
        for b in (95, 255):
            line(x + a, 434, x + b, 470, C["dc"][1], arrow=False, width=1)
    n = len(leaves)
    lw = (300 - (n - 1) * 10) / n
    xs = [x + 25 + i * (lw + 10) for i in range(n)]
    for i, lf in enumerate(leaves):
        node(xs[i], 550, lw, 44, [lf[0], lf[1]], "dc", size=11)
        for a in (95, 255):
            line(x + a, 514, xs[i] + lw / 2, 550, C["dc"][1], arrow=False, width=1)
    label(x + 175, 538, f"OSPF area 0 underlay · iBGP EVPN overlay · VTEPs {vtep}", 10, bg=True)
    node(x + 25, 625, 300, 58, ["servers (VLANs, anycast gateway)", servers], "node", size=11)
    box(x + 15, 700, 320, 235, "k8s", "Kubernetes nodes (k3s)", title_size=12)
    for i, (nm, ip, leaf) in enumerate(k8s):
        node(x + 30, 735 + i * 50, 290, 42, [f"{nm}  {ip}", f"routed /31 to {leaf} Ethernet7 · eBGP"], "k8s", size=11)
    out.append(f'<text x="{x + 175}" y="{735 + len(k8s) * 50 + 18}" font-size="11" text-anchor="middle" fill="#1f2933">{esc(pods)}</text>')
    out.append(f'<text x="{x + 175}" y="{735 + len(k8s) * 50 + 34}" font-size="11" text-anchor="middle" fill="#1f2933">{esc(k8s_note)}</text>')


dc(600, "DC1", 65100,
   [("leaf1", "web"), ("leaf2", "web, str."), ("leaf3", "app"), ("leaf4", "app")],
   "web1-2 (VLAN 110), app1-2 (120), stretch1 (150)",
   [("dc1-k8s-cp1", "10.10.40.1", "leaf1"), ("dc1-k8s-wk1", "10.10.40.3", "leaf3"), ("dc1-k8s-wk2", "10.10.40.5", "leaf4")],
   "web pods ×2 · iperf3-dc1", "pods 10.11.x.0/24 announced to the leaves", "10.1.1.x")
dc(970, "DC2", 65200,
   [("leaf1", "db"), ("leaf2", "db, stretch")],
   "db1-2 (VLAN 130, DB reserved), stretch1 (150)",
   [("dc2-k8s-cp2", "10.20.40.1", "leaf1"), ("dc2-k8s-wk3", "10.20.40.3", "leaf2")],
   "web pods ×2 · iperf3-dc2", "pods 10.21.x.0/24 announced to the leaves", "10.2.1.x")

# WAN <-> BGWs
for bx in (695, 855, 1065, 1225):
    line(800, 314, bx, 390, C["wan"][1], arrow=False, width=1)
    line(1120, 314, bx, 390, C["wan"][1], arrow=False, width=1)
label(960, 344, "underlay eBGP (BGW loopbacks) + VRF PROD on .100 sub-interfaces (VRF-lite)", 10)
path("M 925 412 C 945 440, 1000 440, 1020 412", C["dc"][1], dash=True, arrow=False, width=2)
label(972, 448, "EVPN multi-site", 10, weight="600")
label(972, 461, "(eBGP EVPN, I-ES)", 10)

# VIP banner
out.append('<rect x="600" y="958" width="720" height="22" rx="5" fill="#1f6fb2" opacity="0.10"/>')
out.append('<text x="960" y="973" font-size="12" text-anchor="middle" font-weight="600" fill="#1f6fb2">'
           'web app VIPs: 192.0.2.10 public (to the WAN) · 10.99.0.10 internal · announced only by nodes with a ready pod</text>')

# IaC -> lab
line(534, 176, 598, 176, C["iac"][1])
label(566, 168, "configs", 10, bg=False)
line(534, 274, 598, 274, C["iac"][1])
line(534, 368, 598, 450, C["iac"][1])
label(560, 398, "apply", 10, bg=False)
line(534, 470, 612, 760, C["iac"][1])
label(585, 640, "make k8s", 10, bg=True)

# ---------------------------------------------------------------- ④ Observability
box(1370, 85, 210, 900, "obs", "④ Observability")
node(1385, 130, 180, 70, ["gnmic", "gNMI subscribe to all", "14 switches (:6030)"], "obs")
node(1385, 230, 180, 84, ["OTel Collector", "OTLP in (4317 / 4318)", "data contract: device, lab", "disk queue to Elastic"], "obs")
node(1385, 344, 180, 70, ["Elastic Cloud (AWS)", "metrics · logs ·", "change events"], "obs")
node(1385, 444, 180, 84, ["Auto-SRE agent", "reads telemetry +", "change log, finds the", "cause at 3 AM"], "obs")
node(1385, 558, 180, 84, ["⑤ pull request", "edits network/ or", "kubernetes/ with the fix", "→ back to ①"], "obs")
line(1475, 200, 1475, 230, C["obs"][1])
line(1475, 314, 1475, 344, C["obs"][1])
line(1475, 414, 1475, 444, C["obs"][1])
line(1475, 528, 1475, 558, C["obs"][1])
line(1340, 430, 1383, 165, C["dc"][1], dash=True)
label(1352, 300, "gNMI", 10, bg=True)
line(1340, 800, 1383, 272, C["k8s"][1], dash=True)
label(1360, 700, "OTLP", 10, bg=True)
path("M 1475 642 L 1475 1010 L 145 1010 L 145 645", C["obs"][1], dash=True, width=2)
label(800, 1014, "the agent's fix is a pull request: CI plans it, an engineer approves, the merge deploys it", 12, weight="600")

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
       f'font-family="-apple-system, Segoe UI, Helvetica, Arial, sans-serif">'
       '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
       '<path d="M 0 0 L 10 5 L 0 10 z" fill="#5b6b7c"/></marker></defs>'
       f'<rect width="{W}" height="{H}" fill="#ffffff"/>' + "".join(out) + "</svg>\n")
open(sys.argv[1], "w").write(svg)
print("wrote", sys.argv[1], len(svg), "bytes")
