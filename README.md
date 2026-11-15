# TB371FC 부트로더 재잠금 (relock)

**한국어** | [English](README.en.md)

Lenovo Xiaoxin Pad Pro 12.7 (TB371FC)을 **순정 ZUI로 되돌린 뒤 부트로더를 다시 잠그는** 방법입니다.
2026-11-15 실제 기기에서 성공한 과정을 스크립트와 함께 정리했습니다.

- 결과: `locked / green / verity enforcing / Widevine L1`
- 소요 시간: 준비 1~2시간(다운로드 포함), 기기 작업 약 30분

---

## ⚠️ 시작 전에 꼭 읽어 주십시오

1. **커스텀 롬(Lunaris 등)이나 수정된 부팅 이미지를 쓰는 상태에서는 절대 잠그지 마십시오.** 잠그면 부팅되지 않습니다.
   이 방법은 **순정 롬을 다시 설치한 뒤에** 잠그는 경우에만 씁니다. (4단계에서 순정을 설치합니다)
2. **기기의 모든 데이터가 지워집니다.** 사진, 파일 등은 미리 PC나 클라우드에 옮기십시오.
3. 1단계에서 만드는 `sdd_full_backup.bin`(32 MiB)은 **잠금이 끝날 때까지 절대 지우지 마십시오.** 문제가 생겼을 때 되돌릴 수 있는 유일한 파일입니다.
4. 잠근 뒤 다시 풀면(언락) 데이터가 또 초기화됩니다.

## 왜 그냥 잠그면 안 되나요?

이 기기는 `fastboot flashing lock`을 입력하면 다음 오류가 나고 잠기지 않습니다.

```
FAILED (remote: 'Prc device unlocked, don't allow lock')
```

부트로더가 잠그기 전에 `proinfo`라는 작은 영역을 확인하는데, 이 기기에는 그 영역이 없기 때문입니다.
그래서 **`proinfo` 영역을 직접 만들어 준 다음** 잠급니다. 1~3단계가 그 작업입니다.
자세한 분석은 [`docs/PROCEDURE.md`](docs/PROCEDURE.md)에 있습니다.

## 처음 보는 용어

| 용어 | 뜻 |
|---|---|
| adb | PC에서 켜져 있는 기기에 명령을 보내는 도구 |
| fastboot | 기기가 부트로더 모드일 때 이미지를 설치(플래시)하거나 잠금을 거는 도구 |
| 부트로더 모드 | 안드로이드가 켜지기 전 단계의 화면. fastboot 명령은 이 화면에서만 됩니다 |
| 루팅 (Magisk) | 기기의 관리자 권한(`su`). 1·3단계에서 저장 영역을 직접 읽고 쓰기 위해 필요합니다 |
| WSL | Windows 안에서 리눅스(Ubuntu)를 쓰는 기능. 이 스크립트들은 WSL에서 실행합니다 |

---

## 준비물

