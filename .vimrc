" ==============================
" 기본 Vim 설정 (.vimrc)
" ==============================

" --- 인코딩 & 언어 설정 ---
set encoding=utf-8
set fileencodings=utf-8,euc-kr,latin1
set termencoding=utf-8

" --- UI/편의 기능 ---
syntax on              " 구문 하이라이팅
set number             " 줄 번호 표시
set relativenumber     " 상대 번호 (편집시 유용, 원하면 끄세요)
set ruler              " 커서 위치 표시
set showcmd            " 입력 중인 명령 표시
set cursorline         " 현재 커서 라인 강조
set wildmenu           " 명령 자동완성 메뉴
set laststatus=2       " 상태줄 항상 표시
set showmatch          " 괄호 짝 하이라이트
set hlsearch           " 검색 결과 하이라이트
set incsearch          " 입력과 동시에 검색
set ignorecase         " 검색 시 대소문자 구분 안 함
set smartcase          " 단, 대문자 포함하면 구분

" --- 들여쓰기 & 탭 ---
set tabstop=4          " 탭 = 4칸
set shiftwidth=4       " 자동 들여쓰기 4칸
set expandtab          " 탭 대신 스페이스
set autoindent         " 자동 들여쓰기
set smartindent        " 스마트 들여쓰기

" --- 색상 & 테마 ---
set background=dark
colorscheme desert     " Vim 기본 내장 색상 (solarized 좋아하면 변경 가능)

" --- 파일 관련 ---
set nobackup
set nowritebackup
set noswapfile
set hidden             " 저장 안해도 버퍼 이동 가능
set autoread           " 외부에서 수정된 파일 자동 반영

" --- 편집 편의 ---
set clipboard=unnamedplus   " 시스템 클립보드 공유
set backspace=indent,eol,start " 백스페이스 사용 개선
set mouse=a                 " 마우스 사용 가능 (터미널 기반에서도)

" --- UTF-8 한글 입력시 문제 예방 ---
set langmenu=ko_KR.UTF-8
language messages en_US.UTF-8

" --- 단축키 ---
nnoremap <SPACE> :nohlsearch<CR>   " 스페이스 누르면 검색 하이라이트 해제

