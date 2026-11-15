QFIL 재플래싱용 GPT 교체 파일
==============================

이 폴더의 두 파일은 proinfo 항목이 들어간 sdd(LUN3) GPT 입니다.
QFIL 패키지의 `image/` 폴더에 같은 이름으로 넣어 교체하십시오.

  gpt_main3.bin    24576 bytes  (주 GPT)
  gpt_backup3.bin  20480 bytes  (백업 GPT)

교체하지 않고 QFIL 을 그대로 실행하면 rawprogram3.xml 이 LUN3 의 GPT 를
원래대로 덮어써서 proinfo 가 사라집니다. 그러면 `fastboot flashing lock` 이
다시 다음 오류로 실패합니다.

  FAILED (remote: 'Prc device unlocked, don't allow lock')

원본(교체 전) 파일은 백업해 두십시오. 되돌릴 때 필요합니다.
