#!/bin/bash
# Unified setup script for email-sleuth
# Installs system dependencies, email-sleuth binary, and ChromeDriver

set -e  # Exit on any error

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="$HOME/.email-sleuth"
CONFIG_DIR="$HOME/.config/email-sleuth"
BIN_DIR="$HOME/.local/bin"
DRIVERS_DIR="$INSTALL_DIR/drivers"
CONFIG_FILE="$CONFIG_DIR/config.toml"

REPO_OWNER="tokenizer-decode"
REPO_NAME="email-sleuth"
BINARY_NAME="email-sleuth"
GITHUB_RELEASE_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases"
LATEST_RELEASE_URL="$GITHUB_RELEASE_URL/latest"
CHROMEDRIVER_VERSION="135.0.7049.114"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}     Email Sleuth Complete Setup Tool      ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

detect_platform() {
    OS_RAW=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    if [[ "$OS_RAW" == "darwin" ]]; then
        OS="apple-darwin"
        CHROMEDRIVER_PLATFORM="mac-x64"
        [[ "$ARCH" == "arm64" ]] && CHROMEDRIVER_PLATFORM="mac-arm64"
        PACKAGE_MANAGER="brew"
    elif [[ "$OS_RAW" == "linux" ]]; then
        OS="unknown-linux-gnu"
        CHROMEDRIVER_PLATFORM="linux64"
        if command -v apt-get &> /dev/null; then
            PACKAGE_MANAGER="apt-get"
        elif command -v yum &> /dev/null; then
            PACKAGE_MANAGER="yum"
        elif command -v dnf &> /dev/null; then
            PACKAGE_MANAGER="dnf"
        else
             PACKAGE_MANAGER="unknown"
        fi
    else
        echo -e "${RED}Error: Unsupported operating system: $OS_RAW${NC}"
        echo "This installer supports macOS and Linux only."
        exit 1
    fi
    
    if [[ "$ARCH" == "x86_64" ]]; then
        ARCH="x86_64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        ARCH="aarch64"
    else
        echo -e "${RED}Error: Unsupported architecture: $ARCH${NC}"
        exit 1
    fi
    
    PLATFORM="${ARCH}-${OS}"
    echo -e "${GREEN}Detected platform: $PLATFORM, Package Manager: $PACKAGE_MANAGER${NC}"
}

install_system_dependencies() {
    echo -e "${BLUE}Checking and installing system dependencies...${NC}"
    
    if [[ "$OS" == "unknown-linux-gnu" ]]; then
        if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
            echo "Attempting to install dependencies using apt-get (requires sudo)..."
            if sudo apt-get update && sudo apt-get install -y \
                curl \
                wget \
                tar \
                unzip \
                jq \
                ca-certificates \
                libnss3 \
                libatk1.0-0 \
                libatk-bridge2.0-0 \
                libgtk-3-0 \
                libgbm-dev \
                libasound2t64; then
                echo -e "${GREEN}System dependencies installed successfully.${NC}"
            else
                echo -e "${RED}Error: Failed to install system dependencies using apt-get.${NC}"
                echo -e "${YELLOW}Please install the required packages manually and try again.${NC}"
                exit 1
            fi
        elif [[ "$PACKAGE_MANAGER" == "yum" || "$PACKAGE_MANAGER" == "dnf" ]]; then
            echo "Attempting to install dependencies using $PACKAGE_MANAGER (requires sudo)..."
             echo -e "${YELLOW}Warning: Automatic dependency installation for $PACKAGE_MANAGER is not fully implemented.${NC}"
             echo -e "${YELLOW}Please ensure the following are installed: curl, wget, tar, unzip, jq, ca-certificates, nss, GConf2, atk, gtk3, libgbm, alsa-lib.${NC}"
        else
            echo -e "${YELLOW}Warning: Unknown Linux package manager. Cannot automatically install dependencies.${NC}"
            echo -e "${YELLOW}Please ensure essential tools (curl, wget, tar, unzip, jq, ca-certificates) and ChromeDriver dependencies (like libnss3) are installed.${NC}"
        fi
    elif [[ "$OS" == "apple-darwin" ]]; then
         echo "On macOS, required tools will be installed via Homebrew if needed."
    fi
    echo ""
}

