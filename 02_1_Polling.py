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
    # ボタン電源が押されているか確認
    if button.is_pressed:
        led.on()
        ic('ON')
    else:
        led.off()
        ic('OFF')
    sleep(0.5)

