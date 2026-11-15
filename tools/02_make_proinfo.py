#!/usr/bin/env python3
"""02. sdd 원본 백업에 proinfo 파티션(GPT)을 추가해 sdd_new.bin 을 만든다.

TB371FC 는 proinfo 파티션이 없어서 `fastboot flashing lock` 이
FAILED (remote: 'Prc device unlocked, don't allow lock') 로 거부된다.
ABL 은 proinfo 0x19000 바이트를 쓰고 읽어 잠금 가능 여부를 판단하므로,
32 MiB sdd 디스크의 GPT 에 proinfo 항목을 추가하고 내용을 채워 넣는다.

동작은 오직 다음 다섯 곳만 바꾼다 (나머지 바이트는 건드리지 않는다):
  LBA 1     주 GPT 헤더 (항목 CRC, 헤더 CRC 갱신)
  LBA 2     주 GPT 항목 배열 (proinfo 항목 추가)
  LBA 1024  proinfo 내용 256 KiB ("deadbeef" + 0x20=2)
  LBA 8187  백업 GPT 항목 배열
  LBA 8191  백업 GPT 헤더

사용:
  python3 02_make_proinfo.py --input work/sdd_full_backup.bin --output work/sdd_new.bin
  python3 02_make_proinfo.py --input ... --output ... --check reference.bin   # 산출물 대조

종료 코드: 0 성공, 2 입력 오류, 3 이미 proinfo 있음, 4 검증 실패
"""
from __future__ import annotations

import argparse
import struct
import sys
import uuid
import zlib

LBA = 4096
DISK_SIZE = 32 * 1024 * 1024
PROINFO_FIRST = 1024          # 위키: 1024-1087 (256 KiB)
PROINFO_SECTORS = 64
PROINFO_BYTES = PROINFO_SECTORS * LBA
PROINFO_CONTENT = b"deadbeef"
TYPE_BASIC_DATA = uuid.UUID("ebd0a0a2-b9e5-4433-87c0-68b6b72699c7")
# 실제 리락에 사용한 값과 동일하게 고정 → 같은 입력에서 바이트 단위로 같은 출력이 나온다.
REFERENCE_GUID = uuid.UUID("4cbef1c0-4132-4923-a99e-2bd0f9dc42c4")

HDR_FMT = "<8sIIIIQQQQ16sQIII"
HDR_SIZE = struct.calcsize(HDR_FMT)   # 92


def die(msg: str, code: int = 2) -> "NoReturn":
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(code)


def read_header(img: bytes, lba: int) -> dict:
    off = lba * LBA
    raw = img[off:off + HDR_SIZE]
    (sig, rev, hsize, hcrc, _res, my, alt, first, last,
     dguid, ent_lba, nent, esize, entcrc) = struct.unpack(HDR_FMT, raw)
    if sig != b"EFI PART":
        die(f"LBA {lba} 에 GPT 헤더가 없습니다 (sig={sig!r})")
    if hsize != HDR_SIZE:
        die(f"예상하지 못한 헤더 크기: {hsize}")
    if esize != 128 or nent == 0:
        die(f"예상하지 못한 항목 배열: nent={nent} esize={esize}")
    # 헤더 CRC 검증 (CRC 필드 0 으로 두고 계산)
    check = bytearray(raw)
    struct.pack_into("<I", check, 16, 0)
    if zlib.crc32(bytes(check)) & 0xFFFFFFFF != hcrc:
        die(f"LBA {lba} 헤더 CRC 불일치 — 원본 이미지가 손상되었을 수 있습니다")
    return dict(sig=sig, rev=rev, hsize=hsize, my=my, alt=alt, first=first, last=last,
                dguid=dguid, ent_lba=ent_lba, nent=nent, esize=esize, entcrc=entcrc)


def read_entries(img: bytes, hdr: dict) -> list[bytearray]:
    base = hdr["ent_lba"] * LBA
    n, sz = hdr["nent"], hdr["esize"]
    ents = [bytearray(img[base + i * sz: base + (i + 1) * sz]) for i in range(n)]
    calc = zlib.crc32(b"".join(bytes(e) for e in ents)) & 0xFFFFFFFF
    if calc != hdr["entcrc"]:
        die(f"항목 배열 CRC 불일치 (계산 {calc:#010x}, 헤더 {hdr['entcrc']:#010x})")
    return ents


def entry_name(ent: bytes) -> str:
    return ent[56:128].decode("utf-16-le", "replace").rstrip("\x00")


