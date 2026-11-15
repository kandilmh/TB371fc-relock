#!/usr/bin/env bash
# 04. stock ZUI 16.0.474 복원 (fastboot). super + boot/dtbo/vbmeta/vbmeta_system/recovery (a·b), wipe.
# 사용: 04_flash_stock.sh --stock-dir 'D:\12.7\flash_tmp' [--super super_stock.img] [--yes]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
LOG="$LOGDIR/04_flash.log"; : > "$LOG"

STOCK_DIR=""
SUPER_IMG="super_stock.img"
ASSUME_YES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stock-dir) STOCK_DIR="${2:?}"; shift 2 ;;
    --super)     SUPER_IMG="${2:?}"; shift 2 ;;
    --yes)       ASSUME_YES=1; shift ;;
    *) die "알 수 없는 인자: $1" ;;
  esac
done
[ -n "$STOCK_DIR" ] || die "--stock-dir 를 지정하세요 (Windows 경로, 예: 'D:\\12.7\\flash_tmp')"

setup_fastboot
SER="$(fb_device)"
[ -z "$SER" ] && die "fastboot 기기가 없습니다 (부트로더/ fastbootd 진입 확인)"
log "serial=$SER"

# Windows fastboot.exe 는 'D:\...' 형태를 그대로 받는다. 경로 구분자를 통일.
D="${STOCK_DIR//\//\\}"
log "stock dir = $D"

run() { log "\$ $*"; "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }

run "$FB" -s "$SER" getvar current-slot
run "$FB" -s "$SER" --set-active=a
run "$FB" -s "$SER" getvar current-slot

if [ -z "$ASSUME_YES" ]; then
  echo
  echo "stock 이미지를 플래시합니다. userdata/metadata 가 초기화됩니다."
  echo "  super  : $D\\$SUPER_IMG"
  echo "  슬롯 a·b: boot dtbo vbmeta vbmeta_system recovery"
  printf "계속하려면 'yes' 입력: "
  read -r ans
  [ "$ans" = "yes" ] || die "사용자가 취소했습니다"
fi

log "== super (12 GiB) =="
run "$FB" -s "$SER" flash super "$D\\$SUPER_IMG" || die "super 플래시 실패"

for part in boot dtbo vbmeta vbmeta_system recovery; do
  run "$FB" -s "$SER" --slot a flash "$part" "$D\\$part.img" || die "$part(a) 플래시 실패"
done
for part in boot dtbo vbmeta vbmeta_system recovery; do
  run "$FB" -s "$SER" --slot b flash "$part" "$D\\$part.img" || die "$part(b) 플래시 실패"
done

log "== wipe =="
run "$FB" -s "$SER" -w

log "== 확인 =="
run "$FB" -s "$SER" getvar current-slot
run "$FB" -s "$SER" getvar unlocked
run "$FB" -s "$SER" getvar partition-size:proinfo    # "FAILED" 면 03 단계가 빠진 것

log "== 재부팅 =="
run "$FB" -s "$SER" reboot

log "부팅 후: 05_lock.sh (잠금) → 06_verify.sh (검증)"
