#!/usr/bin/env bash
set -euo pipefail

# =========================
# Mint-Optimized Bootstrap (Snap Multipass only)
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

get_ubuntu_codename() {
  local code=""
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    code="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  fi
  if [ -z "$code" ] && [ -r /etc/upstream-release/lsb-release ]; then
    . /etc/upstream-release/lsb-release
    code="${DISTRIB_CODENAME:-$code}"
  fi
  echo "$code"
}

check_kvm() {
  msg "KVM 가상화 지원/디바이스 점검"
  if ! grep -Eq 'vmx|svm' /proc/cpuinfo; then
    warn "CPU 가상화 비트(VT-x/AMD-V) 미확인 → BIOS에서 활성화 필요할 수 있음."
  fi
  if [ ! -e /dev/kvm ]; then
    warn "/dev/kvm 없음 → qemu-kvm/libvirt 설치 및 재로그인 필요할 수 있음."
  fi
}

install_base_tools() {
  apt_install ca-certificates gnupg lsb-release apt-transport-https software-properties-common \
              git curl wget vim htop net-tools iproute2 traceroute nmap ufw \
              python3 python3-pip python3-venv
}

install_openssh() {
  if ! need_cmd sshd && ! need_cmd ssh; then
    msg "OpenSSH 서버 설치"
    apt_install openssh-server
    systemctl enable --now ssh
  else
    msg "OpenSSH 서버 이미 설치/활성화됨"
  fi
}

install_docker() {
  if need_cmd docker; then
    msg "Docker 이미 설치됨"
    return
  fi
  msg "Docker 공식 리포지토리 설정"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  local UB_CODE ARCH
  UB_CODE="$(get_ubuntu_codename)"; [ -z "$UB_CODE" ] && UB_CODE="jammy"
  ARCH="$(dpkg --print-architecture)"
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UB_CODE} stable" \
    | tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt_update_once
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker

  ensure_user_in_group "$INSTALL_USER" "docker"
}

install_kubectl() {
  if need_cmd kubectl; then
    msg "kubectl 이미 설치됨"
    return
  fi
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
}

install_multipass_snap_only() {
  # 혼용 방지: apt판 제거
  if dpkg -l | grep -q '^ii\s\+multipass\s'; then
    warn "apt판 multipass 감지 → 제거"
    apt-get purge -y multipass >>"$LOG" 2>&1 || true
  fi

  # snapd 설치
  if ! need_cmd snap; then
    msg "snapd 설치"
    apt_install snapd
  fi

  # snap multipass 설치
  if ! snap list 2>/dev/null | grep -q '^multipass\s'; then
    msg "Multipass(snap) 설치"
    snap install multipass --classic >>"$LOG" 2>&1
  else
    msg "Multipass(snap) 이미 설치됨"
  fi

  # 드라이버 확인/설정
  if ! multipass get local.driver >/dev/null 2>&1; then
    msg "Multipass 드라이버 qemu 설정"
    multipass set local.driver=qemu
  fi

  # 데몬 확인
  systemctl is-active --quiet snap.multipass.multipassd || systemctl start snap.multipass.multipassd
  systemctl enable snap.multipass.multipassd >/dev/null 2>&1 || true
}

enable_ufw_after_multipass() {
  # Multipass 확인(간단 ping)
  multipass version >>"$LOG" 2>&1 || true
  if ufw status | grep -qi inactive; then
    msg "UFW 기본 정책 설정 후 활성화 (deny incoming / allow outgoing / OpenSSH 허용)"
    ufw default deny incoming >>"$LOG" 2>&1 || true
    ufw default allow outgoing >>"$LOG" 2>&1 || true
    ufw allow OpenSSH >>"$LOG" 2>&1 || ufw allow 22/tcp >>"$LOG" 2>&1 || true
    echo "y" | ufw enable >>"$LOG" 2>&1 || true
  else
    msg "UFW 이미 활성화됨"
  fi
}

print_versions() {
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
}

# (선택) 3노드 Multipass 클러스터 생성 함수
create_three_vms() {
  local img="jammy"  # Ubuntu 22.04 LTS
  msg "3노드 VM 생성 (1 master, 2 workers) - CPU=1, RAM=2G, Disk=20G"
  multipass launch "$img" -n k8s-master -c 1 -m 2G -d 20G
  multipass launch "$img" -n k8s-node1  -c 1 -m 2G -d 20G
  multipass launch "$img" -n k8s-node2  -c 1 -m 2G -d 20G

  msg "VM 목록"
  multipass list
  msg "간단 정보"
  multipass info k8s-master || true
  multipass info k8s-node1  || true
  multipass info k8s-node2  || true
}

# -------------------------
# 실행 시작
# -------------------------
require_root
ensure_log
msg "로그 파일: $LOG"

apt_update_once
install_base_tools
install_openssh
install_docker
install_kubectl
check_kvm
install_multipass_snap_only

# UFW는 Multipass 확인 뒤 켭니다
enable_ufw_after_multipass

print_versions

echo
warn "docker 그룹 적용을 위해 '${INSTALL_USER}' 사용자로 재로그인(또는 재부팅)하세요."
msg  "도커 sudo 없이 즉시 적용하려면:  newgrp docker"
msg  "Multipass 사용 전, BIOS/UEFI의 VT-x/AMD-V 활성화 여부를 확인하세요."
msg  "SSH 서버는 기본 포트(22)로 활성화되어 있습니다."
msg  "필요 시 다음 함수를 수동 실행하여 3노드 VM을 올리세요:  create_three_vms"
