import argparse

import cv2
import numpy as np


# 画像ファイルを分類する関数
def classify_image(image_path, model_path=None, labels_path=None, threshold=None):
    if model_path is None:
        model_path = "model_unquant.tflite"
    if labels_path is None:
        labels_path = "labels.txt"
    if threshold is None:
        threshold = 0.75

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
    score = float(probs[idx])
    if score < threshold:
        return "Unknown", score
    return labels[idx], score


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", "-m")
    ap.add_argument("--labels", "-l")
    ap.add_argument("--image", "-i", required=True)
    ap.add_argument("--threshold", "-t", type=float)
    args = ap.parse_args()
    class_name, score = classify_image(
        args.image, args.model, args.labels, args.threshold
    )
    print("Class:", class_name)
    print("Score:", score)
