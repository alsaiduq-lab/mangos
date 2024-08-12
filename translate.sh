#!/bin/bash

set -euo pipefail

DEBUG_LOG="/tmp/mangos_debug.log"
VERBOSITY=1
GUI_MODE=false

INSTALL_DIR="$HOME/.local/share/mangos"
VENV_DIR="$INSTALL_DIR/venv"
CONFIG_FILE="$INSTALL_DIR/config.yaml"

declare -A CONFIG=(
    [MODEL]="llama3.1"
    [API_BASE]="http://localhost:11434"
    [API_KEY]=""
    [DEVICE]="cpu"
    [API_TYPE]="ollama"
)

WAYBAR_MODE=false
SCREENSHOT_PATH=""

show_help() {
    cat << EOF
Usage: mangos [OPTIONS]
Translate Japanese text from screenshots using OCR and machine translation.

Options:
  -h, --help                  Show this help message and exit
  -m, --model MODEL           Specify the translation model to use
  -a, --api API_BASE          Specify the API base URL
  -k, --key API_KEY           Specify the API key (optional)
  -d, --device DEVICE         Specify the device to use (cpu or cuda)
  -t, --type API_TYPE         Specify the API type (ollama, openai, or other)
  -V, --version               Show version information
  -q, --quiet                 Suppress all output except errors
  -v, --verbose               Show verbose output

Examples:
  mangos                              Take a screenshot and translate
  mangos -m gpt-3.5-turbo -t openai   Use OpenAI API for translation
  mangos -a http://localhost:8080     Use a different API endpoint
  mangos -k myapikey                  Pass the API key
  mangos -d cuda                      Use CUDA (GPU) for processing
EOF
}

show_version() {
    echo "mangos version 0.0.2"
}

update_config() {
    local config_content=""
    for key in "${!CONFIG[@]}"; do
        config_content+="${key,,}: ${CONFIG[$key]}\n"
    done
    echo -e "$config_content" > "$CONFIG_FILE"
}

read_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS=': ' read -r key value; do
            key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
            if [[ -n "$key" && -n "$value" ]]; then
                CONFIG[$key]="$value"
            fi
        done < "$CONFIG_FILE"
    else
        update_config
    fi
}

validate_config() {
    local required_fields=("MODEL" "API_BASE" "DEVICE" "API_TYPE")
    for field in "${required_fields[@]}"; do
        if [[ -z "${CONFIG[$field]}" ]]; then
            log_error "Missing required configuration: $field"
            exit 1
        fi
    done

    if [[ "${CONFIG[API_TYPE]}" == "openai" && -z "${CONFIG[API_KEY]}" ]]; then
        log_error "API_KEY is required for OpenAI API"
        exit 1
    fi
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -m|--model)
                CONFIG[MODEL]="$2"
                shift 2
                ;;
            -a|--api)
                CONFIG[API_BASE]="$2"
                shift 2
                ;;
            -k|--key)
                CONFIG[API_KEY]="$2"
                shift 2
                ;;
            -d|--device)
                if [[ "$2" != "cpu" && "$2" != "cuda" ]]; then
                    log_error "Error: Device must be either 'cpu' or 'cuda'"
                    exit 1
                fi
                CONFIG[DEVICE]="$2"
                shift 2
                ;;
            -t|--type)
                CONFIG[API_TYPE]="$2"
                shift 2
                ;;
            -w|--waybar)
                WAYBAR_MODE=true
                GUI_MODE=true
                shift
                ;;
            -V|--version)
                show_version
                exit 0
                ;;
            -q|--quiet)
                VERBOSITY=0
                shift
                ;;
            -v|--verbose)
                VERBOSITY=2
                shift
                ;;
            -g|--gui)
                GUI_MODE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

log_debug() {
    if [[ $VERBOSITY -ge 2 ]]; then
        echo "[DEBUG] $1" >&2
    fi
    echo "[DEBUG][$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEBUG_LOG"
}

log_info() {
    if [[ $VERBOSITY -ge 1 ]]; then
        echo "[INFO] $1" >&2
    fi
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEBUG_LOG"
}

log_error() {
    echo "[ERROR] $1" >&2
    echo "[ERROR][$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEBUG_LOG"
}

cleanup() {
    if [[ -n "$SCREENSHOT_PATH" && -f "$SCREENSHOT_PATH" ]]; then
        rm -f "$SCREENSHOT_PATH"
        log_debug "Deleted screenshot: $SCREENSHOT_PATH"
    fi
    jobs -p | xargs -r kill
    log_debug "Cleaned up background processes"
}

take_screenshot() {
    SCREENSHOT_PATH=$(mktemp /tmp/mangos_screenshot_XXXXXX.png)
    log_debug "Taking screenshot: $SCREENSHOT_PATH"

    if grim -g "$(slurp)" "$SCREENSHOT_PATH"; then
        log_debug "Screenshot saved: $SCREENSHOT_PATH"
        echo "$SCREENSHOT_PATH"
    else
        log_error "Screenshot failed"
        rm -f "$SCREENSHOT_PATH"
        return 1
    fi
}

