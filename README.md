# 포맷 후 리눅스 재설치 USB 사용시
> 1. 바이오스셋업 진입 F1, F2, Del 등
> 2. BOOT 순서 USB로 맨 첫번째 두기
> 3. 중요!!!바이오스 셋업에서 반드시 SecureBoot 부분을 Disabled로 바꾼뒤 재시작하기!(대부분 이거안해서 리눅스 부팅시 오류뜨고 튕김)


# Multipass 설치시
> 1. snapd 사용하도록 설정해야함. 민트리눅스의 경우 기본적으로 snap명령어사용안되도록 설정해두어서 삭제 또는 이름바꾸기 필요.
> 2. 위치 ls /etc/apt/preferences.d/nosnap.pref  << 이거 삭제!
> 3. 하고 snapd 설치 후 multipass설치하기


# Linux Mint Setup & k3s Playground

Linux Mint 재설치 후 바로 사용할 수 있는 **개인 개발 환경 세팅 스크립트**와  
**Multipass 기반 3노드 k3s 클러스터 구성 스크립트**입니다.

---

# Linux Mint Setup & k3s Playground

Linux Mint 재설치 후 바로 사용할 수 있는 **개인 개발 환경 세팅 스크립트**와  
**Multipass 기반 3노드 k3s 클러스터 구성 스크립트**입니다.

---

## 📦 포함된 파일

- `setup_mint.sh`  
  - Linux Mint(Ubuntu 기반) 초기 세팅 스크립트  
  - 설치되는 주요 패키지:
    - **기본 유틸리티**: git, curl, wget, vim, htop
    - **네트워크 진단**: net-tools, iproute2, traceroute, nmap
    - **보안/시스템**: ufw, ca-certificates, gnupg, lsb-release, apt-transport-https, software-properties-common
    - **개발 환경**: python3, python3-pip, python3-venv
    - **컨테이너/쿠버네티스**: docker, docker-compose-plugin, kubectl
    - **VM 관리**: multipass (snap 기반 설치 가능)
    - **SSH 서버**: openssh-server (자동 설치 및 활성화)

- `multipass-k3s-3node.sh`  
  - Multipass VM 3개(k3s1, k3s2, k3s3)를 띄우고  
    k3s(경량 Kubernetes) 클러스터를 자동 구성하는 스크립트
  - VM 스펙: `-c 1 -m 2G -d 20G`
  - 클러스터 kubeconfig를 `kubeconfig_k3s1.yaml` 로 추출하여 호스트에서 바로 `kubectl` 사용 가능

- `.vimrc`  
  - UTF-8 한글 지원 및 보편적인 개발자 세팅:
    - 줄 번호, 상대번호
    - 탭 대신 스페이스 (4칸)
    - 검색 하이라이트 & 스마트 검색
    - 시스템 클립보드 연동
    - 단축키: 스페이스 → `:nohlsearch`

---

## 🚀 사용 방법

### 1. 초기 세팅
> chmod +x setup_mint.sh
> sudo ./setup_mint.sh

### 2. Multipass + k3s 클러스터 구성
> chmod +x multipass-k3s-3node.sh
> ./multipass-k3s-3node.sh up


#### 클러스터 연결:

> export KUBECONFIG=$PWD/kubeconfig_k3s1.yaml
> kubectl get nodes -o wide


#### VM 관리:

> ./multipass-k3s-3node.sh stop    # VM 중지
> ./multipass-k3s-3node.sh start   # VM 시작
> ./multipass-k3s-3node.sh delete  # VM 삭제

### 3. Vim 설정 적용
> cp .vimrc ~/

### 🛠️ 추가 팁

### snapd 활성화 (Mint 기본 차단 해제)

> sudo rm /etc/apt/preferences.d/nosnap.pref
> sudo apt update
> sudo apt install snapd -y
> sudo snap install multipass --classic


### SSH 포트 변경 (예: 2222)

> /etc/ssh/sshd_config 편집 → Port 2222 설정

### UFW 규칙 추가:

> sudo ufw allow 2222/tcp
> sudo systemctl restart ssh


#### k3s 서버에 Traefik 끄기 → multipass-k3s-3node.sh 안의 INSTALL_K3S_EXEC 옵션에 --disable traefik 추가
#### nomodeset 옵션: 특정 그래픽/하드웨어 문제로 부팅 실패 시 GRUB에서 nomodeset 옵션 추가 후 부팅 시도

### 한글입력기 설치 방법(fcitx5)
#### 로케일/인코딩을 UTF-8로 통일(선행)
##### 권장: 영문 UI + 한글 입력 안정
> sudo locale-gen en_US.UTF-8 ko_KR.UTF-8
> sudo update-locale LANG=en_US.UTF-8 LC_CTYPE=ko_KR.UTF-8

##### 한국어 UI까지 원하면:
##### sudo update-locale LANG=ko_KR.UTF-8
##### 적용 확인(재로그인 후):
> locale

### 확인 완료 후 fcitx 설치 진행
> sudo apt install fcitx5 fcitx5-hangul fcitx5-configtool fcitx5-frontend-gtk3 fcitx5-frontend-qt5
> im-config -n fcitx5
> vi ~/.xprofile
> export GTK_IM_MODULE=fcitx
> export QT_IM_MODULE=fcitx
> export XMODIFIERS="@im=fcitx"
> 저장후 로그아웃/재로그임

#### 자동실행 등록
> mkdir -p ~/.config/autostart
> cp /usr/share/applications/org.fcitx.Fcitx5.desktop ~/.config/autostart/

#### 한글입력 모듈 확인
> fcitx5-configtool
> 입력방법 목록에 '한글' 또는 Hangul이 있어야함. 기존입력타입X
> 위의 한글과 영문키 전환하게끔 집어넣기

