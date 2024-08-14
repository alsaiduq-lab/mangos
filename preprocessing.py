#!/usr/bin/env python3
from PIL import Image, ImageEnhance
import sys
import numpy as np
import cv2

def is_text_dark(image):
    gray = np.array(image.convert('L'))
    avg_brightness = np.mean(gray)
    return avg_brightness > 127

def preprocess_image(image_path):
    try:
        image = Image.open(image_path)
        grayscale_image = image.convert('L')
        text_is_dark = is_text_dark(image)
        open_cv_image = np.array(grayscale_image)
        if text_is_dark:
            adaptive_thresh_image = cv2.adaptiveThreshold(
                open_cv_image,
                255,
                cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                cv2.THRESH_BINARY,
                11,
                2
            )
        else:
            adaptive_thresh_image = cv2.adaptiveThreshold(
                open_cv_image,
                255,
                cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                cv2.THRESH_BINARY_INV,
                11,
                2
            )

        result_image = Image.fromarray(adaptive_thresh_image)
        kernel = np.ones((3,3), np.uint8)
        morph_image = cv2.morphologyEx(adaptive_thresh_image, cv2.MORPH_CLOSE, kernel, iterations=1)
        result_image = Image.fromarray(morph_image)
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
        print("Usage: preprocessing.py <image_path>", file=sys.stderr)
        sys.exit(1)
    preprocess_image(sys.argv[1])
