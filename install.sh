#!/bin/bash
set -e

INSTALL_DIR="$HOME/.local/share/mangos"
BIN_DIR="$HOME/.local/bin"
CURRENT_DIR="$(pwd)"
CONFIG_FILE="config.yaml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

check_system_dependencies() {
    print_message "Checking system dependencies..."
    local missing_deps=()
    for cmd in python3 grim zenity curl jq; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "The following dependencies are missing: ${missing_deps[*]}"
        print_error "Please install them and run this script again."
        exit 1
    fi
}

create_install_dir() {
    print_message "Creating installation directory..."
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"
}

copy_files() {
    print_message "Copying files to installation directory..."
    cp -R "$CURRENT_DIR"/* "$INSTALL_DIR"
}

setup_venv() {
    print_message "Setting up Python virtual environment..."
    python3 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install --upgrade pip
    pip install manga_ocr pillow
    deactivate
}

install_mangos() {
    print_message "Installing mangos..."
    cat > "$BIN_DIR/mangos" << EOL
#!/bin/bash
exec "$INSTALL_DIR/translate.sh" "\$@"
EOL
    chmod +x "$BIN_DIR/mangos"
}

create_config() {
    print_message "Creating initial config file..."
    cat > "$INSTALL_DIR/$CONFIG_FILE" << EOL
model: gpt-4o-mini
api_base: https://api.openai.com/v1
api_key:
device: cpu
api_type: openai
EOL
    ln -sf "$INSTALL_DIR/$CONFIG_FILE" "$CURRENT_DIR/$CONFIG_FILE"
    print_message "Created symlink for config file in current directory"
}

update_path() {
    print_message "Updating PATH..."
    local shell_configs=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.config/fish/config.fish"
        "$HOME/.profile"
        "$HOME/.bash_profile"
    )

    local path_updated=false

    for config in "${shell_configs[@]}"; do
        if [ -f "$config" ]; then
            if ! grep -q "$BIN_DIR" "$config"; then
                if [[ "$config" == *"fish"* ]]; then
                    echo "set -gx PATH $BIN_DIR \$PATH" >> "$config"
                else
                    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$config"
                fi
                print_warning "Updated $config. Please restart your terminal or run 'source $config' to update your PATH."
                path_updated=true
            fi
        fi
    done

    if [ "$path_updated" = false ]; then
        print_warning "No existing shell configuration files were updated."
        print_warning "Please add the following line to your preferred shell configuration file:"
        print_warning "export PATH=\"$BIN_DIR:\$PATH\""
    fi

    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        print_warning "The installation directory is not in your current PATH."
        print_warning "You may need to restart your terminal or manually add it to use the 'mangos' command."
    fi
}

create_uninstall_script() {
    print_message "Creating uninstall script..."
    cat > "$INSTALL_DIR/uninstall.sh" << EOL
#!/bin/bash
rm -rf "$INSTALL_DIR"
rm -f "$BIN_DIR/mangos"
rm -f "$CURRENT_DIR/$CONFIG_FILE"
echo "mangos has been uninstalled. You may need to manually remove the PATH addition from your shell configuration files."
EOL
    chmod +x "$INSTALL_DIR/uninstall.sh"
}

create_update_script() {
    print_message "Creating update script..."
    cat > "$INSTALL_DIR/update.sh" << EOL
#!/bin/bash
set -e
INSTALL_DIR="$INSTALL_DIR"
VENV_DIR="$INSTALL_DIR/venv"
echo "Updating mangos..."
cd "\$INSTALL_DIR"
git pull origin main
echo "Updating Python dependencies..."
source "\$VENV_DIR/bin/activate"
pip install --upgrade manga_ocr pillow
deactivate
echo "Update complete!"
EOL
    chmod +x "$INSTALL_DIR/update.sh"
}


main() {
    print_message "Starting mangos installation..."
    check_system_dependencies
    create_install_dir
    copy_files
    setup_venv
    install_mangos
    create_config
    update_path
    create_uninstall_script
    create_update_script
    print_message "Installation complete!"
    print_message "You can now run mangos by typing 'mangos' in your terminal."
    print_warning "If 'mangos' command is not found, please restart your terminal or update your PATH manually."
    print_message "To uninstall, run $INSTALL_DIR/uninstall.sh"
    print_message "To update, run $INSTALL_DIR/update.sh"
}

main
