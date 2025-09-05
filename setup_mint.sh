#!/usr/bin/env bash
set -euo pipefail

# =========================
# Mint-Optimized Bootstrap
# =========================

INSTALL_USER="${SUDO_USER:-${USER}}"
LOG="/var/log/bootstrap_setup_mint.log"

msg()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "root 권한이 필요합니다. sudo로 다시 실행하세요."
    exit 1
  fi
}

ensure_log() { mkdir -p "$(dirname "$LOG")"; touch "$LOG"; }

apt_update_once() {
  export DEBIAN_FRONTEND=noninteractive
  msg "apt 업데이트"
  apt-get update -y >>"$LOG" 2>&1
}

apt_install() {
  local pkgs=("$@")
  msg "설치: ${pkgs[*]}"
  apt-get install -y --no-install-recommends "${pkgs[@]}" >>"$LOG" 2>&1
}

ensure_user_in_group() {
  local user="$1" grp="$2"
  if id -nG "$user" | tr ' ' '\n' | grep -qx "$grp"; then
    msg "$user 는 이미 $grp 그룹입니다."
  else
    msg "$user 를 $grp 그룹에 추가합니다."
    usermod -aG "$grp" "$user"
    warn "그룹 적용을 위해 $user 재로그인 필요."
  fi
}

# Ubuntu codename 추출 (Mint 호환)
get_ubuntu_codename() {
  local code=""
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    code="${UBUNTU_CODENAME:-}"
    if [ -z "$code" ]; then
      code="${VERSION_CODENAME:-}"
    fi
  fi
  if [ -z "$code" ] && [ -r /etc/upstream-release/lsb-release ]; then
    . /etc/upstream-release/lsb-release
    code="${DISTRIB_CODENAME:-$code}"
  fi
  echo "$code"
}

# -------------------------
# 실행 시작
# -------------------------
require_root
ensure_log
msg "로그 파일: $LOG"
apt_update_once

# 0) 필수 기초 툴
apt_install ca-certificates gnupg lsb-release apt-transport-https software-properties-common

# 1) 기본 유틸/네트워크/보안/파이썬
apt_install \
  git curl wget vim htop \
  net-tools iproute2 traceroute nmap \
  ufw \
  python3 python3-pip python3-venv

# 1-1) SSH 서버 설치 및 활성화
if ! need_cmd sshd; then
  msg "OpenSSH 서버 설치"
  apt_install openssh-server
  systemctl enable --now ssh
else
  msg "OpenSSH 서버 이미 설치됨"
fi

# 2) Docker (공식 리포지토리 + Compose v2 플러그인)
if ! need_cmd docker; then
  msg "Docker 공식 GPG 키/리포 설정 (Mint→Ubuntu codename 매핑)"
  install -m 0755 -d /etc/apt/keyrings

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  UB_CODE="$(get_ubuntu_codename)"
  if [ -z "$UB_CODE" ]; then
    warn "Ubuntu codename을 찾지 못했습니다. 기본값 'jammy' 사용 시도."
    UB_CODE="jammy"
  fi
  ARCH="$(dpkg --print-architecture)"

  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UB_CODE} stable" \
    | tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt_update_once
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
else
  msg "Docker 이미 설치됨"
fi

ensure_user_in_group "$INSTALL_USER" "docker"

# 3) kubectl (pkgs.k8s.io v1.30 stable)
if ! need_cmd kubectl; then
  msg "kubectl 리포지토리 설정 (v1.30 stable)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  cat >/etc/apt/sources.list.d/kubernetes.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /
EOF

  apt_update_once
  apt_install kubectl
else
  msg "kubectl 이미 설치됨"
fi

# 4) Multipass (Mint에서는 apt 우선)
if ! need_cmd multipass; then
  msg "Multipass 설치 (apt)"
  apt_install multipass || {
    err "apt 기반 multipass 설치 실패. snap 사용을 고려하세요: 'sudo apt install snapd && sudo snap install multipass --classic'"
    exit 1
  }
else
  msg "multipass 이미 설치됨"
fi

# 5) UFW 기본 정책
if ufw status | grep -qi inactive; then
  msg "UFW 기본 정책(deny incoming / allow outgoing / OpenSSH 허용)"
  ufw default deny incoming >>"$LOG" 2>&1 || true
  ufw default allow outgoing >>"$LOG" 2>&1 || true
  ufw allow OpenSSH >>"$LOG" 2>&1 || ufw allow 22/tcp >>"$LOG" 2>&1 || true
  echo "y" | ufw enable >>"$LOG" 2>&1 || true
else
  msg "UFW 이미 활성화됨"
fi

# 6) 버전 출력
echo
msg "설치 버전 확인:"
for c in git curl wget vim htop ifconfig ip route traceroute nmap python3 pip3 docker kubectl multipass sshd; do
  if need_cmd "$c"; then
    printf "  - %-10s : " "$c"
    case "$c" in
      ifconfig|ip|route) "$c" --version 2>&1 | head -n1 || true ;;
      docker) docker --version || true ;;
      kubectl) kubectl version --client --output=yaml | head -n 5 || true ;;
      multipass) multipass version || true ;;
      sshd) ssh -V 2>&1 || true ;;
      *) "$c" --version 2>&1 | head -n1 || true ;;
    esac
  fi
done

echo
warn "docker 그룹 적용을 위해 '${INSTALL_USER}' 사용자로 재로그인(또는 재부팅)하세요."
msg  "도커 sudo 재로그인 없이 적용하려면 >> newgrp docker"
msg  "Multipass 사용 전 BIOS/UEFI에서 VT-x/AMD-V 활성화 필요."
msg  "SSH 서버는 기본 포트(22)로 활성화되어 있습니다."
msg  "완료!"
