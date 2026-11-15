#!/usr/bin/env python3
"""00. 순정 펌웨어(QFIL 패키지)에서 4단계에 쓸 fastboot 이미지를 준비합니다.

QFIL 패키지에는 super 가 super_1.img ~ super_6.img 조각으로 들어 있습니다.
이 스크립트는 rawprogram0.xml 의 위치 정보대로 조각을 이어 붙여 super_stock.img(12 GiB)를 만들고,
boot / dtbo / vbmeta / vbmeta_system / recovery 를 같은 폴더에 복사합니다.

사용:
    python3 tools/00_prepare_stock.py --package TB371FC_ZUI_16.0.474 --out stock

  --package : 7z 를 풀어서 나온 TB371FC_ZUI_16.0.474 폴더 (또는 그 안의 image 폴더)
  --out     : 결과를 둘 폴더 (여유 공간 약 13 GiB 필요)

Windows, macOS, Linux 모두 Python 3.8 이상이면 동작합니다. 외부 패키지는 필요 없습니다.
"""
import argparse
import os
import shutil
import sys
import xml.etree.ElementTree as ET

SUPER_SIZE = 12 * 1024 ** 3          # 이 기기의 super 파티션 크기 (12 GiB)
SECTOR = 4096
COPY_IMAGES = ["boot.img", "dtbo.img", "vbmeta.img", "vbmeta_system.img", "recovery.img"]
CHUNK = 8 * 1024 * 1024


def fail(msg):
    print("오류:", msg)
    sys.exit(1)


def find_image_dir(path):
    for cand in (path, os.path.join(path, "image")):
        if os.path.isfile(os.path.join(cand, "rawprogram0.xml")):
            return cand
    fail(f"{path} 안에서 rawprogram0.xml 을 찾지 못했습니다. 7z 를 푼 폴더를 지정하십시오.")


def super_chunks(image_dir):
    root = ET.parse(os.path.join(image_dir, "rawprogram0.xml")).getroot()
    chunks = []
    for p in root.iter("program"):
        if p.get("label") == "super" and p.get("filename"):
            chunks.append((p.get("filename"), int(p.get("start_sector")),
                           int(p.get("num_partition_sectors"))))
    if not chunks:
        fail("rawprogram0.xml 에 super 조각 정보가 없습니다.")
    chunks.sort(key=lambda c: c[1])
    return chunks


def build_super(image_dir, out_path):
    chunks = super_chunks(image_dir)
    base = chunks[0][1]  # 첫 조각(LP 메타데이터)이 파티션 시작 위치
    total = sum(n for _, _, n in chunks) * SECTOR
    end = max(s + n for _, s, n in chunks)
    if (end - base) * SECTOR > SUPER_SIZE:
        fail("조각이 super 크기(12 GiB)를 넘습니다. 다른 기기나 펌웨어의 패키지일 수 있습니다.")

    for name, _, n in chunks:
        p = os.path.join(image_dir, name)
        if not os.path.isfile(p):
            fail(f"{name} 이 없습니다.")
        if os.path.getsize(p) != n * SECTOR:
            fail(f"{name} 크기가 rawprogram0.xml 과 다릅니다. 압축 해제를 다시 하십시오.")

    print(f"super_stock.img 만드는 중 (조각 {len(chunks)}개, {total // 2**20} MiB) ...")
    tmp = out_path + ".part"
    done = 0
    with open(tmp, "wb") as w:
        w.truncate(SUPER_SIZE)  # 조각 사이 빈 공간은 0 으로 둡니다
        for name, start, _ in chunks:
            w.seek((start - base) * SECTOR)
            with open(os.path.join(image_dir, name), "rb") as r:
                while True:
                    buf = r.read(CHUNK)
                    if not buf:
                        break
                    w.write(buf)
                    done += len(buf)
                    sys.stdout.write(f"\r  {done * 100 // total:3d}%")
                    sys.stdout.flush()
    print()
    os.replace(tmp, out_path)


def main():
    ap = argparse.ArgumentParser(description="QFIL 패키지에서 fastboot 용 stock 이미지 준비")
    ap.add_argument("--package", required=True, help="7z 를 푼 TB371FC_ZUI_16.0.474 폴더")
    ap.add_argument("--out", required=True, help="결과 폴더")
    args = ap.parse_args()

    image_dir = find_image_dir(args.package)
    os.makedirs(args.out, exist_ok=True)

    free = shutil.disk_usage(os.path.abspath(args.out)).free
    if free < SUPER_SIZE + 300 * 2**20:
        fail(f"{args.out} 의 여유 공간이 부족합니다. 약 13 GiB 필요, 남은 {free // 2**30} GiB")

    for name in COPY_IMAGES:
        src = os.path.join(image_dir, name)
        if not os.path.isfile(src):
            fail(f"{name} 이 없습니다.")
        shutil.copyfile(src, os.path.join(args.out, name))
        print(f"복사: {name}")

    build_super(image_dir, os.path.join(args.out, "super_stock.img"))

    print(f"완료: {os.path.abspath(args.out)}")
    print("다음 단계: tools/04_flash_stock.sh --stock-dir <이 폴더의 Windows 경로>")


if __name__ == "__main__":
    main()