| 항목 | 설명 |
|---|---|
| Windows PC + WSL(Ubuntu) | 스크립트는 WSL에서 실행하고, adb/fastboot는 Windows용을 씁니다 |
| USB 케이블 | 데이터 전송이 되는 케이블 |
| platform-tools | Google의 adb/fastboot. `C:\adb`에 풀어 둡니다 |
| 루팅된 기기 | Magisk로 루팅된 상태여야 합니다. 지금 쓰는 롬이 무엇이든 상관없습니다 |
| 순정 펌웨어 | ZUI 16.0.474. 이 저장소의 [릴리스](https://github.com/kandilmh/TB371fc-relock/releases/tag/stock-zui-16.0.474)에서 받습니다 |
| 디스크 여유 공간 | C 드라이브에 약 30 GB |

### 1) WSL 설치

PowerShell을 **관리자 권한**으로 열고 실행합니다. 설치 후 재부팅하고, Ubuntu 사용자 이름/비밀번호를 정합니다.

```powershell
wsl --install
```

Ubuntu 창(시작 메뉴 → Ubuntu)에서 필요한 프로그램을 설치합니다.

```bash
sudo apt update && sudo apt install -y git python3 p7zip-full
```

### 2) platform-tools 설치

1. [platform-tools](https://developer.android.com/tools/releases/platform-tools)에서 Windows용을 받습니다.
2. 압축을 풀어 `C:\adb\adb.exe`, `C:\adb\fastboot.exe`가 되도록 둡니다. 스크립트가 이 위치를 자동으로 찾습니다.
   - 다른 곳에 두었다면 실행 전에 `export ADB=/mnt/d/tools/adb.exe FB=/mnt/d/tools/fastboot.exe`처럼 지정합니다.

### 3) 이 저장소 받기

Ubuntu 창에서:

```bash
cd ~
git clone https://github.com/kandilmh/TB371fc-relock.git
cd TB371fc-relock
```

**이후 모든 명령은 이 폴더(`~/TB371fc-relock`)에서 실행합니다.**

### 4) 순정 펌웨어 받기와 준비

1. [릴리스](https://github.com/kandilmh/TB371fc-relock/releases/tag/stock-zui-16.0.474)에서 다음 4개를 `C:\tb371\download` 폴더에 받습니다.
   `TB371FC.7z.000`, `TB371FC.7z.001`, `TB371FC.7z.002`, `join_stock.py`
2. 조각을 합칩니다. 각 조각과 결과 파일의 sha256까지 자동으로 확인합니다.

   ```bash
   python3 /mnt/c/tb371/download/join_stock.py
   ```

   `완료` 와 `sha256 ... 일치`가 나오면 성공입니다.
3. 압축을 풉니다. (몇 분 걸립니다)

   ```bash
   7z x /mnt/c/tb371/download/TB371FC.7z -o/mnt/c/tb371/download
   ```

4. fastboot로 설치할 이미지를 만듭니다. 펌웨어 안의 `super` 조각 6개를 하나로 합치고, 나머지 이미지를 복사합니다.

   ```bash
   python3 tools/00_prepare_stock.py \
     --package /mnt/c/tb371/download/TB371FC_ZUI_16.0.474 \
     --out /mnt/c/tb371/stock
   ```

   `C:\tb371\stock`에 이미지 6개(`super_stock.img`, `boot.img`, `dtbo.img`, `vbmeta.img`, `vbmeta_system.img`, `recovery.img`)가 생기면 됩니다.

### 5) 기기 연결 확인

1. 기기에서 **설정 → 태블릿 정보 → 빌드 번호**를 7번 눌러 개발자 옵션을 켭니다.
2. **설정 → 시스템 → 개발자 옵션 → USB 디버깅**을 켭니다.
3. USB로 연결하고, 기기에 뜨는 "USB 디버깅 허용"에서 **허용**을 누릅니다.
4. 연결과 루팅을 확인합니다.

   ```bash
   /mnt/c/adb/adb.exe devices          # 기기 번호 옆에 device 가 보여야 합니다
   /mnt/c/adb/adb.exe shell su -c id   # uid=0(root) 가 보여야 합니다
   ```

   `su -c id`를 처음 실행하면 기기에 Magisk 권한 요청이 뜹니다. **허용**을 누르십시오.

---

## 전체 흐름

| 단계 | 기기 상태 | 실행 | 하는 일 |
|---|---|---|---|
| 1 | 켜진 상태 (adb) | `tools/01_backup_sdd.sh` | 저장 영역(sdd, 32 MiB) 백업 |
| 2 | 상관없음 | `tools/02_make_proinfo.py` | 백업에 `proinfo`를 추가한 새 이미지 생성 |
| 3 | 켜진 상태 (adb) | `tools/03_apply_sdd.sh` | 새 이미지를 기기에 기록하고 다시 읽어 대조 |
| 4 | 부트로더 모드 | `tools/04_flash_stock.sh` | 순정 롬 설치 + 데이터 초기화 |
| 5 | 부트로더 모드 | `tools/05_lock.sh` | 부트로더 잠금 |
| 6 | 켜진 상태 (adb) | `tools/06_verify.sh` | 잠금 상태 최종 확인 |

각 스크립트의 기록은 `logs/` 폴더에 남습니다.

## 1단계. 백업

```bash
tools/01_backup_sdd.sh
```

- `work/sdd_full_backup.bin`(32 MiB)과 sha256 값이 만들어집니다.
- **이 파일을 PC의 다른 곳(예: `C:\tb371\backup`)에도 복사해 두십시오.**

  ```bash
  mkdir -p /mnt/c/tb371/backup && cp work/sdd_full_backup.bin* /mnt/c/tb371/backup/
  ```

## 2단계. proinfo 이미지 만들기

```bash
python3 tools/02_make_proinfo.py --input work/sdd_full_backup.bin --output work/sdd_new.bin
```

- PC에서만 계산하며 기기는 건드리지 않습니다.
- 원본과 달라지는 곳은 GPT 표 4곳과 `proinfo` 내용 1곳뿐입니다.

## 3단계. 기기에 기록

```bash
tools/03_apply_sdd.sh
```

- 확인 질문에 `yes`를 입력합니다.
- 마지막에 **`READBACK MATCH`**가 나와야 합니다. 다른 메시지가 나오면 아래 [문제 해결](#문제-해결)을 보십시오.
- 기록이 끝나면 **기기를 재부팅**하고, `proinfo`가 생겼는지 확인합니다.

  ```bash
  /mnt/c/adb/adb.exe reboot
  # 부팅이 끝난 뒤
  /mnt/c/adb/adb.exe shell ls -l /dev/block/by-name/proinfo   # ... -> /dev/block/sdd5 가 보이면 성공
  ```

## 4단계. 순정 롬 설치

1. 기기를 부트로더 모드로 재부팅합니다.

   ```bash
   /mnt/c/adb/adb.exe reboot bootloader
   ```

2. 기기가 보이는지 확인합니다.

   ```bash
   /mnt/c/adb/fastboot.exe devices    # 기기 번호 옆에 fastboot 가 보여야 합니다
   ```

3. 설치합니다. 경로는 **Windows 형식**으로 적습니다.

   ```bash
   tools/04_flash_stock.sh --stock-dir 'C:\tb371\stock'
   ```

- 확인 질문에 `yes`를 입력합니다.
- `super`(12 GiB) 설치에 10~20분 걸립니다. **중간에 케이블을 뽑지 마십시오.**
- 끝나면 데이터 초기화 후 기기가 자동으로 재부팅됩니다.

## 5단계. 잠금

1. 순정 ZUI가 처음 켜지면 초기 설정을 간단히 넘기고, [준비 5)](#5-기기-연결-확인)의 1~3번처럼 USB 디버깅을 다시 켭니다.
2. 부트로더 모드로 들어가서 잠급니다.

   ```bash
   /mnt/c/adb/adb.exe reboot bootloader
   tools/05_lock.sh
   ```

3. 확인 질문에 `yes`를 입력합니다.
4. **기기 화면**에 잠금 확인 메뉴가 뜹니다. **볼륨 키로 잠금(Lock) 항목을 고르고 전원 키로 확정**합니다.
5. 기기가 초기화되며 재부팅됩니다.

## 6단계. 확인

부팅이 끝나면 초기 설정 후 USB 디버깅을 다시 켜고 실행합니다.

```bash
tools/06_verify.sh
```

모든 항목 옆에 `OK`가 나오면 끝입니다.

| 항목 | 기대값 |
|---|---|
| `ro.boot.flash.locked` | 1 |
| `ro.boot.verifiedbootstate` | green |
| `ro.boot.vbmeta.device_state` | locked |
| `ro.boot.secureboot` | 1 |
| `ro.boot.veritymode` | enforcing |
| `/dev/block/by-name/proinfo` | `-> sdd5` |
| `sys.lenovo.widevine_security_level` | L1 |

Play 스토어 → 설정 → 정보에서 "기기 인증됨"도 확인할 수 있습니다.

---

## 문제 해결

**`adb devices`에 아무것도 안 나오거나 `unauthorized`가 나옵니다**
USB 디버깅이 켜져 있는지, 기기에 뜬 "USB 디버깅 허용"을 눌렀는지 확인하십시오. 케이블이 충전 전용일 수도 있습니다.

**`dd 실패 — 루팅(su) 상태인지 확인`**
Magisk 루팅이 안 되어 있거나, Magisk 권한 요청을 거부했습니다. `adb shell su -c id`로 먼저 확인하십시오.
스크립트는 Magisk의 `su`(`/debug_ramdisk/su`)를 씁니다. KernelSU 등 다른 루팅 도구에서는 확인하지 않았습니다.

**부트로더 모드에서 `fastboot devices`에 아무것도 안 나옵니다**
Windows에 USB 드라이버가 없을 수 있습니다. 장치 관리자에서 느낌표가 붙은 장치에 Google USB Driver를 설치하십시오.

**`Prc device unlocked, don't allow lock`**
`proinfo`가 없거나, 기록 후 재부팅하지 않았습니다. 3단계를 다시 하고 재부팅한 뒤 잠그십시오.

**`READBACK MISMATCH`**
기록이 일부 실패했습니다. 아래 방법으로 백업을 되돌린 뒤 3단계를 다시 하십시오.

**백업으로 되돌리기** (기기가 켜져 있고 루팅된 상태에서)

```bash
ADB=/mnt/c/adb/adb.exe
"$ADB" push work/sdd_full_backup.bin /data/local/tmp/sdd_orig.bin
"$ADB" shell "su -c 'dd if=/data/local/tmp/sdd_orig.bin of=/dev/block/sdd bs=4096 && sync'"
```

**QFIL로 다시 플래싱하는 경우**
QFIL 패키지의 `rawprogram3.xml`이 `proinfo`를 지웁니다. `qfil_gpt/`의 두 파일로 패키지 `image/` 폴더의 같은 이름 파일을 바꾼 뒤 실행하십시오.

---

## 폴더 구조

```
TB371fc-relock/
├── README.md / README.en.md   설명서 (한국어 / 영어)
├── docs/PROCEDURE.md          배경, 분석 근거, 실측 기록
├── tools/
│   ├── 00_prepare_stock.py    펌웨어에서 fastboot 이미지 준비 (super 조각 합치기)
│   ├── 01_backup_sdd.sh       sdd 백업
│   ├── 02_make_proinfo.py     proinfo 추가 이미지 생성
│   ├── 03_apply_sdd.sh        기기에 기록 + 대조
│   ├── 04_flash_stock.sh      순정 롬 설치
│   ├── 05_lock.sh             잠금
│   ├── 06_verify.sh           확인
│   └── lib.sh                 공통 함수
├── qfil_gpt/                  QFIL 재플래싱 시 바꿔 넣을 GPT
└── work/, logs/               백업, 생성 이미지, 기록 (저장소에 올리지 않음)
```

## 확인하지 못한 것

- ZUI 16.0.474 외의 펌웨어에서 같은 방법이 통하는지
- 잠금 후 OTA 업데이트 수신과 설치
- QFIL과 교체 GPT 조합 (파일만 준비)
- Windows + WSL 외의 환경 (스크립트가 Windows용 adb/fastboot와 Windows 경로를 기준으로 작성됨)

## 참고

- 개인 기록이며 Lenovo, Lunaris 팀과 관계없습니다.
- 기기 상태를 바꾸는 작업입니다. 사용에 따른 책임은 사용자에게 있습니다.
