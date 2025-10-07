from datetime import datetime
from picamera2.encoders import H264Encoder
from picamera2 import Picamera2
from gpiozero import LED, DistanceSensor
from icecream import ic
from time import sleep
from warnings import filterwarnings

from keras.models import load_model  # TensorFlow is required for Keras to work
from PIL import Image, ImageOps  # Install pillow instead of PIL
import numpy as np


# 警告の抑止とログの設定
filterwarnings('ignore', module='gpiozero')
ic.configureOutput(prefix=lambda: f'{datetime.now().isoformat(timespec="milliseconds")}  ')


# 画像認識
def classify_picture(image_path):
    # Disable scientific notation for clarity
    np.set_printoptions(suppress=True)

    # Load the model
    model = load_model("keras_model.h5", compile=False)

    # Load the labels
    class_names = open("labels.txt", "r").readlines()

    # Create the array of the right shape to feed into the keras model
    # The 'length' or number of images you can put into the array is
    # determined by the first position in the shape tuple, in this case 1
    data = np.ndarray(shape=(1, 224, 224, 3), dtype=np.float32)

    # Replace this with the path to your image
    image = Image.open("images/cat.jpg").convert("RGB")

    # resizing the image to be at least 224x224 and then cropping from the center
    size = (224, 224)
    image = ImageOps.fit(image, size, Image.Resampling.LANCZOS)

    # turn the image into a numpy array
    image_array = np.asarray(image)

    # Normalize the image
    normalized_image_array = (image_array.astype(np.float32) / 127.5) - 1

    # Load the image into the array
    data[0] = normalized_image_array

    # Predicts the model
    prediction = model.predict(data)
    index = np.argmax(prediction)
    class_name = class_names[index]
    confidence_score = prediction[0][index]

    # Print prediction and confidence score
    return class_name[2:], confidence_score


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
        if status == False:
            # 静止画を撮影
            now = datetime.now().strftime('%Y%m%d%H%M%S')
            image_path = f'capture_{now}.jpg'
            camera.capture_file(f'capture_{now}.jpg')
            # 画像を判定する
            label, score = classify_picture(image_path)
            print(label, score)
            # 人間の場合のみ、検知オン処理
            if label == '人間' and score > 80:
                # 検知状態
                status = True
                # LEDオン
                led.on()
                ic('ON')
                # 動画の撮影を開始する
                camera.start_recording(H264Encoder(bitrate=10000000), f'video_{now}.h264')
    else:
        if status == True:
            # 非検知状態
            status = False
            # 動画の撮影を停止
            camera.stop_recording()
            # LEDオフ
            led.off()
            ic('OFF')
    sleep(1)
