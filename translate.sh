#!/bin/bash

DEBUG_LOG="/tmp/mangaocr_translate_debug.log"
exec 3>&2
exec 2>>"$DEBUG_LOG"

INSTALL_DIR="$HOME/.local/share/mangos"
VENV_DIR="$INSTALL_DIR/venv"
CONFIG_FILE="$INSTALL_DIR/config.yaml"

MODEL="gpt-4o-mini"
API_BASE="http://localhost:11434"
API_KEY=""
DEVICE="cpu"
WAYBAR_MODE=false
API_TYPE="ollama"

show_help() {
    echo "Usage: mangos [OPTIONS]"
    echo "Translate Japanese text from screenshots using OCR and machine translation."
    echo
    echo "Options:"
    echo "  -h, --help                  Show this help message and exit"
    echo "  -m, --model MODEL           Specify the translation model to use"
    echo "  -a, --api API_BASE          Specify the API base URL"
    echo "  -k, --key API_KEY           Specify the API key (optional)"
    echo "  -d, --device DEVICE         Specify the device to use (cpu or cuda)"
    echo "  -t, --type API_TYPE         Specify the API type (ollama or openai)"
    echo "  -v, --version               Show version information"
    echo
    echo "Examples:"
    echo "  mangos                              Take a screenshot and translate"
    echo "  mangos -m gpt-3.5-turbo -t openai   Use OpenAI API for translation"
    echo "  mangos -a http://localhost:8080     Use a different API endpoint"
    echo "  mangos -k myapikey                  Pass the API key"
    echo "  mangos -d cuda                      Use CUDA (GPU) for processing"
}

show_version() {
    echo "mangos version 0.0.1"
}

update_config() {
    cat > "$CONFIG_FILE" << EOL
model: $MODEL
api_base: $API_BASE
api_key: $API_KEY
device: $DEVICE
api_type: $API_TYPE
EOL
}

read_config() {
    if [ -f "$CONFIG_FILE" ]; then
        MODEL=$(grep "model:" "$CONFIG_FILE" | awk '{print $2}')
        API_BASE=$(grep "api_base:" "$CONFIG_FILE" | awk '{print $2}')
        API_KEY=$(grep "api_key:" "$CONFIG_FILE" | awk '{print $2}')
        DEVICE=$(grep "device:" "$CONFIG_FILE" | awk '{print $2}')
        API_TYPE=$(grep "api_type:" "$CONFIG_FILE" | awk '{print $2}')
    else
        update_config
    fi
}

read_config

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            show_help
            exit 0
            ;;
        -m|--model)
            MODEL="$2"
            echo "Model set: $MODEL" >> "$DEBUG_LOG"
            shift 2
            ;;
        -a|--api)
            API_BASE="$2"
            echo "API Base set: $API_BASE" >> "$DEBUG_LOG"
            shift 2
            ;;
        -k|--key)
            API_KEY="$2"
            echo "API Key set: ${API_KEY:0:5}..." >> "$DEBUG_LOG"
            shift 2
            ;;
        -d|--device)
            DEVICE="$2"
            if [[ "$DEVICE" != "cpu" && "$DEVICE" != "cuda" ]]; then
                echo "Error: Device must be either 'cpu' or 'cuda'" >&2
                exit 1
            fi
            echo "Device set: $DEVICE" >> "$DEBUG_LOG"
            shift 2
            ;;
        -t|--type)
            API_TYPE="$2"
            if [[ "$API_TYPE" != "ollama" && "$API_TYPE" != "openai" ]]; then
                echo "Error: API type must be either 'ollama' or 'openai'" >&2
                exit 1
            fi
            echo "API Type set: $API_TYPE" >> "$DEBUG_LOG"
            shift 2
            ;;
        -w|--waybar)
            WAYBAR_MODE=true
            echo "Waybar mode enabled" >> "$DEBUG_LOG"
            shift
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

echo "Final configuration:" >> "$DEBUG_LOG"
echo "Model: $MODEL" >> "$DEBUG_LOG"
echo "API Base: $API_BASE" >> "$DEBUG_LOG"
echo "API Key: ${API_KEY:0:5}..." >> "$DEBUG_LOG"
echo "Device: $DEVICE" >> "$DEBUG_LOG"
echo "API Type: $API_TYPE" >> "$DEBUG_LOG"

cleanup() {
    if [ -n "$SCREENSHOT_PATH" ] && [ -f "$SCREENSHOT_PATH" ]; then
        rm -f "$SCREENSHOT_PATH"
        echo "Deleted screenshot: $SCREENSHOT_PATH" >> "$DEBUG_LOG"
    fi
}

take_screenshot() {
    mkdir -p "$HOME/Pictures/waybar_output"
    SCREENSHOT_FILENAME="mangos_screenshot_$(date +%s%N).png"
    SCREENSHOT_PATH="$HOME/Pictures/$SCREENSHOT_FILENAME"
    echo "Taking screenshot: $SCREENSHOT_PATH" >> "$DEBUG_LOG"

    if grim -g "$(slurp)" "$SCREENSHOT_PATH"; then
        echo "Screenshot saved: $SCREENSHOT_PATH" >> "$DEBUG_LOG"
        echo "$SCREENSHOT_PATH"
    else
        echo "Error: Screenshot failed" >> "$DEBUG_LOG"
        return 1
    fi
}