check_command() {
    local cmd="$1"
    local install_package="${2:-$1}"

    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${YELLOW}Required command '$cmd' not found. Attempting to install...${NC}"
        if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
            echo "Trying sudo apt-get install -y $install_package..."
            if sudo apt-get update && sudo apt-get install -y "$install_package"; then
                 echo -e "${GREEN}$cmd installed successfully.${NC}"
            else
                 echo -e "${RED}Failed to install $cmd using apt-get.${NC}"
                 exit 1
            fi
        elif [[ "$PACKAGE_MANAGER" == "brew" ]]; then
            echo "Trying brew install $install_package..."
             if brew install "$install_package"; then
                 echo -e "${GREEN}$cmd installed successfully via Homebrew.${NC}"
             else
                 echo -e "${RED}Failed to install $cmd using Homebrew.${NC}"
                 exit 1
             fi
        else
             echo -e "${RED}Error: Cannot automatically install '$cmd'. Package manager '$PACKAGE_MANAGER' not supported.${NC}"
             exit 1
        fi
    fi
}

create_directories() {
    echo -e "${BLUE}Creating installation directories...${NC}"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "$DRIVERS_DIR"
}

# Get latest email-sleuth version
get_latest_version() {
    echo -e "${BLUE}Fetching latest email-sleuth release information...${NC}"

    # Try API first (requires jq)
    if command -v jq &> /dev/null; then
        LATEST_VERSION=$(curl -s -L \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$LATEST_RELEASE_URL" |
            jq -r '.tag_name // empty' |
            head -n 1)
        echo -e "${YELLOW}Using GitHub API via jq.${NC}"
    fi

    # Fallback or if jq failed
    if [[ -z "$LATEST_VERSION" ]]; then
        echo -e "${YELLOW}API call failed or jq not found, trying HTML scrape fallback...${NC}"
        LATEST_VERSION=$(curl -s -L "$GITHUB_RELEASE_URL" |
            grep -o '/releases/tag/v[0-9]*\.[0-9]*\.[0-9]*' |
            head -n 1 |
            cut -d '/' -f4)
    fi

    if [[ -z "$LATEST_VERSION" ]]; then
        echo -e "${RED}Error: Could not determine latest version.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Latest version: $LATEST_VERSION${NC}"
}

# Download and install email-sleuth binary
install_email_sleuth() {
    echo -e "${BLUE}Installing Email Sleuth binary ($LATEST_VERSION)...${NC}"

    local ARCHIVE_NAME="${BINARY_NAME}-${LATEST_VERSION}-${PLATFORM}"
    if [[ "$OS" == "apple-darwin" ]]; then
        ARCHIVE_NAME="${ARCHIVE_NAME}.zip"
    else
        ARCHIVE_NAME="${ARCHIVE_NAME}.tar.gz"
    fi

    local DOWNLOAD_URL="$GITHUB_RELEASE_URL/download/$LATEST_VERSION/$ARCHIVE_NAME"
    echo -e "Downloading from: $DOWNLOAD_URL"

    TMP_DIR=$(mktemp -d)
    pushd "$TMP_DIR" > /dev/null

    # Use wget if curl failed previously, otherwise prefer curl
    DOWNLOAD_CMD="curl -L --progress-bar -o"
    if ! command -v curl &> /dev/null && command -v wget &> /dev/null; then
        DOWNLOAD_CMD="wget --progress=bar:force -O"
    fi

    if ! $DOWNLOAD_CMD "$ARCHIVE_NAME" "$DOWNLOAD_URL"; then
        echo -e "${RED}Error: Failed to download $ARCHIVE_NAME${NC}"
        popd > /dev/null
        rm -rf "$TMP_DIR"
        exit 1
    fi

    echo -e "Extracting..."
    if [[ "$ARCHIVE_NAME" == *.zip ]]; then
        check_command unzip
        unzip -q "$ARCHIVE_NAME"
    else
        check_command tar
        tar xzf "$ARCHIVE_NAME"
    fi

    # Find the binary
    if [[ "$(uname)" == "Darwin" ]]; then
        FOUND_BINARY=$(find . -name "$BINARY_NAME" -type f | head -n 1)
    else
        FOUND_BINARY=$(find . -name "$BINARY_NAME" -type f -executable | head -n 1)
    fi
    
    if [[ -z "$FOUND_BINARY" ]]; then
        echo -e "${RED}Error: No executable named '$BINARY_NAME' found in the archive.${NC}"
        popd > /dev/null
        rm -rf "$TMP_DIR"
        exit 1
    fi

    echo "Found binary at: $FOUND_BINARY"
    
    # Install both email-sleuth and es binaries (they're the same binary)
    cp "$FOUND_BINARY" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    
    # Link both binary names
    ln -sf "$INSTALL_DIR/$BINARY_NAME" "$BIN_DIR/$BINARY_NAME"
    ln -sf "$INSTALL_DIR/$BINARY_NAME" "$BIN_DIR/es"

    popd > /dev/null
    rm -rf "$TMP_DIR"

    echo -e "${GREEN}Email Sleuth binary installed successfully!${NC}"
}

