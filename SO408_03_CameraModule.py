from datetime import datetime
from time import sleep
from warnings import filterwarnings

from icecream import ic
from picamera2 import Picamera2

# 警告の抑止とログの設定
filterwarnings("ignore", module="gpiozero")
ic.configureOutput(
    prefix=lambda: f'{datetime.now().isoformat(timespec="milliseconds")}  '
)

# カメラの開始
camera = Picamera2()
camera.start()

# 10回繰り返し
for _ in range(10):
    now = datetime.now().strftime("%Y%m%d%H%M%S")
    ic(now)
    camera.capture_file(f"capture_{now}.jpg")
    sleep(1)

# カメラの終了
camera.close()
