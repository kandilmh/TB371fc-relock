# 배경과 분석 근거

## 1. 증상

순정 ZUI 16.0.474 로 복원한 뒤에도 잠금 명령이 거부되었습니다.

```
$ fastboot flashing lock
FAILED (remote: 'Prc device unlocked, don't allow lock')
```

## 2. 원인

ABL 의 잠금 사전 검사가 `proinfo` 파티션의 `0x19000` 바이트를 쓰고 읽어 확인합니다.
이 기기의 32 MiB 디스크(LUN3, `/dev/block/sdd`)에는 `proinfo` 항목이 아예 없어서
검사가 실패하고 PRC 오류 경로로 빠집니다.

`fastboot getvar partition-size:proinfo` 도 `FAILED` 를 돌려줍니다.

## 3. 디스크 구조 (실측)

| 항목 | 값 |
|---|---|
| 장치 | `/dev/block/sdd` |
| 크기 | 32 MiB (33,554,432 bytes) |
| 논리 섹터 | 4096 bytes, LBA 0–8191 |
| GPT 항목 | 32개 × 128 bytes (항목 배열 1 LBA = 4096 bytes) |
| 주 헤더 / 주 항목 | LBA 1 / LBA 2 |
| 백업 항목 / 백업 헤더 | LBA 8187 / LBA 8191 |
| usable | LBA 6 – 8186 |

기존 항목:

| 슬롯 | 이름 | LBA | attr |
|---|---|---|---|
| 0 | `ALIGN_TO_128K_1` | 6–31 | `0x1000000000000000` |
| 1 | `cdt` | 32–63 | `0x1000000000000000` |
| 2 | `ddr` | 64–575 | `0x1000000000000000` |
| 3 | `mdmddr` | 576–831 | `0x0` |

## 4. 추가한 항목

| 필드 | 값 |
|---|---|
| 슬롯 | 4 (첫 빈 슬롯) |
| 이름 | `proinfo` |
| LBA | 1024–1087 (256 KiB) |
| 타입 GUID | `ebd0a0a2-b9e5-4433-87c0-68b6b72699c7` (Basic Data) |
| 고유 GUID | `4cbef1c0-4132-4923-a99e-2bd0f9dc42c4` |
| attr | 0 |

내용(256 KiB):

| 오프셋 | 값 |
|---|---|
| `0x00` | ASCII `deadbeef` (8 bytes) |
| `0x20` | `0x02` |
| 나머지 | `0x00` |

재부팅 후 확인: `/dev/block/by-name/proinfo -> /dev/block/sdd5`

## 5. 변경 범위 (실측 대조)

원본 백업과 결과 이미지의 차이는 **119 바이트, LBA 5개**뿐입니다.

| LBA | 내용 |
|---|---|
| 1 | 주 GPT 헤더 (항목 CRC, 헤더 CRC) |
| 2 | 주 GPT 항목 배열 (슬롯 4) |
| 1024 | proinfo 내용 256 KiB |
| 8187 | 백업 GPT 항목 배열 |
| 8191 | 백업 GPT 헤더 |

`02_make_proinfo.py` 는 이 다섯 곳만 수정하며, 2026-11-15 에 실제로 사용한
`sdd_new.bin` 과 **바이트 단위로 동일한** 출력을 냅니다 (`--check` 로 확인).

```
검증 OK: work/sdd_new.bin 와 바이트 단위로 일치합니다.
```

## 6. stock 복원 (실시한 순서)

1. `fastboot getvar current-slot` — 당시 `b` 였음
2. `fastboot --set-active=a`
3. `fastboot flash super super_stock.img` (12 GiB, QFIL 청크 super_1..6 을 LP 메타데이터
   오프셋에 맞춰 조립한 이미지)
4. `boot`, `dtbo`, `vbmeta`, `vbmeta_system`, `recovery` 를 **a·b 슬롯 모두** 기록
5. `fastboot -w`
6. 재부팅 후 잠금

## 7. 실측 타임라인 (2026-11-15)

| 시각 | 단계 |
|---|---|
| 14:12 | sdd 백업 |
| 14:19 | proinfo 기록 |
| 14:21 | stock super 플래시 시작 |
| 14:39 | 재부팅 |
| 14:41 | 잠금 확정 |

## 8. 최종 검증 결과

| 항목 | 값 |
|---|---|
| 빌드 | `TB371FC_CN_OPEN_USER_Q00028.1_U_ZUI_16.0.474_ST_241129` (Android 14) |
| `ro.boot.flash.locked` | 1 |
| `ro.boot.verifiedbootstate` | green |
| `ro.boot.vbmeta.device_state` | locked |
| `ro.boot.secureboot` | 1 |
| `ro.boot.veritymode` | enforcing |
| 현재 슬롯 | a |
| proinfo | `/dev/block/by-name/proinfo -> sdd5` |
| Widevine | `sys.lenovo.widevine_security_level = L1` |

## 9. 위험과 주의

- **재언락 금지 권고.** 이 ABL 은 일반 `flashing unlock` 경로가 미지원으로 분석되었습니다.
  다시 풀었다면 같은 proinfo 절차가 또 필요할 수 있습니다.
- 잠금 상태에서는 `fastboot -w`(erase)가 거부됩니다. 초기화는 recovery 의 factory reset 을 씁니다.
- QFIL 재플래싱은 `rawprogram3.xml` 이 LUN3 GPT 를 덮어써 proinfo 를 지웁니다.
  `qfil_gpt/` 파일로 교체해야 유지됩니다.
- Play 인증은 Play 스토어 → 설정 → 정보에서 "기기 인증됨" 으로 확인합니다.

## 10. 검증하지 못한 것

- 다른 펌웨어 버전(ZUI 16.0.x 이외)에서 같은 절차가 통하는지
- 잠금 후 OTA 수신/설치 동작
- QFIL + 교체 GPT 조합의 실제 재현 (파일만 준비)
