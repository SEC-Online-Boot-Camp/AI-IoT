from datetime import datetime
from picamera2.encoders import H264Encoder
from picamera2 import Picamera2
from gpiozero import LED, Button
from icecream import ic
from time import sleep
from warnings import filterwarnings

# 警告の抑止とログの設定
filterwarnings('ignore', module='gpiozero')
ic.configureOutput(prefix=lambda: f'{datetime.now().isoformat(timespec="milliseconds")}  ')


# GPIOの設定
led = LED(4)
button = Button(21)

# カメラの設定
camera = Picamera2()
camera.start()

# 検知状態（True：検知状態、False：非検知状態）
status = False

# 無限ループ
while True:
    # ボタンが押されるまで待機
    button.wait_for_press()
    if status == False:
        # 検知状態
        status = True
        # LEDを点灯
        led.on()
        ic('LED ON')
        # 静止画を撮影
        now = datetime.now().strftime('%Y%m%d%H%M%S')
        ic(now)
        camera.capture_file(f'capture_{now}.jpg')
        # 動画の撮影を開始する
        camera.start_recording(H264Encoder(bitrate=10000000), f'video_{now}.h264')
    else:
        # 非検知状態
        status = False
        # 動画の撮影を停止
        camera.stop_preview()
        camera.stop_recording()
        # LEDを消灯
        led.off()
        ic('LED OFF')
    
    # ボタンが離されるまで待機
    button.wait_for_release()
    sleep(1)