install_chromedriver() {
    echo -e "${BLUE}Installing ChromeDriver ($CHROMEDRIVER_VERSION) for enhanced verification...${NC}"

    local CHROMEDRIVER_DOWNLOAD_URL
    CHROMEDRIVER_DOWNLOAD_URL=$(curl -s "https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json" | jq -r --arg version "$CHROMEDRIVER_VERSION" --arg platform "chromedriver-$CHROMEDRIVER_PLATFORM" '.versions[] | select(.version==$version) | .downloads.chromedriver[] | select(.platform==$platform).url // empty' | head -n 1)

    if [[ -z "$CHROMEDRIVER_DOWNLOAD_URL" ]]; then
         echo -e "${YELLOW}Warning: Could not automatically find download URL for ChromeDriver $CHROMEDRIVER_VERSION ($CHROMEDRIVER_PLATFORM).${NC}"
         echo -e "${YELLOW}Falling back to constructed URL (might be outdated or incorrect).${NC}"
         CHROMEDRIVER_DOWNLOAD_URL="https://storage.googleapis.com/chrome-for-testing-public/$CHROMEDRIVER_VERSION/$CHROMEDRIVER_PLATFORM/chromedriver-$CHROMEDRIVER_PLATFORM.zip"
    fi

    echo -e "Downloading ChromeDriver from: $CHROMEDRIVER_DOWNLOAD_URL"

    TMP_DIR=$(mktemp -d)
    pushd "$TMP_DIR" > /dev/null

    # Use wget if curl failed previously, otherwise prefer curl
    DOWNLOAD_CMD="curl -L --progress-bar -o"
    if ! command -v curl &> /dev/null && command -v wget &> /dev/null; then
        DOWNLOAD_CMD="wget --progress=bar:force -O"
    fi

    if ! $DOWNLOAD_CMD "chromedriver.zip" "$CHROMEDRIVER_DOWNLOAD_URL"; then
        echo -e "${YELLOW}Warning: Failed to download ChromeDriver. Enhanced verification might not be available.${NC}"
        popd > /dev/null
        rm -rf "$TMP_DIR"
        return 1
    fi

    echo -e "Extracting ChromeDriver..."
    check_command unzip
    mkdir extract
    if ! unzip -q "chromedriver.zip" -d ./extract; then
        echo -e "${RED}Error: Failed to unzip chromedriver.zip${NC}"
        popd > /dev/null
        rm -rf "$TMP_DIR"
        return 1
    fi

    DRIVER_PATH=$(find ./extract -name "chromedriver" -type f -executable | head -n 1)
     if [[ -z "$DRIVER_PATH" ]]; then
        DRIVER_PATH=$(find ./extract -name "chromedriver.exe" -type f -executable | head -n 1)
     fi

    if [[ -z "$DRIVER_PATH" ]]; then
        echo -e "${YELLOW}Warning: Could not find ChromeDriver executable in the extracted archive.${NC}"
        ls -lR ./extract
        popd > /dev/null
        rm -rf "$TMP_DIR"
        return 1
    fi

    echo "Found ChromeDriver executable at: $DRIVER_PATH"
    cp "$DRIVER_PATH" "$DRIVERS_DIR/chromedriver"
    chmod +x "$DRIVERS_DIR/chromedriver"

    popd > /dev/null
    rm -rf "$TMP_DIR"

    echo -e "${GREEN}ChromeDriver installed successfully!${NC}"
    return 0
}

