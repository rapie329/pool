#!/usr/bin/env bash
# ============================================================
# setup.sh — runs INSIDE the GitHub Actions runner.
#   installs a tool "profile" onto the ubuntu-latest container.
#   usage: bash setup.sh <profile>
#   profiles: base net rev web build android forensic
# ============================================================
set -uo pipefail

PROFILE="${1:-base}"
SUDO=sudo
LOG() { printf '\033[36m[setup]\033[0m %s\n' "$*"; }
DIE() { printf '\033[31m[setup:fail]\033[0m %s\n' "$*" >&2; exit 1; }

LOG "profile=$PROFILE  host=$(hostname)  user=$(whoami)"
$SUDO apt-get update -qq 2>&1 | tail -1

A() { $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" >/dev/null 2>&1 || DIE "apt failed: $*"; }

# ---------- always ----------
have_base() {
  A ca-certificates curl wget git jq unzip zip xz-utils tar \
    build-essential pkg-config python3 python3-pip python3-venv \
    tmux htop procps net-tools iproute2 dnsutils iputils-ping \
    vim nano file binutils patch sudo locales rsync
  $SUDO locale-gen en_US.UTF-8 >/dev/null 2>&1
  $SUDO pip3 install --quiet --upgrade pip setuptools wheel 2>/dev/null
  LOG "base ok — $(python3 -V) | $(gcc --version|head -1)"
}

# ---------- net ----------
have_net() {
  A nmap netcat-openbsd netcat-traditional socat traceroute mtr whois \
    tcpdump wireshark-common iptables nftables ethtool arp-scan
  # better standalones
  LOG "net ok — $(nmap --version 2>/dev/null|head -1)"
}

# ---------- rev ----------
have_rev() {
  A radare2 gdb gdb-multiarch binutils-multiarch default-jdk-headless patchelf
  $SUDO pip3 install --quiet capstone keystone-engine unicorn lief 2>/dev/null || LOG "pip extras partial"
  $SUDO curl -fsSL https://github.com/extremecoders-re/ghidra/gh-pages/scripts/downloadLatest.sh 2>/dev/null \
    | bash >/dev/null 2>&1 && LOG "ghidra ok" || LOG "ghidra skipped (big download)"
  LOG "rev ok — r2 $(r2 -v 2>/dev/null|head -1)"
}

# ---------- web ----------
have_web() {
  A sqlmap nikto
  go_bin=/usr/local/go/bin
  [ -d "$go_bin" ] || { $SUDO curl -fsSL https://go.dev/dl/go1.23.4.linux-amd64.tar.gz | $SUDO tar -C /usr/local -xz; }
  export PATH=$PATH:$go_bin
  for t in "github.com/projectdiscovery/httpx/cmd/httpx@latest" \
           "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest" \
           "github.com/ffuf/ffuf/v2@latest"; do
    $go_bin/go install "$t" 2>/dev/null && LOG "go install: ${t##*/} ok" || LOG "go install: ${t##*/} FAILED"
  done
  LOG "web ok"
}

# ---------- build ----------
have_build() {
  A docker.io docker-compose-v2 qemu-user-static
  $SUDO systemctl enable --now docker >/dev/null 2>&1
  for t in aarch64-linux-gnu arm-linux-gnueabihf i686-linux-gnu x86_64-linux-musl; do
    $SUDO apt-get install -y -qq "${t}-gcc" >/dev/null 2>&1 && LOG "cross: $t ok" || LOG "cross: $t skip"
  done
  LOG "build ok — $(docker --version 2>/dev/null || echo 'docker: no systemd, use dockerd &')"
}

# ---------- android ----------
have_android() {
  A openjdk-17-jdk-headless apktool aapt apksigner zipalign android-tools-adb dexpatcher
  mkdir -p "$HOME/tools"
  [[ -x $HOME/tools/jadx ]] || {
    $SUDO curl -fsSL -o /tmp/jadx.zip \
      "https://github.com/skylot/jadx/releases/download/v1.5.1/jadx-1.5.1.zip" 2>/dev/null \
      && $SUDO unzip -qo /tmp/jadx.zip -d $HOME/tools \
      && $SUDO ln -sf $HOME/tools/jadx-1.5.1/bin/jadx /usr/local/bin/jadx \
      && LOG "jadx ok" || LOG "jadx FAILED"
  }
  $SUDO pip3 install --quiet androguard frida-tools 2>/dev/null || true
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
  LOG "android ok — java $(java -version 2>&1|head -1|grep -oE '[0-9]+')"
}

# ---------- forensic ----------
have_forensic() {
  A sleuthkit testdisk foremost bulk-extractor volatility3 yara
  $SUDO pip3 install --quiet pytsk3 python-magic 2>/dev/null || true
  LOG "forensic ok — $(tsk_recover -V 2>&1|head -1)"
}

case "$PROFILE" in
  base)     have_base ;;
  net)      have_base; have_net ;;
  rev)      have_base; have_rev ;;
  web)      have_base; have_web ;;
  build)    have_base; have_build ;;
  android)  have_base; have_android ;;
  forensic) have_base; have_forensic ;;
  all)      have_base; have_net; have_rev; have_web; have_android; have_forensic ;;
  *)        DIE "unknown profile '$PROFILE' (base|net|rev|web|build|android|forensic|all)" ;;
esac

LOG "profile '$PROFILE' complete"