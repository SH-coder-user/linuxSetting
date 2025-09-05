#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Multipass 3-node k3s Cluster
#   k3s1: server
#   k3s2: agent
#   k3s3: agent
# Resources: -c 1 -m 2G -d 20G
# Host OS: Linux Mint/Ubuntu (kubectl, multipass 존재 가정)
# ----------------------------

IMAGE="${IMAGE:-24.04}"
CPU="${CPU:-1}"
MEM="${MEM:-2G}"
DISK="${DISK:-20G}"
SERVER="k3s1"
AGENTS=("k3s2" "k3s3")
KUBECONFIG_OUT="${KUBECONFIG_OUT:-kubeconfig_k3s1.yaml}"

msg()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

ip_of() {
  # Multipass IPv4 추출 (NAT 네트워크)
  multipass info "$1" 2>/dev/null | awk '/IPv4/{print $2; exit}'
}

launch_vm() {
  local name="$1"
  if multipass list --format csv | awk -F, '{print $1}' | grep -qx "$name"; then
    msg "$name 이미 존재함. 상태 확인만 진행."
    multipass start "$name" >/dev/null || true
    return
  fi
  msg "Launching VM: $name  (c=${CPU}, m=${MEM}, d=${DISK}, image=${IMAGE})"
  multipass launch -n "$name" -c "$CPU" -m "$MEM" -d "$DISK" "$IMAGE"
}

wait_ssh() {
  local name="$1" tries=40
  msg "SSH 준비 대기: $name"
  for _ in $(seq 1 $tries); do
    if multipass exec "$name" -- true 2>/dev/null; then
      return 0
    fi
    sleep 3
  done
  err "SSH 준비 실패: $name"
  exit 1
}

install_k3s_server() {
  local name="$1"
  local ip
  ip="$(ip_of "$name")"
  if [ -z "$ip" ]; then
    err "서버 IP 조회 실패 ($name)"
    exit 1
  fi
  msg "k3s server 설치: $name ($ip)"
  multipass exec "$name" -- sh -c "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--write-kubeconfig-mode 644 --tls-san ${ip}' sh -"
}

get_k3s_token() {
  local name="$1"
  multipass exec "$name" -- sudo cat /var/lib/rancher/k3s/server/node-token
}

install_k3s_agent() {
  local name="$1" server_ip="$2" token="$3"
  msg "k3s agent 설치: $name -> server https://${server_ip}:6443"
  multipass exec "$name" -- sh -c "curl -sfL https://get.k3s.io | K3S_URL='https://${server_ip}:6443' K3S_TOKEN='${token}' sh -"
}

pull_kubeconfig() {
  local name="$1" out="$2" server_ip="$3"
  msg "kubeconfig 수집: ${out}"
  multipass exec "$name" -- sudo cat /etc/rancher/k3s/k3s.yaml > "${out}.tmp"
  # 127.0.0.1 -> server_ip로 교체
  sed -e "s/127.0.0.1/${server_ip}/g" "${out}.tmp" > "${out}"
  rm -f "${out}.tmp"
  msg "kubeconfig 저장됨: $(readlink -f "$out")"
}

status() {
  multipass list
  echo
  for n in "$SERVER" "${AGENTS[@]}"; do
    echo "[$n] IP: $(ip_of "$n" || true)"
  done
}

cmd_up() {
  need_cmd multipass || { err "multipass가 필요합니다."; exit 1; }

  # 1) VM 생성/부팅
  launch_vm "$SERVER"
  for n in "${AGENTS[@]}"; do launch_vm "$n"; done

  # 2) SSH 준비
  wait_ssh "$SERVER"
  for n in "${AGENTS[@]}"; do wait_ssh "$n"; done

  # 3) 서버 설치
  install_k3s_server "$SERVER"
  local server_ip token
  server_ip="$(ip_of "$SERVER")"
  token="$(get_k3s_token "$SERVER")"

  # 4) 에이전트 설치
  for n in "${AGENTS[@]}"; do install_k3s_agent "$n" "$server_ip" "$token"; done

  # 5) kubeconfig 내려받기
  pull_kubeconfig "$SERVER" "$KUBECONFIG_OUT" "$server_ip"

  # 6) 노드 상태 확인(선택)
  if need_cmd kubectl; then
    msg "클러스터 확인 (잠시 대기 후)"
    sleep 5
    KUBECONFIG="$KUBECONFIG_OUT" kubectl get nodes -o wide || true
  else
    warn "kubectl이 호스트에 없습니다. 설치 후 아래로 확인하세요:"
    echo "  export KUBECONFIG=\$PWD/$KUBECONFIG_OUT"
    echo "  kubectl get nodes -o wide"
  fi

  status
  msg "완료"
}

cmd_stop() {
  for n in "$SERVER" "${AGENTS[@]}"; do
    multipass stop "$n" 2>/dev/null || true
  done
  status
}

cmd_start() {
  for n in "$SERVER" "${AGENTS[@]}"; do
    multipass start "$n" 2>/dev/null || true
  done
  status
}

cmd_delete() {
  for n in "$SERVER" "${AGENTS[@]}"; do
    multipass delete "$n" 2>/dev/null || true
  done
  multipass purge 2>/dev/null || true
  status
}

case "${1:-}" in
  up)     cmd_up ;;
  stop)   cmd_stop ;;
  start)  cmd_start ;;
  delete) cmd_delete ;;
  status) status ;;
  *)
    echo "Usage: $0 {up|stop|start|delete|status}"
    echo "Env overrides: IMAGE(=24.04) CPU(=1) MEM(=2G) DISK(=20G) KUBECONFIG_OUT(=kubeconfig_k3s1.yaml)"
    exit 1
    ;;
esac