create_config() {
    echo -e "${BLUE}Creating default configuration...${NC}"

    # If config file already exists, don't overwrite it
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}Configuration file $CONFIG_FILE already exists. Skipping creation.${NC}"
        return
    fi

    cat > "$CONFIG_FILE" << 'EOL'
# Email Sleuth Configuration

# Settings related to network operations (HTTP requests)
[network]
# Timeout for individual HTTP requests (e.g., fetching website pages) in seconds.
request_timeout = 10
# Sleep between HTTP requests to avoid rate limiting (seconds)
min_sleep = 0.1
max_sleep = 0.5
# User-Agent string for HTTP requests
user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36"

# Settings related to DNS lookups (e.g., finding MX records)
[dns]
# Timeout for DNS resolution queries in seconds.
dns_timeout = 5
# DNS servers to use for lookups
dns_servers = [
    "8.8.8.8", # Google Public DNS 1
    "8.8.4.4", # Google Public DNS 2
    "1.1.1.1", # Cloudflare DNS 1
    "1.0.0.1", # Cloudflare DNS 2
]

# Settings related to SMTP email verification
[smtp]
# Timeout for SMTP commands (like HELO, MAIL FROM, RCPT TO) in seconds.
smtp_timeout = 5
# The sender email address used in the 'MAIL FROM:' SMTP command during verification.
smtp_sender_email = "verify-probe@example.com"
# Maximum number of retries for SMTP verification if inconclusive
max_verification_attempts = 2

# Settings controlling the verification logic and thresholds
[verification]
# Minimum confidence score (0-10) required for an email to be selected
confidence_threshold = 4
# Minimum score (0-10) required for generic emails (e.g., info@)
generic_confidence_threshold = 7
# Maximum number of alternative emails to include in results
max_alternatives = 5
# Default maximum concurrent tasks for processing
max_concurrency = 8
# Stop processing more candidates when a match with this confidence (0-10) is found
early_termination_threshold = 9

# Settings for advanced/experimental verification methods
[advanced_verification]
enable_api_checks = true
enable_headless_checks = true
webdriver_url = "http://localhost:4444" # Default ChromeDriver port
# Path to the ChromeDriver executable. If empty, email-sleuth will try to find it.
# Usually leave this empty if installed by this script to $INSTALL_DIR/drivers/chromedriver
chromedriver_path = ""
EOL

    echo -e "${GREEN}Default configuration created at $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Remember to edit $CONFIG_FILE, especially 'smtp_sender_email'.${NC}"
}

