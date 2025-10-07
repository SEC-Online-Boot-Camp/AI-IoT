#!/usr/bin/env python3
import argparse
import os
import sys

import cv2
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("--model", "-m", default="model_unquant.tflite")
ap.add_argument("--labels", "-l", default="labels.txt")
ap.add_argument("--image", "-i", default="images/lion.jpg")
args = ap.parse_args()

if not os.path.exists(args.model):
    sys.exit(f"model not found: {args.model}")
if not os.path.exists(args.labels):
    sys.exit(f"labels not found: {args.labels}")

net = cv2.dnn.readNetFromTFLite(args.model)

img = cv2.imread(args.image)
if img is None:
    sys.exit(f"image not found or unreadable: {args.image}")

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
with open(args.labels, "r", encoding="utf-8") as f:
    labels = [line.strip() for line in f]

print("Class:", labels[idx])
print("Score:", float(probs[idx]))
