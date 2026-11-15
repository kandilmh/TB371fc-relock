#!/usr/bin/env bash
# 01. 장치의 sdd(32 MiB) 원본을 그대로 백업한다. 이 파일이 모든 복구의 기준이다.
# 사용: 01_backup_sdd.sh [--force]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
LOG="$LOGDIR/01_backup.log"; : > "$LOG"

FORCE=""
[ "${1:-}" = "--force" ] && FORCE=1

setup_adb
T="$(adb_device)"
[ -z "$T" ] && die "adb 기기가 연결되어 있지 않습니다 (USB 디버깅 허용 확인)"
log "target=$T"

OUT="$WORK/sdd_full_backup.bin"
if [ -f "$OUT" ] && [ -z "$FORCE" ]; then
  die "$OUT 이 이미 있습니다. 덮어쓰려면 --force"
fi

SU=/debug_ramdisk/su
log "sdd 백업 중 (32 MiB) …"
"$ADB" -s "$T" exec-out "$SU -c 'dd if=/dev/block/sdd bs=4096 2>/dev/null'" > "$OUT" 2>/dev/null \
  || die "dd 실패 — 루팅(su) 상태인지 확인"

SIZE=$(stat -c%s "$OUT")
[ "$SIZE" -eq 33554432 ] || die "백업 크기가 32 MiB 가 아닙니다: $SIZE bytes"

log "sha256: $(sha256sum "$OUT" | awk '{print $1}')"
sha256sum "$OUT" > "$OUT.sha256"
log "저장: $OUT"
log "다음 단계: tools/02_make_proinfo.py --input $OUT --output $WORK/sdd_new.bin"
