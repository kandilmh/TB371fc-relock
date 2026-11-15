# TB371FC Bootloader Relock

[한국어](README.md) | **English**

How to **return a Lenovo Xiaoxin Pad Pro 12.7 (TB371FC) to stock ZUI and lock the bootloader again**.
This is the exact process that worked on a real device on 2026-11-15, with scripts for each step.

- Result: `locked / green / verity enforcing / Widevine L1`
- Time: 1–2 hours to prepare (including downloads), about 30 minutes on the device

> The scripts print their messages in Korean. Each step below says what you should see.

---

## ⚠️ Read this first

1. **Never lock while a custom ROM (Lunaris, etc.) or a modified boot image is installed.** The tablet will not boot.
   Use this guide only to lock **after reinstalling the stock ROM** (step 4 installs it).
2. **All data on the tablet will be erased.** Copy photos and files to a PC or cloud first.
3. Do **not** delete `sdd_full_backup.bin` (32 MiB, made in step 1) until you are done. It is the only way back if something goes wrong.
4. Unlocking again later will erase your data again.

## Why doesn't a plain lock work?

On this device, `fastboot flashing lock` fails with:

```
FAILED (remote: 'Prc device unlocked, don't allow lock')
```

Before locking, the bootloader checks a small area called `proinfo`. This device does not have one.
So steps 1–3 **create the `proinfo` area**, and only then do we lock.
The full analysis is in [`docs/PROCEDURE.md`](docs/PROCEDURE.md) (Korean).

## Terms

| Term | Meaning |
|---|---|
| adb | Tool for sending commands from the PC to a running tablet |
| fastboot | Tool for flashing images and locking, used while the tablet is in bootloader mode |
| Bootloader mode | The screen before Android starts. fastboot commands only work here |
| Root (Magisk) | Admin access (`su`). Steps 1 and 3 need it to read and write the storage area directly |
| WSL | Runs Linux (Ubuntu) inside Windows. The scripts run in WSL |

---

## What you need

| Item | Notes |
|---|---|
| Windows PC + WSL (Ubuntu) | Scripts run in WSL; they call the Windows adb/fastboot |
| USB cable | One that carries data, not charge-only |
| platform-tools | Google's adb/fastboot, unzipped to `C:\adb` |
| Rooted tablet | Rooted with Magisk. Any current ROM is fine |
| Stock firmware | ZUI 16.0.474, from this repository's [release](https://github.com/kandilmh/TB371fc-relock/releases/tag/stock-zui-16.0.474) |
| Free disk space | About 30 GB on drive C |

### 1) Install WSL

Open PowerShell **as administrator** and run the command below. Reboot, then set an Ubuntu user name and password.

```powershell
wsl --install
```

In the Ubuntu window (Start menu → Ubuntu), install the tools:

```bash
sudo apt update && sudo apt install -y git python3 p7zip-full
```

### 2) Install platform-tools

