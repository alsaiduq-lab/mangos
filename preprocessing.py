#!/usr/bin/env python3
from PIL import Image, ImageEnhance, ImageOps
import sys
import numpy as np
import cv2

def preprocess_image(image_path):
    try:
        image = Image.open(image_path)
        grayscale_image = image.convert('L')

        open_cv_image = np.array(grayscale_image)

        adaptive_thresh_image = cv2.adaptiveThreshold(
            open_cv_image,
            255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY,
            11,
            2
        )

        result_image = Image.fromarray(adaptive_thresh_image)

        np_image = np.array(result_image)
        white_pixel_threshold = 250
        white_pixels = np.sum(np_image > white_pixel_threshold)
        total_pixels = np_image.size
        white_ratio = white_pixels / total_pixels

        if white_ratio < 0.5:
            enhancer = ImageEnhance.Contrast(result_image)
            result_image = enhancer.enhance(2)
        
        result_image.save(image_path)
    except Exception as e:
        print(f"Error processing image: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: preprocess_image.py <image_path>", file=sys.stderr)
        sys.exit(1)
    preprocess_image(sys.argv[1])

