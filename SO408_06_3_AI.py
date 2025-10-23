from datetime import datetime
from time import sleep
from warnings import filterwarnings

from gpiozero import LED, DistanceSensor
from icecream import ic
from picamera2 import Picamera2
from picamera2.encoders import H264Encoder

from SO408_05_TeachableMachine import classify_image

# 警告の抑止とログの設定
filterwarnings("ignore", module="gpiozero")
ic.configureOutput(
    prefix=lambda: f'{datetime.now().isoformat(timespec="milliseconds")}  '
)


# 検知の閾値
THRESHOLD = 30

# GPIOの設定
led = LED(4)
sensor = DistanceSensor(echo=13, trigger=5)

# カメラの設定
camera = Picamera2()
camera.start()

# 検知状態（True：検知状態、False：非検知状態）
status = False

# 無限ループ
while True:
    # 距離の取得
    d = sensor.distance * 100
    ic(d)
    if d < THRESHOLD:
        if status is False:
            # 静止画を撮影
            now = datetime.now().strftime("%Y%m%d%H%M%S")
            image_path = f"capture_{now}.jpg"
            camera.capture_file(f"capture_{now}.jpg")
            # 画像を判定する
            label, score = classify_image(image_path)
            print(label, score)
            # 人間の場合のみ、検知オン処理
            if label == "人間" and score > 80:
                # 検知状態
                status = True
                # LEDオン
                led.on()
                ic("ON")
                # 動画の撮影を開始する
                camera.start_recording(
                    H264Encoder(bitrate=10000000), f"video_{now}.h264"
                )
    else:
        if status is True:
            # 非検知状態
            status = False
            # 動画の撮影を停止
            camera.stop_recording()
            # LEDオフ
            led.off()
            ic("OFF")
    sleep(1)