preprocess_image() {
    if [ $# -eq 0 ]; then
        return 1
    fi
    source "$VENV_DIR/bin/activate"
    python "$INSTALL_DIR/preprocessing.py" "$1"
    deactivate
}

perform_ocr() {
    local image_path="$1"
    if ! preprocess_image "$image_path"; then
        log_error "Image preprocessing failed, skipping OCR"
        return 1
    fi
    source "$VENV_DIR/bin/activate"
    if RESULT=$(python "$INSTALL_DIR/ocr.py" ocr "$image_path" --device "${CONFIG[DEVICE]}" 2>/dev/null); then
        RESULT=$(echo "$RESULT" | grep -v "^Image processed successfully:" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [ -z "$RESULT" ]; then
            log_error "OCR result is empty"
            return 1
        fi
        echo "$RESULT"
    else
        log_error "OCR failed"
        return 1
    fi
    deactivate
}


translate_text_ollama() {
    local escaped_text="$1"
    local endpoint="${CONFIG[API_BASE]}/api/generate"
    local data=$(jq -n \
        --arg model "${CONFIG[MODEL]}" \
        --arg text "$escaped_text" \
        '{model: $model, prompt: "Translate the following Japanese text to English:\n\n\($text)\n\nInstructions:\n1. Provide only the English translation.\n2. Do not include any explanations or notes.\n3. If the text is incomplete, translate what is available.\n4. Preserve the original meaning as closely as possible Do not write thoughts or anything else but the translation.\n\nTranslation:"}')

    local response
    response=$(curl -s -H "Content-Type: application/json" -X POST "$endpoint" -d "$data")
    if [[ -z "$response" ]]; then
        log_error "Empty response from Ollama API"
        return 1
    fi
    echo "$response" | jq -r '.response' | tr -d '\n'
}

translate_text_openai() {
    local escaped_text="$1"
    local endpoint="${CONFIG[API_BASE]}/chat/completions"
    local data=$(jq -n \
        --arg model "${CONFIG[MODEL]}" \
        --arg text "$escaped_text" \
        '{model: $model, messages: [{role: "system", content: "You are a translator. Translate the given Japanese text to English accurately and concisely."}, {role: "user", content: "Translate the following Japanese text to English:\n\n\($text)\n\nInstructions:\n1. Provide only the English translation.\n2. Do not include any explanations or notes.\n3. If the text is incomplete, translate what is available.\n4. Preserve the original meaning as closely as possible."}]}')

    local response
    response=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer ${CONFIG[API_KEY]}" -X POST "$endpoint" -d "$data")
    if [[ -z "$response" ]]; then
        log_error "Empty response from OpenAI API"
        return 1
    fi
    echo "$response" | jq -r '.choices[0].message.content' | tr -d '\n'
}

translate_text() {
    local escaped_text
    escaped_text=$(echo "$1" | jq -sR '.')
    log_debug "Attempting to translate: $escaped_text"

    local translation
    case "${CONFIG[API_TYPE]}" in
        ollama)
            translation=$(translate_text_ollama "$escaped_text")
            ;;
        openai)
            translation=$(translate_text_openai "$escaped_text")
            ;;
        *)
            log_error "Unknown API type ${CONFIG[API_TYPE]}"
            return 1
            ;;
    esac

    if [[ -z "$translation" ]]; then
        log_error "Empty translation received from API"
        return 1
    fi
    echo "$translation"
    update_config
}

waybar_output() {
    local status="$1"
    local message="$2"
    jq -n --arg text "翻訳" --arg tooltip "$message" --arg class "custom-mangaocr-translate $status" \
        '{"text": $text, "tooltip": $tooltip, "class": $class}'
}


perform_translation() {
    local screenshot
    screenshot=$(take_screenshot) || return 1

    log_info "Performing OCR..."

    local ocr_result
    ocr_result=$(perform_ocr "$screenshot") || return 1
    rm -f "$screenshot"
    SCREENSHOT_PATH=""

    if [ -z "$ocr_result" ]; then
        show_error "OCR result is empty. No text detected in the image."
        return 1
    fi

    log_info "Translating..."

    local translation
    translation=$(translate_text "$ocr_result")
    local exit_code=$?

    if [[ $exit_code -eq 0 && -n "$translation" ]]; then
        local result=$(printf "Original:\n%s\n\nTranslation:\n%s" "$ocr_result" "$translation")
        echo "$result" | wl-copy
        log_info "Translation completed and copied to clipboard"
        show_result "$result"
        echo "$result"
    else
        show_error "Translation failed or returned empty result"
        return 1
    fi
}

show_result() {
    local result="$1"
    if $GUI_MODE; then
        zenity --info --title="Translation Result" --text="$result" --width=400 --height=200
    else
        echo -e "\nTranslation Result:\n$result" >&2
    fi
}

show_error() {
    local error_message="$1"
    if $GUI_MODE; then
        zenity --error --title="Translation Failed" --text="$error_message" --width=300
    else
        echo "Error: $error_message" >&2
    fi
}

main() {
    read_config
    parse_arguments "$@"
    validate_config

    if $WAYBAR_MODE; then
        if [ "$1" = "click" ]; then
            echo "Starting translation process" >> "$DEBUG_LOG"
            RESULT=$(perform_translation)
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                waybar_output "" "$RESULT"
            else
                waybar_output "error" "$RESULT"
            fi
        else
            waybar_output "" "Click to translate"
        fi
    else
        echo "Starting translation process" >> "$DEBUG_LOG"
        perform_translation
    fi
}

trap cleanup EXIT
main "$@"
