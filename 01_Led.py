from datetime import datetime
from gpiozero import LED
from icecream import ic
from time import sleep
from warnings import filterwarnings

# 警告の抑止とログの設定
filterwarnings('ignore', module='gpiozero')
ic.configureOutput(prefix=lambda: f'{datetime.now().isoformat(timespec="milliseconds")}  ')

# GPIOの設定
led = LED(4)

# 無限ループ
while True:
    # LEDオン
    led.on()
    ic('ON')
    sleep(0.5)
    # LEDオフ
    led.off()
    ic('OFF')
    sleep(0.5)
