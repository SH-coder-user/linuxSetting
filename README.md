# 포맷 후 리눅스 재설치 USB 사용시
> 1. 바이오스셋업 진입 F1, F2, Del 등
> 2. BOOT 순서 USB로 맨 첫번째 두기
> 3. 중요!!!바이오스 셋업에서 반드시 SecureBoot 부분을 Disabled로 바꾼뒤 재시작하기!(대부분 이거안해서 리눅스 부팅시 오류뜨고 튕김)


# Multipass 설치시
> 1. snapd 사용하도록 설정해야함. 민트리눅스의 경우 기본적으로 snap명령어사용안되도록 설정해두어서 삭제 또는 이름바꾸기 필요.
> 2. 위치 ls /etc/apt/preferences.d/nosnap.pref  << 이거 삭제!
> 3. 하고 snapd 설치 후 multipass설치하기