def build_entry(guid: uuid.UUID) -> bytes:
    e = bytearray(128)
    e[0:16] = TYPE_BASIC_DATA.bytes_le
    e[16:32] = guid.bytes_le
    struct.pack_into("<QQQ", e, 32, PROINFO_FIRST, PROINFO_FIRST + PROINFO_SECTORS - 1, 0)
    name = "proinfo".encode("utf-16-le")
    e[56:56 + len(name)] = name
    return bytes(e)


def make_header(hdr: dict, ent_lba: int, entcrc: int, my: int, alt: int) -> bytes:
    raw = bytearray(HDR_SIZE)
    struct.pack_into(HDR_FMT, raw, 0, b"EFI PART", hdr["rev"], HDR_SIZE, 0, 0,
                     my, alt, hdr["first"], hdr["last"], hdr["dguid"],
                     ent_lba, hdr["nent"], hdr["esize"], entcrc)
    struct.pack_into("<I", raw, 16, zlib.crc32(bytes(raw)) & 0xFFFFFFFF)
    return bytes(raw)


def main() -> int:
    ap = argparse.ArgumentParser(description="sdd GPT 에 proinfo 파티션 추가")
    ap.add_argument("--input", required=True, help="sdd 원본 백업 (32 MiB)")
    ap.add_argument("--output", required=True, help="생성할 이미지 경로")
    ap.add_argument("--guid", default=str(REFERENCE_GUID),
                    help=f"proinfo 항목의 고유 GUID (기본: {REFERENCE_GUID})")
    ap.add_argument("--check", help="생성 후 이 파일과 바이트 단위로 비교")
    args = ap.parse_args()

    img = bytearray(open(args.input, "rb").read())
    if len(img) != DISK_SIZE:
        die(f"입력 크기가 32 MiB 가 아닙니다: {len(img)} bytes")

    hdr = read_header(img, 1)
    ents = read_entries(img, hdr)

    for e in ents:
        if e[0:16] != b"\x00" * 16 and entry_name(e) == "proinfo":
            print("이미 proinfo 항목이 있습니다. 변경하지 않고 종료합니다.")
            return 3

    slot = next((i for i, e in enumerate(ents) if e[0:16] == b"\x00" * 16), None)
    if slot is None:
        die("빈 GPT 항목 슬롯이 없습니다")

    print(f"입력     : {args.input} ({len(img)} bytes)")
    print(f"디스크   : {uuid.UUID(bytes_le=hdr['dguid'])}  LBA={LBA}  항목 {hdr['nent']}개")
    print(f"빈 슬롯  : [{slot}] 사용")

    ents[slot] = bytearray(build_entry(uuid.UUID(args.guid)))

    # proinfo 내용: 256 KiB 0 으로 채우고 0x00="deadbeef", 0x20=2
    content = bytearray(PROINFO_BYTES)
    content[0:len(PROINFO_CONTENT)] = PROINFO_CONTENT
    content[0x20] = 2

    blob = b"".join(bytes(e) for e in ents)
    entcrc = zlib.crc32(blob) & 0xFFFFFFFF

    p_off = hdr["my"] * LBA
    img[p_off:p_off + HDR_SIZE] = make_header(hdr, hdr["ent_lba"], entcrc, hdr["my"], hdr["alt"])
    b_off = hdr["alt"] * LBA
    backup_hdr = read_header(img, hdr["alt"])
    img[b_off:b_off + HDR_SIZE] = make_header(backup_hdr, backup_hdr["ent_lba"], entcrc,
                                              backup_hdr["my"], backup_hdr["alt"])

    e_off = hdr["ent_lba"] * LBA
    img[e_off:e_off + len(blob)] = blob
    be_off = backup_hdr["ent_lba"] * LBA
    img[be_off:be_off + len(blob)] = blob

    c_off = PROINFO_FIRST * LBA
    img[c_off:c_off + PROINFO_BYTES] = content

    with open(args.output, "wb") as f:
        f.write(img)

    print(f"출력     : {args.output}")
    print("\n파티션 목록:")
    for i, e in enumerate(ents):
        if e[0:16] == b"\x00" * 16:
            continue
        first, last, attr = struct.unpack_from("<QQQ", e, 32)
        mark = "  <- 추가" if i == slot else ""
        print(f"  [{i:2}] {entry_name(e):16} {first:5}-{last:<5} attr={attr:#x}{mark}")

    if args.check:
        a = bytes(img)
        b = open(args.check, "rb").read()
        if a == b:
            print(f"\n검증 OK: {args.check} 와 바이트 단위로 일치합니다.")
        else:
            diff = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
            lba = sorted({i // LBA for i in diff})
            print(f"\n검증 실패: {len(diff)} 바이트 다름, LBA {lba}", file=sys.stderr)
            return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
