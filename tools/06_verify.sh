#!/usr/bin/env bash
# 06. 잠금 결과 검증 (부팅 후, adb)
# 사용: 06_verify.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
LOG="$LOGDIR/06_verify.log"; : > "$LOG"

setup_adb
T="$(adb_device)"
[ -z "$T" ] && die "adb 기기가 없습니다 (부팅 완료 후 다시 실행)"

get() { "$ADB" -s "$T" shell getprop "$1" 2>/dev/null | tr -d '\r'; }

check() { # $1=이름 $2=기대값 $3=실제값
  if [ "$2" = "$3" ]; then
    printf '  %-34s %-12s OK\n' "$1" "$3" | tee -a "$LOG"
    return 0
  fi
  printf '  %-34s %-12s 기대값 %s\n' "$1" "$3" "$2" | tee -a "$LOG"
  return 1
}

fail=0
log "== 부트 상태 =="
check ro.boot.flash.locked         1 "$(get ro.boot.flash.locked)"       || fail=1
check ro.boot.verifiedbootstate    green "$(get ro.boot.verifiedbootstate)" || fail=1
check ro.boot.vbmeta.device_state  locked "$(get ro.boot.vbmeta.device_state)" || fail=1
check ro.boot.secureboot           1 "$(get ro.boot.secureboot)"         || fail=1
check ro.boot.veritymode           enforcing "$(get ro.boot.veritymode)" || fail=1

log "== 빌드 =="
printf '  %-34s %s\n' ro.build.display.id "$(get ro.build.display.id)" | tee -a "$LOG"

log "== proinfo =="
PN="$("$ADB" -s "$T" shell 'ls -l /dev/block/by-name/proinfo' 2>/dev/null | tr -d '\r')"
printf '  %s\n' "${PN:-없음}" | tee -a "$LOG"
case "$PN" in
  *sdd5*) : ;;
  *) log "  경고: proinfo 링크가 sdd5 가 아닙니다"; fail=1 ;;
esac

log "== Widevine =="
WV="$(get sys.lenovo.widevine_security_level)"
printf '  %-34s %s\n' sys.lenovo.widevine_security_level "$WV" | tee -a "$LOG"
[ "$WV" = "L1" ] || log "  참고: L1 이 아니면 잠금은 되었지만 프로비저닝이 안 된 상태일 수 있습니다"

log "== 슬롯 =="
printf '  %-34s %s\n' ro.boot.slot_suffix "$(get ro.boot.slot_suffix)" | tee -a "$LOG"

echo
if [ "$fail" -eq 0 ]; then
  log "검증 통과: locked / green / verity enforcing"
else
  log "검증 실패 항목이 있습니다. 위 값을 확인하십시오."
  exit 1
fi
