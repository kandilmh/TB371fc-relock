# TB371FC 부트로더 재잠금 (relock) 툴킷

Lenovo Xiaoxin Pad Pro 12.7 (TB371FC) 에서 **순정 ZUI 로 되돌린 뒤 부트로더를 다시 잠그는** 절차를
스크립트로 정리한 것입니다. 2026-11-15 실제 기기에서 성공한 작업을 그대로 옮겼습니다.

- 결과: `locked / green / verity enforcing / Widevine L1` 확인
- 소요: 약 20분 (백업 포함, 이미지 준비 제외)

## 먼저 읽을 것

> **커스텀 롬(Lunaris 등)이나 수정된 부팅 이미지를 쓰는 동안에는 잠그지 마십시오.** 잠그면 부팅되지 않습니다.
> 이 툴킷은 **완전히 순정으로 복원한 뒤 잠그는** 경우에만 씁니다.

1. `fastboot -w` 는 데이터를 지웁니다. 필요한 것은 미리 백업하십시오.
2. 잠금이 성공하면 이후 `fastboot -w`, `fastboot flash` 가 막힙니다. 되돌리려면 다시 언락해야 하고
   그때 데이터가 초기화됩니다.
3. `sdd_full_backup.bin` (32 MiB) 은 **절대 지우지 마십시오.** 복구의 유일한 기준입니다.

## 왜 그냥 `fastboot flashing lock` 이 안 되는가

이 기기에는 `proinfo` 파티션이 없습니다. ABL 은 잠금 전에 `proinfo` 의 `0x19000` 바이트를 쓰고
읽어 확인하는데, 파티션이 없으면 검사가 실패하고 다음 오류로 빠집니다.

```
fastboot flashing lock
FAILED (remote: 'Prc device unlocked, don't allow lock')
```

해결은 32 MiB 디스크(`/dev/block/sdd`)의 GPT 에 `proinfo` 항목을 추가하는 것입니다.
`02_make_proinfo.py` 가 이 작업을 합니다 (LBA 1024–1087, 256 KiB, 내용 `deadbeef` + `0x20=2`).

## 준비물

| 항목 | 설명 |
|---|---|
| adb / fastboot | Windows `platform-tools`. WSL 이면 `/mnt/c/adb/adb.exe` 를 자동으로 씁니다 |
| 루팅된 부팅 상태 | `sdd` 를 읽고 쓰려면 `su` 가 필요합니다 (`01`, `03` 단계) |
| stock ZUI 16.0.474 이미지 | `super`, `boot`, `dtbo`, `vbmeta`, `vbmeta_system`, `recovery` |
| Python 3.8+ | `02` 단계 (GPT 계산) |
| 디스크 여유 | stock 이미지 약 13 GiB (super 12 GiB 포함) |

## 절차

| 단계 | 스크립트 | 하는 일 |
|---|---|---|
| 0 | — | 기기를 순정 부팅 가능한 상태로 만들고 USB 디버깅 허용 |
| 1 | `tools/01_backup_sdd.sh` | `sdd` 32 MiB 백업 + sha256 |
| 2 | `tools/02_make_proinfo.py` | 백업에 proinfo 를 넣어 `sdd_new.bin` 생성 |
| 3 | `tools/03_apply_sdd.sh` | 기기에 기록 + 전체 readback 대조 |
| 4 | `tools/04_flash_stock.sh` | stock 복원 (super + a·b 슬롯) + wipe |
| 5 | `tools/05_lock.sh` | `fastboot flashing lock` + 기기 확인 |
| 6 | `tools/06_verify.sh` | 잠금/검증 상태 최종 확인 |

### 1. 백업

```bash
tools/01_backup_sdd.sh
# work/sdd_full_backup.bin (32 MiB), work/sdd_full_backup.bin.sha256
```

### 2. proinfo 이미지 생성

```bash
python3 tools/02_make_proinfo.py \
  --input  work/sdd_full_backup.bin \
  --output work/sdd_new.bin
```

이미 만들어진 결과와 비교하려면:

```bash
python3 tools/02_make_proinfo.py \
  --input work/sdd_full_backup.bin --output /tmp/check.bin \
  --check work/sdd_new.bin
```

