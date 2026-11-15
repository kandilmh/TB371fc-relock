#!/usr/bin/env bash
# 05. 부트로더 재잠금. proinfo 가 없으면 ABL 이 PRC 오류로 거부한다.
# 사용: 05_lock.sh [--yes]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
LOG="$LOGDIR/05_lock.log"; : > "$LOG"

ASSUME_YES=""
[ "${1:-}" = "--yes" ] && ASSUME_YES=1

setup_fastboot
SER="$(fb_device)"
[ -z "$SER" ] && die "fastboot 기기가 없습니다"

log "== 잠금 전 확인 =="
"$FB" -s "$SER" getvar unlocked 2>&1 | tee -a "$LOG"
"$FB" -s "$SER" getvar current-slot 2>&1 | tee -a "$LOG"
"$FB" -s "$SER" getvar partition-size:proinfo 2>&1 | tee -a "$LOG"

if ! "$FB" -s "$SER" getvar partition-size:proinfo 2>&1 | grep -qiE 'size:'; then
  log "경고: 이 모드에서 proinfo 크기를 못 읽었습니다(부트로더/fastbootd 차이). 계속 진행하되 실패하면 03 단계를 확인하세요."
fi

if [ -z "$ASSUME_YES" ]; then
  echo
  echo "부트로더를 잠급니다. 실패하면 기기는 그대로 남고, 성공하면 이후 fastboot -w 가 막힙니다."
  printf "계속하려면 'yes' 입력: "
  read -r ans
  [ "$ans" = "yes" ] || die "사용자가 취소했습니다"
fi

log "== fastboot flashing lock =="
"$FB" -s "$SER" flashing lock 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}

if [ "$RC" -eq 0 ]; then
  echo
  echo "기기 화면에서 '볼륨키로 선택 + 전원키로 확정' 하십시오."
  echo "잠금이 확정되면 기기가 재부팅됩니다."
  log "잠금 명령 OK — 기기 확인 대기"
  echo
  echo "재부팅 후 06_verify.sh 로 최종 확인하십시오."
else
  log "잠금 거부됨 (rc=$RC)"
  cat <<'EOF'

거부 메시지가 'Prc device unlocked, don't allow lock' 이라면:
  1) 03 단계로 proinfo 가 실제로 기록되었는지 확인
     (재부팅 후 adb shell ls -l /dev/block/by-name/proinfo)
  2) proinfo 기록 후 재부팅하지 않았으면 재부팅 후 다시 시도
  3) 여전히 안 되면 백업(sdd_full_backup.bin)으로 되돌리고 재시도
EOF
  exit "$RC"
fi
