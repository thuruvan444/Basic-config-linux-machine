#!/bin/bash
# Exit on errors
set -e

# === COLORS ===
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
RED='\e[31m'
RESET='\e[0m'

# === Helper Functions ===
log_info() {
    echo -e "${CYAN}[INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

# === Update and Install Essentials ===
log_info "Updating package list and installing basic tools..."
if sudo apt update && sudo apt install -y build-essential iputils-ping curl wget git vim nano net-tools; then
    log_success "Basic tools installed successfully."
else
    log_error "Failed to install basic tools. Exiting."
    exit 1
fi

# === Prompt for Hostname and Prompt Customization ===
log_info "Prompting for hostname and user details..."
read -p "Enter Course Name (e.g., SRT411): " COURSE_NAME
read -p "Enter VM Name (e.g., L1VM): " VM_NAME
read -p "Enter your Username: " USERNAME

# Validate Username (basic check if user exists)
if ! id "$USERNAME" &>/dev/null; then
    log_error "User '$USERNAME' does not exist. Please create the user first or enter an existing one. Exiting."
    exit 1
fi

# === Set Hostname ===
log_info "Setting hostname to '$VM_NAME'..."
if sudo hostnamectl set-hostname "$VM_NAME"; then
    log_success "Hostname set to '$VM_NAME'."
else
    log_error "Failed to set hostname. Exiting."
    exit 1
fi

# === Configure Custom Terminal Prompt ===
BASHRC_FILE="/home/$USERNAME/.bashrc"
log_info "Configuring custom terminal prompt for user '$USERNAME'..."

if [ ! -f "$BASHRC_FILE" ]; then
    log_error ".bashrc not found for user $USERNAME. Creating one."
    touch "$BASHRC_FILE"
    chown "$USERNAME":"$USERNAME" "$BASHRC_FILE"
fi

# Backup existing .bashrc if PS1 is already custom
if grep -q "Custom prompt" "$BASHRC_FILE"; then
    log_info "Existing custom prompt found. Backing up .bashrc to ${BASHRC_FILE}.bak"
    cp "$BASHRC_FILE" "${BASHRC_FILE}.bak"
    # Remove existing custom prompt to avoid duplicates
    sudo sed -i '/# Custom prompt/,/^PS1=.*$/d' "$BASHRC_FILE"
fi

# Append custom PS1 to .bashrc
cat << EOF | sudo tee -a "$BASHRC_FILE"

# Custom prompt
PS1="${BLUE}${COURSE_NAME}-${MAGENTA}${VM_NAME}-${YELLOW}${USERNAME}${RESET} ${GREEN}\$(date +%a\ %b\ %d\ -\ %H:%M:%S)${RESET} \$ "
EOF
log_success "Custom terminal prompt configured."

# === Prompt for number of adapters ===
log_info "Configuring network interfaces."
read -p "Enter the number of network adapters to configure: " NUM_ADAPTERS

if ! [[ "$NUM_ADAPTERS" =~ ^[0-9]+$ ]] || [ "$NUM_ADAPTERS" -eq 0 ]; then
    log_error "Invalid number of adapters. Must be a positive integer. Exiting."
    exit 1
fi

# === Build Netplan YAML ===
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
log_info "Creating Netplan configuration file: $NETPLAN_FILE"

# Start fresh with the Netplan file
echo "network:" | sudo tee $NETPLAN_FILE > /dev/null
echo "  version: 2" | sudo tee -a $NETPLAN_FILE > /dev/null
echo "  ethernets:" | sudo tee -a $NETPLAN_FILE > /dev/null

# === Loop through each adapter ===
for (( i=1; i<=NUM_ADAPTERS; i++ ))
do
    echo -e "\n${YELLOW}--- Configuring adapter #$i ---${RESET}"
    read -p "  Adapter name (e.g., ens33): " ADAPTER
    read -p "  Static IP Address (e.g., 192.168.1.10): " IPADDR
    read -p "  Subnet Mask (e.g., 24): " NETMASK

    # Optional: Gateway and DNS (can be left blank)
    read -p "  Default Gateway (optional, press Enter to skip): " GATEWAY
    read -p "  DNS Servers (space separated, optional, press Enter to skip): " DNS

    # Basic validation for IP and Netmask (can be more robust)
    if [[ -z "$ADAPTER" || -z "$IPADDR" || -z "$NETMASK" ]]; then
        log_error "Adapter name, IP address, and Subnet Mask are required for adapter #$i. Exiting."
        exit 1
    fi

    # Append adapter configuration
    sudo bash -c "cat >> \"$NETPLAN_FILE\"" << EOF
    $ADAPTER:
      dhcp4: no
      addresses: [$IPADDR/$NETMASK]
$( [ -n "$GATEWAY" ] && echo "      routes:" )
$( [ -n "$GATEWAY" ] && echo "        - to: default" )
$( [ -n "$GATEWAY" ] && echo "          via: $GATEWAY" )
$( [ -n "$DNS" ] && echo "      nameservers:" )
$( [ -n "$DNS" ] && echo "        addresses: [${DNS// /, }]" )
EOF
    log_success "Configuration added for adapter '$ADAPTER'."
done

# === Set Netplan file permissions securely ===
log_info "Setting secure permissions for Netplan configuration file..."
if sudo chmod 600 "$NETPLAN_FILE" && sudo chown root:root "$NETPLAN_FILE"; then
    log_success "Permissions set for '$NETPLAN_FILE' (owner read/write only)."
else
    log_error "Failed to set secure permissions for Netplan file. Please check manually."
    # Do not exit, as Netplan apply might still work, just with a warning.
fi


# === Apply Netplan Configuration ===
echo -e "\n${CYAN}Applying network configuration...${RESET}"
if sudo netplan apply; then
    log_success "Network configuration applied successfully."
else
    log_error "Failed to apply network configuration. Check Netplan logs for errors."
    exit 1
fi

# The internal source command for completeness, but won't affect the parent shell directly
log_info "Attempting to apply custom prompt within script's context..."
if source "/home/$USERNAME/.bashrc"; then
    log_success "Custom prompt applied within the script's shell!"
else
    log_error "Failed to source ~/.bashrc within script. This is usually okay."
fi


log_success "Setup complete!"
echo -e "Hostname set to: ${YELLOW}$VM_NAME${RESET}"
echo -e "The custom prompt has been configured to: ${BLUE}${COURSE_NAME}-${MAGENTA}${VM_NAME}-${YELLOW}${USERNAME}${RESET} ${GREEN}<Current Date/Time>${RESET} \$ "
echo -e "${YELLOW}IMPORTANT:${RESET} To see the new prompt in this current terminal session, you MUST run:"
echo -e "${YELLOW}  source ~/.bashrc${RESET}"
echo -e "${YELLOW}Or simply close and reopen your terminal. ${RESET}"
echo -e "All other system configurations (updates, tools, hostname, network) are already active."#!/bin/bash
# Exit on errors
set -e

# === COLORS ===
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
RED='\e[31m'
RESET='\e[0m'

# === Helper Functions ===
log_info() {
    echo -e "${CYAN}[INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

# === Update and Install Essentials ===
log_info "Updating package list and installing basic tools..."
if sudo apt update && sudo apt install -y build-essential iputils-ping curl wget git vim nano net-tools; then
    log_success "Basic tools installed successfully."
else
    log_error "Failed to install basic tools. Exiting."
    exit 1
fi

# === Prompt for Hostname and Prompt Customization ===
log_info "Prompting for hostname and user details..."
read -p "Enter Course Name (e.g., SRT411): " COURSE_NAME
read -p "Enter VM Name (e.g., L1VM): " VM_NAME
read -p "Enter your Username: " USERNAME

# Validate Username (basic check if user exists)
if ! id "$USERNAME" &>/dev/null; then
    log_error "User '$USERNAME' does not exist. Please create the user first or enter an existing one. Exiting."
    exit 1
fi

# === Set Hostname ===
log_info "Setting hostname to '$VM_NAME'..."
if sudo hostnamectl set-hostname "$VM_NAME"; then
    log_success "Hostname set to '$VM_NAME'."
else
    log_error "Failed to set hostname. Exiting."
    exit 1
fi

# === Configure Custom Terminal Prompt ===
BASHRC_FILE="/home/$USERNAME/.bashrc"
log_info "Configuring custom terminal prompt for user '$USERNAME'..."

if [ ! -f "$BASHRC_FILE" ]; then
    log_error ".bashrc not found for user $USERNAME. Creating one."
    touch "$BASHRC_FILE"
    chown "$USERNAME":"$USERNAME" "$BASHRC_FILE"
fi

# Backup existing .bashrc if PS1 is already custom
if grep -q "Custom prompt" "$BASHRC_FILE"; then
    log_info "Existing custom prompt found. Backing up .bashrc to ${BASHRC_FILE}.bak"
    cp "$BASHRC_FILE" "${BASHRC_FILE}.bak"
    # Remove existing custom prompt to avoid duplicates
    sudo sed -i '/# Custom prompt/,/^PS1=.*$/d' "$BASHRC_FILE"
fi

# Append custom PS1 to .bashrc
cat << EOF | sudo tee -a "$BASHRC_FILE"

# Custom prompt
PS1="${BLUE}${COURSE_NAME}-${MAGENTA}${VM_NAME}-${YELLOW}${USERNAME}${RESET} ${GREEN}\$(date +%a\ %b\ %d\ -\ %H:%M:%S)${RESET} \$ "
EOF
log_success "Custom terminal prompt configured."

# === Prompt for number of adapters ===
log_info "Configuring network interfaces."
read -p "Enter the number of network adapters to configure: " NUM_ADAPTERS

if ! [[ "$NUM_ADAPTERS" =~ ^[0-9]+$ ]] || [ "$NUM_ADAPTERS" -eq 0 ]; then
    log_error "Invalid number of adapters. Must be a positive integer. Exiting."
    exit 1
fi

# === Build Netplan YAML ===
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
log_info "Creating Netplan configuration file: $NETPLAN_FILE"

# Start fresh with the Netplan file
echo "network:" | sudo tee $NETPLAN_FILE > /dev/null
echo "  version: 2" | sudo tee -a $NETPLAN_FILE > /dev/null
echo "  ethernets:" | sudo tee -a $NETPLAN_FILE > /dev/null

# === Loop through each adapter ===
for (( i=1; i<=NUM_ADAPTERS; i++ ))
do
    echo -e "\n${YELLOW}--- Configuring adapter #$i ---${RESET}"
    read -p "  Adapter name (e.g., ens33): " ADAPTER
    read -p "  Static IP Address (e.g., 192.168.1.10): " IPADDR
    read -p "  Subnet Mask (e.g., 24): " NETMASK

    # Optional: Gateway and DNS (can be left blank)
    read -p "  Default Gateway (optional, press Enter to skip): " GATEWAY
    read -p "  DNS Servers (space separated, optional, press Enter to skip): " DNS

    # Basic validation for IP and Netmask (can be more robust)
    if [[ -z "$ADAPTER" || -z "$IPADDR" || -z "$NETMASK" ]]; then
        log_error "Adapter name, IP address, and Subnet Mask are required for adapter #$i. Exiting."
        exit 1
    fi

    # Append adapter configuration
    sudo bash -c "cat >> \"$NETPLAN_FILE\"" << EOF
    $ADAPTER:
      dhcp4: no
      addresses: [$IPADDR/$NETMASK]
$( [ -n "$GATEWAY" ] && echo "      routes:" )
$( [ -n "$GATEWAY" ] && echo "        - to: default" )
$( [ -n "$GATEWAY" ] && echo "          via: $GATEWAY" )
$( [ -n "$DNS" ] && echo "      nameservers:" )
$( [ -n "$DNS" ] && echo "        addresses: [${DNS// /, }]" )
EOF
    log_success "Configuration added for adapter '$ADAPTER'."
done

# === Set Netplan file permissions securely ===
log_info "Setting secure permissions for Netplan configuration file..."
if sudo chmod 600 "$NETPLAN_FILE" && sudo chown root:root "$NETPLAN_FILE"; then
    log_success "Permissions set for '$NETPLAN_FILE' (owner read/write only)."
else
    log_error "Failed to set secure permissions for Netplan file. Please check manually."
    # Do not exit, as Netplan apply might still work, just with a warning.
fi


# === Apply Netplan Configuration ===
echo -e "\n${CYAN}Applying network configuration...${RESET}"
if sudo netplan apply; then
    log_success "Network configuration applied successfully."
else
    log_error "Failed to apply network configuration. Check Netplan logs for errors."
    exit 1
fi

log_success "Setup complete!"
echo -e "Hostname set to: ${YELLOW}$VM_NAME${RESET}"
echo -e "The custom prompt has been configured to: ${BLUE}${COURSE_NAME}-${MAGENTA}${VM_NAME}-${YELLOW}${USERNAME}${RESET} ${GREEN}<Current Date/Time>${RESET} \$ "
echo -e "${YELLOW}IMPORTANT:${RESET} To see the new prompt in this current terminal session, you MUST run:"
echo -e "${YELLOW}  source ~/.bashrc${RESET}"
echo -e "${YELLOW}Or simply close and reopen your terminal. ${RESET}"
echo -e "All other system configurations (updates, tools, hostname, network) are already active."