preprocess_image() {
    source "$VENV_DIR/bin/activate"
    python - <<EOF
from PIL import Image, ImageEnhance
import sys
image_path = sys.argv[1]
image = Image.open(image_path)
image = image.convert('L')
enhancer = ImageEnhance.Contrast(image)
image = enhancer.enhance(2)
image.save(image_path)
EOF
    deactivate
}

perform_ocr() {
    preprocess_image "$1"
    source "$VENV_DIR/bin/activate"
    if RESULT=$(python "$INSTALL_DIR/ocr.py" ocr "$1" --device "$DEVICE"); then
        echo "$RESULT"
    else
        echo "Error: OCR failed" >> "$DEBUG_LOG"
        return 1
    fi
    deactivate
}

translate_text() {
    ESCAPED_TEXT=$(echo "$1" | sed 's/"/\\"/g; s/\n/\\n/g')
    echo "Attempting to translate: $ESCAPED_TEXT" >> "$DEBUG_LOG"
    HEADERS=(-H "Content-Type: application/json")
    if [ -n "$API_KEY" ]; then
        HEADERS+=(-H "Authorization: Bearer $API_KEY")
    fi

    if [ "$API_TYPE" = "ollama" ]; then
        ENDPOINT="$API_BASE/api/generate"
        DATA='{
            "model": "'"$MODEL"'",
            "prompt": "Translate the following Japanese text to English:\n\n\"'"$ESCAPED_TEXT"'\"\n\nInstructions:\n1. Provide only the English translation.\n2. Do not include any explanations or notes.\n3. If the text is incomplete, translate what is available.\n4. Preserve the original meaning as closely as possible Do not write thoughts or anything else but the translation.\n\nTranslation:"
        }'
    else
        ENDPOINT="$API_BASE/chat/completions"
        DATA='{
            "model": "'"$MODEL"'",
            "messages": [
                {"role": "system", "content": "You are a translator. Translate the given Japanese text to English accurately and concisely."},
                {"role": "user", "content": "Translate the following Japanese text to English:\n\n\"'"$ESCAPED_TEXT"'\"\n\nInstructions:\n1. Provide only the English translation.\n2. Do not include any explanations or notes.\n3. If the text is incomplete, translate what is available.\n4. Preserve the original meaning as closely as possible."}
            ]
        }'
    fi
    echo "Headers: ${HEADERS[@]}" >> "$DEBUG_LOG"
    echo "Endpoint: $ENDPOINT" >> "$DEBUG_LOG"

    CURL_OUTPUT=$(curl -s -w "\n%{http_code}" "${HEADERS[@]}" -X POST "$ENDPOINT" -d "$DATA")

    HTTP_STATUS=$(echo "$CURL_OUTPUT" | tail -n1)
    RESPONSE_BODY=$(echo "$CURL_OUTPUT" | sed '$d')

    echo "API HTTP Status: $HTTP_STATUS" >> "$DEBUG_LOG"
    echo "API Response: $RESPONSE_BODY" >> "$DEBUG_LOG"

    if [ "$HTTP_STATUS" -eq 200 ]; then
        if [ "$API_TYPE" = "ollama" ]; then
            TRANSLATION=$(echo "$RESPONSE_BODY" | jq -r '.response' | tr -d '\n')
        else
            TRANSLATION=$(echo "$RESPONSE_BODY" | jq -r '.choices[0].message.content' | tr -d '\n')
        fi
        if [ -z "$TRANSLATION" ]; then
            echo "Error: Empty translation received from API" >> "$DEBUG_LOG"
            return 1
        fi
        echo "$TRANSLATION"
        update_config
    else
        echo "Error: API call failed with status $HTTP_STATUS" >> "$DEBUG_LOG"
        echo "Response body: $RESPONSE_BODY" >> "$DEBUG_LOG"
        return 1
    fi
}

waybar_output() {
    local status="$1"
    local message="$2"
    echo "{\"text\": \"翻訳\", \"tooltip\": \"$message\", \"class\": \"custom-mangaocr-translate $status\"}"
}

perform_translation() {
    SCREENSHOT=$(take_screenshot)
    if [ $? -eq 0 ]; then
        OCR_RESULT=$(perform_ocr "$SCREENSHOT")
        if [ $? -eq 0 ]; then
            TRANSLATION=$(translate_text "$OCR_RESULT")
            if [ $? -eq 0 ]; then
                OUTPUT="Original: $OCR_RESULT\nTranslation: $TRANSLATION"
                echo -e "$OUTPUT" | wl-copy
                echo "$OUTPUT"
                return 0
            else
                echo "Translation failed"
                return 1
            fi
        else
            echo "OCR failed"
            return 1
        fi
    else
        echo "Screenshot failed"
        return 1
    fi
}

main() {
    if $WAYBAR_MODE; then
        if [ "$1" = "click" ]; then
            echo "Starting translation process" >> "$DEBUG_LOG"
            RESULT=$(perform_translation)
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                zenity --info --title="Translation Result" --text="$RESULT" --width=400 --height=200
                waybar_output "" "$RESULT"
            else
                waybar_output "error" "$RESULT"
            fi
        else
            waybar_output "" "Click to translate"
        fi
    else
        echo "Starting translation process" >> "$DEBUG_LOG"
        RESULT=$(perform_translation)
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
            zenity --info --title="Translation Result" --text="$RESULT" --width=400 --height=200
            echo -e "$RESULT"
        else
            echo "$RESULT" >&2
        fi
    fi
    cleanup
}

main "$@"
exec 2>&3
