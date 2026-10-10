#!/usr/bin/env bash
# Bootstrap the containerlab host (192.168.20.56) for netops-lab.
# Run as your normal user; it prompts for sudo once.  Re-runnable.
#   bash ~/hackathon/netops-lab/containerlab/bootstrap.sh            # install everything
#   GROW_DISK=1 bash ~/hackathon/netops-lab/containerlab/bootstrap.sh # also grow root LV to the full 300G disk
#
# Storage layout:
#   ~/hackathon (SMB share)  -> repo, cEOS/vrnetlab image tarballs, backups.
#   local disk               -> docker data, python venv, containerlab lab dirs.
#   (CIFS mount has no symlinks/POSIX owners: venvs, docker overlay2 and SR Linux
#    bind-mounted config dirs break there.)
set -euo pipefail

HACK="$HOME/hackathon"
VENV="$HOME/.venvs/netops"
LABDIR_BASE="$HOME/clab-runs"

SRL_VER=26.7.2
FRR_VER=10.7.1
GNMIC_VER=0.49.0
OTELCOL_VER=0.162.0
GOFLOW2_VER=v2.2.7

step() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

step "0. Folders"
mkdir -p "$HACK"/{netops-lab,images,backups} "$LABDIR_BASE" "$HOME/.venvs"

sudo -v   # ask for the password once up front

if [[ "${GROW_DISK:-0}" == 1 ]]; then
  step "0b. Grow root LV into free VG space"
  sudo vgs
  sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv || echo "lvextend: nothing to grow?"
  df -h /
fi

step "1. OS packages"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3-venv python3-pip pipx unzip curl gnupg lsb-release ca-certificates \
  git make jq yq sshpass iproute2 ethtool bridge-utils \
  iperf3 hping3 tcpdump tshark mtr-tiny traceroute nmap

step "2. Terraform + GitHub CLI (vendor apt repos)"
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo tee /usr/share/keyrings/githubcli.gpg >/dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y terraform gh

step "3. AWS CLI v2"
if ! command -v aws >/dev/null; then
  tmp=$(mktemp -d)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmp/awscli.zip"
  unzip -q "$tmp/awscli.zip" -d "$tmp"
  sudo "$tmp/aws/install" --update
  rm -rf "$tmp"
fi

step "4. gnmic CLI ($GNMIC_VER)"
sudo bash -c "$(curl -sL https://get-gnmic.openconfig.net)" -- -v "$GNMIC_VER"

step "5. Host tuning for big labs"
sudo tee /etc/sysctl.d/90-clab.conf >/dev/null <<'SYSCTL'
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches   = 1048576
net.ipv4.ip_forward           = 1
net.ipv6.conf.all.forwarding  = 1
net.core.rmem_max             = 33554432
net.core.wmem_max             = 33554432
vm.max_map_count              = 262144
SYSCTL
sudo sysctl --system >/dev/null
printf 'vxlan\nip6_tables\nsch_netem\nsch_tbf\n' | sudo tee /etc/modules-load.d/clab.conf >/dev/null
sudo modprobe -a vxlan ip6_tables sch_netem sch_tbf

step "6. Python venv (local disk): ansible + network libs"
[[ -d "$VENV" ]] || python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip wheel
"$VENV/bin/pip" install -q \
  ansible-core pyavd jinja2 pyyaml netaddr jmespath requests \
  pygnmi pybatfish elasticsearch boto3 \
  opentelemetry-sdk opentelemetry-exporter-otlp
"$VENV/bin/ansible-galaxy" collection install -U \
  arista.avd arista.eos ansible.netcommon ansible.utils community.general community.docker
"$VENV/bin/pip" install -q -r "$HOME/.ansible/collections/ansible_collections/arista/avd/requirements.txt"

step "7. Shell env"
grep -q 'netops-lab env' ~/.bashrc || cat >> ~/.bashrc <<RC

# >>> netops-lab env
export PATH="$VENV/bin:\$PATH"
export CLAB_LABDIR_BASE="$LABDIR_BASE"   # keep clab-* runtime dirs off the SMB share
export HACK="$HACK"
# <<< netops-lab env
RC

step "8. Container images"
images=(
  "ghcr.io/nokia/srlinux:$SRL_VER"
  "quay.io/frrouting/frr:$FRR_VER"
  "ghcr.io/openconfig/gnmic:$GNMIC_VER"
  "otel/opentelemetry-collector-contrib:$OTELCOL_VER"
  "netsampler/goflow2:$GOFLOW2_VER"
  "ghcr.io/srl-labs/network-multitool:latest"
  "grafana/k6:latest"
  "batfish/allinone:latest"
)
for i in "${images[@]}"; do docker pull -q "$i"; done

# Arista cEOS is login-gated: download cEOS64-lab-<ver>.tar.xz from arista.com into
# ~/hackathon/images/ and it will be imported here.
for f in "$HACK"/images/cEOS64-lab-*.tar*; do
  [[ -e "$f" ]] || { echo "cEOS: no tarball in $HACK/images yet (skipping)"; break; }
  ver=$(basename "$f" | sed -E 's/cEOS64-lab-(.*)\.tar.*/\1/')
  docker image inspect "ceos:$ver" >/dev/null 2>&1 || docker import "$f" "ceos:$ver"
done

step "9. Versions"
containerlab version | grep -E 'version:'
docker --version; terraform version | head -1; gh --version | head -1; aws --version
gnmic version | grep -E 'version'
"$VENV/bin/ansible" --version | head -1
docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}' | sort
df -h / "$HACK"
echo -e "\nDone. Run: source ~/.bashrc"