> `--check` 는 바이트 단위 비교입니다. 2026-11-15 실제 사용한 이미지와 **완전히 일치**하는 것을
> 확인했습니다.

### 3. 기기에 기록

```bash
tools/03_apply_sdd.sh          # 사전 대조 → 기록 → readback 대조
# READBACK MATCH 가 나와야 합니다.
```

### 4. stock 복원

```bash
tools/04_flash_stock.sh --stock-dir 'D:\12.7\flash_tmp'
```

Windows fastboot 를 쓰므로 `--stock-dir` 는 Windows 경로로 줍니다. `super` 는 12 GiB 라
시간이 걸립니다. `boot`/`dtbo`/`vbmeta`/`vbmeta_system`/`recovery` 는 **a·b 슬롯 모두** 기록합니다.
마지막에 `fastboot -w` 로 초기화하고 재부팅합니다.

### 5. 잠금

```bash
tools/05_lock.sh
# 기기 화면에서 볼륨키로 선택 + 전원키로 확정
```

`getvar partition-size:proinfo` 가 `FAILED` 면 3단계가 빠진 것이므로 잠금이 거부됩니다.

### 6. 검증

부팅 완료 후:

```bash
tools/06_verify.sh
```

기대값:

| 항목 | 값 |
|---|---|
| `ro.boot.flash.locked` | 1 |
| `ro.boot.verifiedbootstate` | green |
| `ro.boot.vbmeta.device_state` | locked |
| `ro.boot.secureboot` | 1 |
| `ro.boot.veritymode` | enforcing |
| `/dev/block/by-name/proinfo` | `-> sdd5` |
| `sys.lenovo.widevine_security_level` | L1 |

## 문제 해결

**`Prc device unlocked, don't allow lock`**
proinfo 가 없거나, 기록 후 재부팅하지 않았습니다. 3단계를 다시 하고 재부팅한 뒤 잠그십시오.

**`READBACK MISMATCH`**
쓰기가 일부 실패했습니다. 백업으로 되돌리고(아래) 3단계를 다시 하십시오.

**QFIL 로 다시 플래싱할 때**
`rawprogram3.xml` 이 LUN3 GPT 를 덮어써 proinfo 가 사라집니다. `qfil_gpt/` 의 두 파일을
패키지 `image/` 에 교체한 뒤 실행하십시오. 그대로 실행하면 잠금이 다시 실패합니다.

**백업으로 되돌리기**

```bash
ADB=adb  # 필요하면 경로 지정
T=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')
"$ADB" -s "$T" push work/sdd_full_backup.bin /data/local/tmp/sdd_orig.bin
"$ADB" -s "$T" shell "su -c 'dd if=/data/local/tmp/sdd_orig.bin of=/dev/block/sdd bs=4096 && sync'"
```

## 폴더 구조

```
TB371fc-relock/
├── README.md                 이 문서
├── docs/
│   └── PROCEDURE.md          배경, 분석 근거, 실측 기록
├── tools/
│   ├── lib.sh                공통 함수 (adb/fastboot 탐색, 로그)
│   ├── 01_backup_sdd.sh
│   ├── 02_make_proinfo.py
│   ├── 03_apply_sdd.sh
│   ├── 04_flash_stock.sh
│   ├── 05_lock.sh
│   └── 06_verify.sh
├── qfil_gpt/                 QFIL 재플래싱 시 교체할 GPT
└── work/                     백업, 생성 이미지 (저장소에 올리지 않음)
```

## 확인하지 못한 것

- ZUI 16.0.474 이외 펌웨어에서 같은 절차가 통하는지
- 잠금 후 OTA 수신과 설치
- QFIL과 교체 GPT 조합의 실제 재현 (파일만 준비)

자세한 배경과 실측 기록은 [`docs/PROCEDURE.md`](docs/PROCEDURE.md)에 있습니다.

## 참고

- 개인 기록이며 Lenovo, Lunaris 팀과 무관합니다.
- 기기 상태를 바꾸는 작업입니다. 사용에 따른 책임은 사용자에게 있습니다.