1. Download the Windows version of [platform-tools](https://developer.android.com/tools/releases/platform-tools).
2. Unzip it so that you have `C:\adb\adb.exe` and `C:\adb\fastboot.exe`. The scripts look there automatically.
   - If you put them elsewhere, set them before running: `export ADB=/mnt/d/tools/adb.exe FB=/mnt/d/tools/fastboot.exe`

### 3) Get this repository

In the Ubuntu window:

```bash
cd ~
git clone https://github.com/kandilmh/TB371fc-relock.git
cd TB371fc-relock
```

**Run every command below from this folder (`~/TB371fc-relock`).**

### 4) Download and prepare the stock firmware

1. From the [release](https://github.com/kandilmh/TB371fc-relock/releases/tag/stock-zui-16.0.474), download these four files into `C:\tb371\download`:
   `TB371FC.7z.000`, `TB371FC.7z.001`, `TB371FC.7z.002`, `join_stock.py`
2. Join the parts. The script checks the sha256 of every part and of the result.

   ```bash
   python3 /mnt/c/tb371/download/join_stock.py
   ```

   It worked if you see `완료` (done) and `sha256 ... 일치` (match).
3. Extract the archive (takes a few minutes):

   ```bash
   7z x /mnt/c/tb371/download/TB371FC.7z -o/mnt/c/tb371/download
   ```

4. Build the images for fastboot. This joins the six `super` pieces in the firmware into one file and copies the other images.

   ```bash
   python3 tools/00_prepare_stock.py \
     --package /mnt/c/tb371/download/TB371FC_ZUI_16.0.474 \
     --out /mnt/c/tb371/stock
   ```

   You should end up with six images in `C:\tb371\stock`: `super_stock.img`, `boot.img`, `dtbo.img`, `vbmeta.img`, `vbmeta_system.img`, `recovery.img`.

### 5) Check the connection

1. On the tablet, open **Settings → About tablet** and tap **Build number** 7 times to enable Developer options.
2. Turn on **Settings → System → Developer options → USB debugging**.
3. Connect the USB cable and tap **Allow** on the "Allow USB debugging" prompt.
4. Check the connection and root:

   ```bash
   /mnt/c/adb/adb.exe devices          # your device should show "device"
   /mnt/c/adb/adb.exe shell su -c id   # should show uid=0(root)
   ```

   The first `su -c id` shows a Magisk prompt on the tablet. Tap **Allow**.

---

## Overview

| Step | Tablet state | Run | What it does |
|---|---|---|---|
| 1 | Booted (adb) | `tools/01_backup_sdd.sh` | Back up the storage area (sdd, 32 MiB) |
| 2 | Any | `tools/02_make_proinfo.py` | Make a new image with `proinfo` added |
| 3 | Booted (adb) | `tools/03_apply_sdd.sh` | Write it to the tablet and read it back to compare |
| 4 | Bootloader mode | `tools/04_flash_stock.sh` | Install stock ROM + wipe data |
| 5 | Bootloader mode | `tools/05_lock.sh` | Lock the bootloader |
| 6 | Booted (adb) | `tools/06_verify.sh` | Final check |

Every script writes a log to the `logs/` folder.

## Step 1. Backup

```bash
tools/01_backup_sdd.sh
```

- Creates `work/sdd_full_backup.bin` (32 MiB) and its sha256.
- **Copy it somewhere else on the PC as well** (for example `C:\tb371\backup`):

  ```bash
  mkdir -p /mnt/c/tb371/backup && cp work/sdd_full_backup.bin* /mnt/c/tb371/backup/
  ```

## Step 2. Build the proinfo image

```bash
python3 tools/02_make_proinfo.py --input work/sdd_full_backup.bin --output work/sdd_new.bin
```

- Runs on the PC only; the tablet is not touched.
- Only five places differ from the original: four GPT table blocks and the `proinfo` content.

## Step 3. Write it to the tablet

```bash
tools/03_apply_sdd.sh
```

- Type `yes` at the prompt.
- It must end with **`READBACK MATCH`**. Anything else: see [Troubleshooting](#troubleshooting).
- When it is done, **reboot the tablet** and check that `proinfo` exists:

  ```bash
  /mnt/c/adb/adb.exe reboot
  # after it boots
  /mnt/c/adb/adb.exe shell ls -l /dev/block/by-name/proinfo   # success if it shows ... -> /dev/block/sdd5
  ```

## Step 4. Install the stock ROM

1. Reboot into bootloader mode:

   ```bash
   /mnt/c/adb/adb.exe reboot bootloader
   ```

2. Check that the tablet is visible:

   ```bash
   /mnt/c/adb/fastboot.exe devices    # your device should show "fastboot"
   ```

3. Flash. Give the folder as a **Windows path**:

   ```bash
   tools/04_flash_stock.sh --stock-dir 'C:\tb371\stock'
   ```

- Type `yes` at the prompt.
- Flashing `super` (12 GiB) takes 10–20 minutes. **Do not unplug the cable.**
- At the end it wipes data and the tablet reboots by itself.

## Step 5. Lock

1. When stock ZUI starts, skip through the setup and turn on USB debugging again (items 1–3 of [Check the connection](#5-check-the-connection)).
2. Enter bootloader mode and lock:

   ```bash
   /mnt/c/adb/adb.exe reboot bootloader
   tools/05_lock.sh
   ```

3. Type `yes` at the prompt.
4. A lock confirmation menu appears **on the tablet**. **Select Lock with the volume keys and confirm with the power key.**
5. The tablet wipes itself and reboots.

## Step 6. Verify

After it boots, finish setup, turn on USB debugging again, and run:

```bash
tools/06_verify.sh
```

You are done when every line ends with `OK`.

| Item | Expected |
|---|---|
| `ro.boot.flash.locked` | 1 |
| `ro.boot.verifiedbootstate` | green |
| `ro.boot.vbmeta.device_state` | locked |
| `ro.boot.secureboot` | 1 |
| `ro.boot.veritymode` | enforcing |
| `/dev/block/by-name/proinfo` | `-> sdd5` |
| `sys.lenovo.widevine_security_level` | L1 |

You can also check "Device is certified" in Play Store → Settings → About.

---

## Troubleshooting

**`adb devices` shows nothing, or `unauthorized`**
Check that USB debugging is on and that you tapped Allow on the tablet. The cable may be charge-only.

**`dd 실패 — 루팅(su) 상태인지 확인` (dd failed — check root)**
The tablet is not rooted with Magisk, or the Magisk prompt was denied. Check with `adb shell su -c id` first.
The scripts use Magisk's `su` (`/debug_ramdisk/su`). Other root tools such as KernelSU were not tested.

**`fastboot devices` shows nothing in bootloader mode**
Windows may be missing the USB driver. In Device Manager, install the Google USB Driver for the device with a warning mark.

**`Prc device unlocked, don't allow lock`**
`proinfo` is missing, or the tablet was not rebooted after writing it. Redo step 3, reboot, then lock.

**`READBACK MISMATCH`**
The write partly failed. Restore the backup as below, then redo step 3.

**Restoring the backup** (tablet booted and rooted)

```bash
ADB=/mnt/c/adb/adb.exe
"$ADB" push work/sdd_full_backup.bin /data/local/tmp/sdd_orig.bin
"$ADB" shell "su -c 'dd if=/data/local/tmp/sdd_orig.bin of=/dev/block/sdd bs=4096 && sync'"
```

**Reflashing with QFIL**
The package's `rawprogram3.xml` removes `proinfo`. Replace the two files of the same name in the package's `image/` folder with the ones in `qfil_gpt/` before running QFIL.

---

## Folder layout

```
TB371fc-relock/
├── README.md / README.en.md   Guide (Korean / English)
├── docs/PROCEDURE.md          Background, analysis, measurements (Korean)
├── tools/
│   ├── 00_prepare_stock.py    Prepare fastboot images from the firmware (join super pieces)
│   ├── 01_backup_sdd.sh       Back up sdd
│   ├── 02_make_proinfo.py     Build the image with proinfo
│   ├── 03_apply_sdd.sh        Write + compare
│   ├── 04_flash_stock.sh      Install stock ROM
│   ├── 05_lock.sh             Lock
│   ├── 06_verify.sh           Verify
│   └── lib.sh                 Shared functions
├── qfil_gpt/                  GPT files to swap in when reflashing with QFIL
└── work/, logs/               Backups, generated images, logs (not in the repo)
```

## Not verified

- Whether this works on firmware other than ZUI 16.0.474
- Receiving and installing OTA updates after locking
- QFIL with the replacement GPT (files prepared only)
- Environments other than Windows + WSL (the scripts assume Windows adb/fastboot and Windows paths)

## Notes

- Personal notes; not affiliated with Lenovo or the Lunaris team.
- This changes the state of your device. Use at your own risk.