check_path() {
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo -e "${YELLOW}Adding $BIN_DIR to your PATH...${NC}"

        SHELL_NAME=$(basename "$SHELL")
        SHELL_CONFIG=""

        if [[ "$SHELL_NAME" == "bash" ]]; then
            if [[ -f "$HOME/.bashrc" ]]; then
                SHELL_CONFIG="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                SHELL_CONFIG="$HOME/.bash_profile"
            else
                 SHELL_CONFIG="$HOME/.profile"
            fi
        elif [[ "$SHELL_NAME" == "zsh" ]]; then
            SHELL_CONFIG="$HOME/.zshrc"
        elif [[ "$SHELL_NAME" == "fish" ]]; then
            if command -v fish &> /dev/null; then
                 mkdir -p "$HOME/.config/fish/conf.d"
                 echo "set -gx PATH \$PATH $BIN_DIR" > "$HOME/.config/fish/conf.d/email_sleuth.fish"
                 echo -e "${GREEN}Added $BIN_DIR to PATH for Fish shell.${NC}"
                 echo -e "${YELLOW}Note: You need to restart your fish shell to apply the PATH change.${NC}"
                 return
            else
                 echo -e "${YELLOW}Warning: Fish shell detected but 'fish' command not found? Please add $BIN_DIR to your PATH manually.${NC}"
                 return
            fi
        else
            echo -e "${YELLOW}Warning: Could not detect a standard shell configuration file for '$SHELL_NAME'.${NC}"
            echo -e "${YELLOW}Please add the following line to your shell's startup file manually:${NC}"
            echo -e "${YELLOW}  export PATH=\"\$PATH:$BIN_DIR\"${NC}"
            return
        fi

        if [[ -n "$SHELL_CONFIG" ]]; then
             echo -e "\n# Added by email-sleuth setup $(date)" >> "$SHELL_CONFIG"
             echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$SHELL_CONFIG"
             echo -e "${GREEN}Added $BIN_DIR to PATH in $SHELL_CONFIG${NC}"
             echo -e "${YELLOW}Note: You may need to restart your terminal or run 'source $SHELL_CONFIG' to apply the PATH change.${NC}"
        else
              echo -e "${YELLOW}Warning: Could not find a suitable shell configuration file. Please add $BIN_DIR to your PATH manually.${NC}"
        fi
    else
        echo -e "${GREEN}$BIN_DIR is already in your PATH.${NC}"
    fi
}

show_success() {
    echo -e "\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Email Sleuth setup completed successfully! ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo -e "${BLUE}Installation Details:${NC}"
    echo -e "  Binary:      ${YELLOW}$INSTALL_DIR/$BINARY_NAME${NC}"
    echo -e "  Commands:    ${YELLOW}email-sleuth${NC} or ${YELLOW}es${NC} (both work the same)"
    echo -e "  ChromeDriver:${YELLOW}$DRIVERS_DIR/chromedriver${NC}"
    echo -e "  Config File: ${YELLOW}$CONFIG_FILE${NC}"
    echo ""
    echo -e "${BLUE}Quick Start:${NC}"
    echo -e "  ${YELLOW}es \"John Doe\" example.com${NC}               # Basic verification"
    echo -e "  ${YELLOW}es -m comprehensive \"Jane Smith\" company.com${NC}  # All verification methods"
    echo ""
    echo -e "${BLUE}ChromeDriver Service:${NC}"
    echo -e "  ${YELLOW}es --service start${NC}                       # Start ChromeDriver"
    echo -e "  ${YELLOW}es --service status${NC}                      # Check ChromeDriver status"
    echo -e "  ${YELLOW}es --service stop${NC}                        # Stop ChromeDriver"
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo -e "  Edit ${YELLOW}$CONFIG_FILE${NC} to customize settings."
    echo -e "  ${RED}IMPORTANT:${NC} Remember to set a valid 'smtp_sender_email' in the config!"
    echo ""
    check_path
    echo ""
    echo -e "${YELLOW}If the 'es' command is not found, please restart your terminal or run the 'source' command suggested above.${NC}"
    echo ""
}

main() {
    detect_platform
    install_system_dependencies
    
    echo -e "${BLUE}Verifying essential tools...${NC}"
    check_command curl
    check_command grep
    check_command tar
    check_command jq || echo -e "${YELLOW}jq not found or install failed. Some features like API version check might be limited.${NC}"
    
    create_directories
    get_latest_version
    install_email_sleuth
    
    if ! install_chromedriver; then
        echo -e "${YELLOW}ChromeDriver installation failed or was skipped.${NC}"
        echo -e "${YELLOW}'comprehensive' verification mode will not be available unless ChromeDriver is installed manually.${NC}"
    fi
    
    create_config
    show_success
}

main
exit 0
