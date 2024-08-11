# mangos

An OCR to machine translation script. The script supports multiple translation models and allows you to specify different API endpoints.

## Installation

You need a couple of things: zenity, grim, and jq. The installation script will tell you what you're missing before attempting to install.

Clone the repo:

```bash
git clone https://github.com/alsaiduq-lab/mangos.git
cd mangos
./install.sh
```

## First Time Installation

You need to edit the `config.yaml` provided in the directory. Alternatively, you can pass command-line arguments like:

```bash
mangos -m gpt-4o-mini -a 'https://openai.com/v1' -t openai -k skPS5HasNoGames -d cuda
```

This runs mangos in CUDA mode, using the OpenAI model gpt-4o-mini.

## Uninstall

After installation, `update.sh` and `uninstall.sh` scripts are provided. Run the uninstall script to remove mangos:

```bash
~/.local/share/mangos/uninstall.sh
```

## Usage

mangos will always attempt to use the last known method in the config, unless commandline arguments prioritize it.

## Features

- Multiple translation models support
- Customizable API endpoints
- Waybar integration

## License

idk do what you want
