import sys
import logging
from manga_ocr import MangaOcr

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def initialize_ocr():
    logging.info("Initializing OCR model")
    try:
        mocr = MangaOcr(force_cpu=True)
        logging.info("OCR model initialized successfully")
        return mocr
    except Exception as e:
        logging.error(f"Error initializing OCR model: {e}")
        return None

def perform_ocr(mocr, image_path):
    logging.info(f"Performing OCR on image: {image_path}")
    try:
        result = mocr(image_path)
        logging.info(f"OCR result: {result}")
        return result
    except Exception as e:
        logging.error(f"Error performing OCR: {e}")
        return None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logging.error("Insufficient arguments")
        sys.exit(1)

    action = sys.argv[1]
    if action == "init":
        mocr = initialize_ocr()
        if mocr:
            print("OCR model initialized")
        else:
            print("Error: OCR model initialization failed", file=sys.stderr)
    elif action == "ocr":
        if len(sys.argv) < 3:
            logging.error("Image path not provided")
            sys.exit(1)
        mocr = initialize_ocr()
        if mocr:
            result = perform_ocr(mocr, sys.argv[2])
            if result:
                print(result)
            else:
                print("Error: OCR failed", file=sys.stderr)
        else:
            print("Error: OCR model initialization failed", file=sys.stderr)
    else:
        logging.error(f"Unknown action: {action}")
        sys.exit(1)
