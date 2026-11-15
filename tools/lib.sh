#!/usr/bin/env bash
# 공통 함수: adb/fastboot 탐색, 기기 선택, 로그
# 사용: source "$(dirname "$0")/lib.sh"
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/work}"
LOGDIR="${LOGDIR:-$ROOT/logs}"
mkdir -p "$WORK" "$LOGDIR" 2>/dev/null || true

log()  { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "${LOG:-/dev/null}"; }
die()  { log "ERROR: $*"; exit 1; }

# Windows adb/fastboot 래퍼를 우선 사용하고, 없으면 PATH 의 것을 쓴다.
find_tool() { # $1 = adb | fastboot
  local name=$1
  if [ -n "${!name:-}" ]; then echo "${!name}"; return 0; fi   # 환경변수 우선
  if [ -x "/mnt/c/adb/$name.exe" ]; then echo "/mnt/c/adb/$name.exe"; return 0; fi
  command -v "$name" 2>/dev/null && return 0
  return 1
}

setup_adb() {
  ADB="$(find_tool adb)" || die "adb 를 찾지 못했습니다 (ADB=... 로 지정하세요)"
  export ADB
}

setup_fastboot() {
  FB="$(find_tool fastboot)" || die "fastboot 를 찾지 못했습니다 (FB=... 로 지정하세요)"
  export FB
}

setup_tools() { setup_adb; setup_fastboot; }

adb_device() { # 연결된 adb 기기 1대의 시리얼
  "$ADB" devices 2>/dev/null | tr -d '\r' | awk 'NR>1 && $2=="device" {print $1}' \
    | grep -v 'tls-connect' | head -1
}

fb_device() { # fastboot 기기 시리얼
  "$FB" devices 2>/dev/null | tr -d '\r' | awk '$2=="fastboot" {print $1; exit}'
}
