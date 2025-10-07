from datetime import datetime
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

# 無限ループ
while True:
    # ボタンが押されるまで待機
    button.wait_for_press()
    led.on()
    ic('ON')
    # ボタンが離されるまで待機
    button.wait_for_release()
    led.off()
    ic('OFF')
