import argparse
import os

import cv2
import numpy as np


# 画像ファイルを分類する関数
def classify_image(model_path, labels_path, image_path):
    net = cv2.dnn.readNetFromTFLite(model_path)
    labels = []
    with open(labels_path, "r", encoding="utf-8") as f:
        labels = [line.strip() for line in f]
    img = cv2.imread(image_path)
    blob = cv2.dnn.blobFromImage(
        img,
        scalefactor=1 / 127.5,
        size=(224, 224),
        mean=(127.5, 127.5, 127.5),
        swapRB=True,
        crop=False,
    )
    net.setInput(blob)
    probs = net.forward()[0]
    idx = int(np.argmax(probs))
    return labels[idx], float(probs[idx])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", "-m", default="model_unquant.tflite")
    ap.add_argument("--labels", "-l", default="labels.txt")
    ap.add_argument("--image", "-i")
    args = ap.parse_args()
    class_name, score = classify_image(args.model, args.labels, args.image)
    print("Class:", class_name)
    print("Score:", score)
