#!/usr/bin/env bash
# 03. 만든 sdd_new.bin 을 장치의 /dev/block/sdd 에 쓴다. (사전 대조 → 기록 → 전체 readback 대조)
# 사용: 03_apply_sdd.sh [--yes]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
LOG="$LOGDIR/03_apply.log"; : > "$LOG"

ASSUME_YES=""
[ "${1:-}" = "--yes" ] && ASSUME_YES=1

setup_adb
T="$(adb_device)"
[ -z "$T" ] && die "adb 기기가 연결되어 있지 않습니다"
log "target=$T"

OLD="$WORK/sdd_full_backup.bin"
NEW="$WORK/sdd_new.bin"
[ -f "$OLD" ] || die "$OLD 없음 — 01 을 먼저 실행하세요"
[ -f "$NEW" ] || die "$NEW 없음 — 02 를 먼저 실행하세요"
[ "$(stat -c%s "$NEW")" -eq 33554432 ] || die "sdd_new.bin 크기가 32 MiB 가 아닙니다"

SU=/debug_ramdisk/su
read_sdd() { # $1=출력파일
  "$ADB" -s "$T" exec-out "$SU -c 'dd if=/dev/block/sdd bs=4096 2>/dev/null'" > "$1" 2>/dev/null
}

log "== 사전 대조: 장치의 sdd 가 백업과 같은지 =="
read_sdd "$WORK/current_before.bin"
cmp -s "$WORK/current_before.bin" "$OLD" || die "장치 sdd 가 백업과 다릅니다. 중단합니다(직접 확인 필요)"
log "사전 대조 OK"

if [ -z "$ASSUME_YES" ]; then
  echo
  echo "장치 /dev/block/sdd 에 proinfo 를 기록합니다."
  echo "  - GPT 주/백업 항목과 헤더를 갱신하고, proinfo 256 KiB 를 씁니다."
  echo "  - 이 작업 자체는 되돌릴 수 있지만(백업으로 복원), 잘못 쓰면 부팅이 안 될 수 있습니다."
  printf "계속하려면 'yes' 입력: "
  read -r ans
  [ "$ans" = "yes" ] || die "사용자가 취소했습니다"
fi

# sdd_new.bin 에서 조각을 잘라 쓴다. 오프셋은 LBA*4096.
slice() { # $1=src $2=dst $3=start $4=end
  python3 - "$1" "$2" "$3" "$4" <<'EOF'
import sys
src, dst, a, b = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
d = open(src, 'rb').read()
open(dst, 'wb').write(d[a:b])
EOF
}

slice "$NEW" "$WORK/part_proinfo.bin"         4194304 4456448
slice "$NEW" "$WORK/part_backup_entries.bin"  33533952 33538048
slice "$NEW" "$WORK/part_backup_header.bin"   33550336 33554432
slice "$NEW" "$WORK/part_primary_entries.bin" 8192 12288
slice "$NEW" "$WORK/part_primary_header.bin"  4096 8192

put() { # $1=파일 $2=시작 섹터
  head -c 4096 "$1" | "$ADB" -s "$T" shell "$SU -c 'dd of=/dev/block/sdd bs=4096 seek=$2 conv=notrunc 2>/dev/null'" >/dev/null \
    || die "쓰기 실패: $(basename "$1")"
  "$ADB" -s "$T" shell "$SU -c sync" >/dev/null 2>&1
  log "  기록 $(basename "$1") -> 섹터 $2"
}

log "== proinfo 내용 기록 (섹터 1024, 64 x 4K) =="
head -c 262144 "$WORK/part_proinfo.bin" \
  | "$ADB" -s "$T" shell "$SU -c 'dd of=/dev/block/sdd bs=4096 seek=1024 conv=notrunc 2>/dev/null'" >/dev/null \
  || die "proinfo 내용 기록 실패"
"$ADB" -s "$T" shell "$SU -c sync" >/dev/null 2>&1

log "== GPT 항목/헤더 기록 =="
put "$WORK/part_backup_entries.bin"  8187
put "$WORK/part_backup_header.bin"   8191
put "$WORK/part_primary_entries.bin" 2
put "$WORK/part_primary_header.bin"  1

log "== 전체 readback 대조 =="
read_sdd "$WORK/readback.bin"
if cmp -s "$WORK/readback.bin" "$NEW"; then
  log "READBACK MATCH"
  log "sha256: $(sha256sum "$WORK/readback.bin" | awk '{print $1}')"
else
  log "READBACK MISMATCH — 즉시 중단하고 백업으로 되돌리십시오"
  die "readback 불일치"
fi

log "다음 단계: 04_flash_stock.sh  (stock 복원) → 05_lock.sh"
