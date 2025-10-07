from datetime import datetime
from gpiozero import DistanceSensor
from icecream import ic
from time import sleep
from warnings import filterwarnings

# 警告の抑止とログの設定
filterwarnings('ignore', module='gpiozero')
ic.configureOutput(prefix=lambda: f'{datetime.now().isoformat(timespec="milliseconds")}  ')

# GPIOの設定
sensor = DistanceSensor(echo=13, trigger=5)

# 無限ループ
while True:
    # 距離の取得
    d = sensor.distance * 100
    ic(d)
    sleep(1)
