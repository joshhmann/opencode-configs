# OpenCode Configs

> Pre-configured, multi-mode OpenCode setups optimized for different use cases - from free/frugal to maximum performance.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenCode](https://img.shields.io/badge/OpenCode-1.1.46+-blue.svg)](https://opencode.ai)

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/opencode-configs.git
cd opencode-configs

# Run the installer
./install.sh

# Source your shell config (or restart terminal)
source ~/.bashrc  # or ~/.zshrc

# Start using!
omo          # Check current mode
omob         # Switch to balanced mode
opencode /path/to/your/project
```

## 📋 What's Included

This repository provides pre-configured OpenCode setups with multiple modes:

### Configuration Modes

| Mode | Primary Model | Best For |
|------|---------------|----------|
| **Free** | `opencode/kimi-k2.5-free` | Saving money, testing, rate-limited scenarios |
| **Balanced** | `kimi-for-coding/k2p5` | Daily development with good quality |
| **Performance** | `kimi-for-coding/k2p5` + fallbacks | Complex tasks, important code reviews |

### Features

- ✅ **Multi-mode configuration** - Switch between free, balanced, and performance modes
- ✅ **Smart fallbacks** - Automatic fallback chains when primary models fail
- ✅ **Shell aliases** - Quick mode switching with `omof`, `omob`, `omop`
- ✅ **Easy installation** - One-command setup with `./install.sh`
- ✅ **Backup system** - Automatic backups of existing configs

## 📦 Installation

### Prerequisites

- [OpenCode](https://opencode.ai) installed (v1.1.46+)
- Bash, Zsh, or Fish shell
- Git

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/opencode-configs/main/install.sh | bash
```

### Manual Install

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/opencode-configs.git
cd opencode-configs

# 2. Run installer
./install.sh

# 3. Source your shell config
source ~/.bashrc  # or ~/.zshrc for zsh users
```

## ⚙️ Configuration

### API Keys Setup

After installation, you need to configure your API keys in `~/.config/opencode/opencode.json`:

#### Option 1: Kimi for Coding (Recommended)

If you have a Kimi for Coding subscription:

```json
{
  "provider": {
    "kimi-for-coding": {
      "models": {
        "k2p5": {
          "name": "Kimi K2.5 for Coding"
        }
      }
    }
  }
}
```

#### Option 2: Moonshot API

```json
{
  "provider": {
    "moonshot": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "https://api.moonshot.ai/v1",
        "apiKey": "sk-your-api-key-here"
      },
      "models": {
        "kimi-k2.5": {
          "name": "Kimi K2.5 (Moonshot)"
        }
      }
    }
  }
}
```

#### Option 3: Antigravity

Already configured if you have `opencode-antigravity-auth` plugin installed.

## 🎮 Usage

### Mode Switching

```bash
# Check current mode
omo
# or
omo-mode status

# Switch modes
omof    # Free mode: free models → subscription → antigravity
omob    # Balanced mode: subscription → antigravity  
omop    # Performance mode: subscription → opencode → antigravity
```

### Using OpenCode

```bash
# Start opencode in a project
opencode /path/to/your/project

# Or with specific mode
opencode /path/to/project --model kimi-for-coding/k2p5
```

## 📁 Project Structure

```
opencode-configs/
├── configs/                          # Configuration files
│   ├── oh-my-opencode-free.json      # Free/frugal mode
│   ├── oh-my-opencode-balanced.json  # Balanced mode (default)
│   └── oh-my-opencode-performance.json # Performance mode
├── scripts/
│   └── omo-mode                      # Mode switching script
├── install.sh                        # Installation script
├── README.md                         # This file
└── LICENSE                           # MIT License
```

## 🔧 Customization

### Adding Your Own Mode

1. Copy an existing config:
```bash
cp configs/oh-my-opencode-balanced.json configs/oh-my-opencode-custom.json
```

2. Edit the config to your preferences

3. Add to omo-mode script (optional)

### Modifying Fallback Chains

Edit the `fallbackChain` arrays in any config file:

```json
{
  "agents": {
    "sisyphus": {
      "model": "kimi-for-coding/k2p5",
      "fallbackChain": [
        "kimi-for-coding/k2p5",
        "your-custom-model",
        "google/antigravity-claude-opus-4-5-thinking"
      ]
    }
  }
}
```

## 🆘 Troubleshooting

### Mode switch not working?

```bash
# Check if symlink is correct
ls -la ~/.config/opencode/oh-my-opencode.json

# Verify JSON validity
cat ~/.config/opencode/oh-my-opencode.json | python -m json.tool
```

### Model not available?

```bash
# List available models
opencode models

# Check provider configuration
cat ~/.config/opencode/opencode.json
```

### Aliases not working?

```bash
# Source your shell config
source ~/.bashrc  # or ~/.zshrc

# Check if aliases are defined
alias | grep omo
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [OpenCode](https://opencode.ai) - The AI coding agent
- [Oh My OpenCode](https://github.com/code-yeongyu/oh-my-opencode) - The orchestration layer
- [Kimi](https://platform.moonshot.ai/) - The AI model
- [Antigravity](https://antigravity.ai/) - Model provider

## 📧 Support

- Create an [issue](https://github.com/yourusername/opencode-configs/issues) for bug reports
- Start a [discussion](https://github.com/yourusername/opencode-configs/discussions) for questions

---

Made with ❤️ for the OpenCode community
