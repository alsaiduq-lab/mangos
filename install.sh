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
    for cmd in python3 grim zenity curl jq git rsync; do
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

setup_venv() {
    print_message "Setting up Python virtual environment..."
    python3 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install --upgrade pip
    pip install -r "$INSTALL_DIR/requirements.txt"
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
    local path_entry="export PATH=\"$BIN_DIR:\$PATH\""
    local fish_path_entry="set -gx PATH $BIN_DIR \$PATH"
    local path_updated=false
    for config in "${shell_configs[@]}"; do
        if [ -f "$config" ]; then
            if [[ "$config" == *"fish"* ]]; then
                if ! grep -q "set -gx PATH $BIN_DIR" "$config"; then
                    echo "$fish_path_entry" >> "$config"
                    print_warning "Updated $config. Please restart your terminal or run 'source $config' to update your PATH."
                    path_updated=true
                fi
            else
                if ! grep -q "export PATH=.*$BIN_DIR" "$config"; then
                    echo "$path_entry" >> "$config"
                    print_warning "Updated $config. Please restart your terminal or run 'source $config' to update your PATH."
                    path_updated=true
                fi
            fi
        fi
    done

    if [ "$path_updated" = false ]; then
        print_warning "No shell configuration files were updated."
        print_warning "The mangos binary directory is already in your PATH."
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
set -e
INSTALL_DIR="$INSTALL_DIR"
BIN_DIR="$BIN_DIR"
CURRENT_DIR="$CURRENT_DIR"
CONFIG_FILE="$CONFIG_FILE"

echo "Uninstalling mangos..."

if [ -d "\$INSTALL_DIR" ]; then
    rm -rf "\$INSTALL_DIR"
    echo "Removed \$INSTALL_DIR"
else
    echo "Installation directory \$INSTALL_DIR not found."
fi

if [ -f "\$BIN_DIR/mangos" ]; then
    rm -f "\$BIN_DIR/mangos"
    echo "Removed \$BIN_DIR/mangos"
else
    echo "Binary link \$BIN_DIR/mangos not found."
fi

if [ -f "\$CURRENT_DIR/\$CONFIG_FILE" ]; then
    rm -f "\$CURRENT_DIR/\$CONFIG_FILE"
    echo "Removed \$CURRENT_DIR/\$CONFIG_FILE"
else
    echo "Config file \$CURRENT_DIR/\$CONFIG_FILE not found."
fi

echo "mangos has been uninstalled."
echo "You may need to manually remove the PATH addition from your shell configuration files."

read -p "Do you want to attempt automatic removal of the PATH entry? (y/n) " -n 1 -r
echo
if [[ \$REPLY =~ ^[Yy]$ ]]; then
    for config in "\$HOME/.bashrc" "\$HOME/.zshrc" "\$HOME/.config/fish/config.fish" "\$HOME/.profile" "\$HOME/.bash_profile"; do
        if [ -f "\$config" ]; then
            sed -i '/export PATH="\$BIN_DIR:\$PATH"/d' "\$config"
            sed -i '/set -gx PATH \$BIN_DIR \$PATH/d' "\$config"
            echo "Attempted to remove PATH entry from \$config"
        fi
    done
    echo "Please restart your terminal or run 'source <config>' to refresh your environment."
else
    echo "Skipped automatic PATH removal. Please remove the PATH entry manually if necessary."
fi

echo "Uninstallation complete!"
EOL
    chmod +x "$INSTALL_DIR/uninstall.sh"
}


copy_files() {
    print_message "Copying files to installation directory..."
    rsync -av --exclude='.git' --exclude='.gitignore' --exclude='venv' --exclude='install.sh' "$CURRENT_DIR/" "$INSTALL_DIR/"
}

create_update_script() {
    print_message "Creating update script..."
    cat > "$INSTALL_DIR/update.sh" << EOL
#!/bin/bash
set -e
INSTALL_DIR="$INSTALL_DIR"
VENV_DIR="\$INSTALL_DIR/venv"
CURRENT_DIR="$CURRENT_DIR"

echo "Updating mangos..."
rsync -av --exclude='.git' --exclude='venv' --exclude='install.sh' --exclude='config.yaml' "$CURRENT_DIR/" "\$INSTALL_DIR/"

echo "Checking for changes in requirements..."
if ! cmp -s "\$INSTALL_DIR/requirements.txt" "\$VENV_DIR/requirements.txt"; then
    echo "Requirements have changed. Updating Python dependencies..."
    cp "\$INSTALL_DIR/requirements.txt" "\$VENV_DIR/requirements.txt"
    source "\$VENV_DIR/bin/activate"
    pip install -r "\$VENV_DIR/requirements.txt"
    deactivate
else
    echo "No changes in requirements."
fi
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
    print_warning "If the 'mangos' command is not found, please restart your terminal or update your PATH manually."
    print_message "To uninstall, run $INSTALL_DIR/uninstall.sh"
    print_message "To update, run $INSTALL_DIR/update.sh"
}

main
