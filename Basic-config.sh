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
# Added nftables to the install list as it's required for masquerading
if sudo apt update && sudo apt install -y build-essential iputils-ping curl wget git vim nano net-tools nftables; then
    log_success "Basic tools and nftables installed successfully."
else
    log_error "Failed to install basic tools or nftables. Exiting."
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

# === ROUTER CONFIGURATION: Enable IP Forwarding (Step 3 from PDF) ===
log_info "Enabling IP forwarding for router functionality..."
SYSCTL_CONF="/etc/sysctl.conf"
if ! grep -q "^net.ipv4.ip_forward=1" "$SYSCTL_CONF"; then
    log_info "Backing up sysctl.conf to ${SYSCTL_CONF}.original"
    sudo cp "$SYSCTL_CONF" "${SYSCTL_CONF}.original"

    log_info "Modifying sysctl.conf to enable IP forwarding..."
    # Remove '#' and any leading/trailing spaces from the line containing ip_forward
    sudo sed -i '/^#\s*net.ipv4.ip_forward/s/^#\s*//' "$SYSCTL_CONF"
    # Ensure the line is exactly 'net.ipv4.ip_forward=1'
    if ! grep -q "^net.ipv4.ip_forward=1" "$SYSCTL_CONF"; then
        echo "net.ipv4.ip_forward=1" | sudo tee -a "$SYSCTL_CONF" > /dev/null
    fi
    log_success "IP forwarding configured in sysctl.conf."
else
    log_info "IP forwarding is already enabled in sysctl.conf."
fi

log_info "Applying sysctl changes..."
if sudo sysctl -p; then
    log_success "IP forwarding enabled successfully."
else
    log_error "Failed to enable IP forwarding. Exiting."
    exit 1
fi

# === ROUTER CONFIGURATION: Configure nftables for Masquerading (Step 4 from PDF) ===
log_info "Configuring nftables for masquerading (NAT)..."

read -p "Enter the name of the EXTERNAL (Internet-facing) network interface for masquerading (e.g., enp0s3): " EXTERNAL_INTERFACE

if [[ -z "$EXTERNAL_INTERFACE" ]]; then
    log_error "External interface name is required for masquerading. Exiting."
    exit 1
fi

NFTABLES_RULESET_FILE="/etc/nftables.ruleset"

log_info "Flushing existing nftables ruleset and adding NAT rules..."
if sudo nft flush ruleset && \
   sudo nft add table ip nat && \
   sudo nft add chain ip nat POSTROUTING '{ type nat hook postrouting priority 100; policy accept; }' && \
   sudo nft add rule ip nat POSTROUTING oifname "$EXTERNAL_INTERFACE" counter masquerade; then
    log_success "nftables NAT rules added successfully."

    log_info "Saving nftables ruleset to $NFTABLES_RULESET_FILE..."
    if sudo nft list ruleset > "$NFTABLES_RULESET_FILE"; then
        log_success "nftables ruleset saved to $NFTABLES_RULESET_FILE."
        log_info "Current nftables ruleset:"
        cat "$NFTABLES_RULESET_FILE"
    else
        log_error "Failed to save nftables ruleset. Please check permissions or disk space."
        exit 1
    fi
else
    log_error "Failed to configure nftables. Check nftables logs for errors. Exiting."
    exit 1
fi

# === ROUTER CONFIGURATION: Make nftables rules persistent (Step 5 & 6 from PDF) ===
log_info "Making nftables rules persistent using networkd-dispatcher..."
NETWORKD_DISPATCHER_DIR="/etc/networkd-dispatcher/routable.d"
HOOK_FILE="$NETWORKD_DISPATCHER_DIR/50-ifup.hooks"

log_info "Creating directory $NETWORKD_DISPATCHER_DIR if it does not exist..."
if sudo mkdir -p "$NETWORKD_DISPATCHER_DIR"; then
    log_success "Directory $NETWORKD_DISPATCHER_DIR ensured."
else
    log_error "Failed to create directory $NETWORKD_DISPATCHER_DIR. Exiting."
    exit 1
fi

log_info "Creating and setting permissions for $HOOK_FILE..."
cat << 'EOF_HOOK' | sudo tee "$HOOK_FILE" > /dev/null
#!/bin/bash
#
# This script is executed by networkd-dispatcher when an interface becomes routable.
# It loads the nftables ruleset to ensure NAT/masquerading is active after network changes.

/usr/sbin/nft --file /etc/nftables.ruleset

# Entire contents added by Thuruvan Thavapalan on $(date +%F)
EOF_HOOK

if sudo chmod a+x "$HOOK_FILE"; then
    log_success "Hook file $HOOK_FILE created and made executable."
else
    log_error "Failed to make hook file executable. Exiting."
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
echo -e "All other system configurations (updates, tools, hostname, network, and router functionality) are already active."

echo -e "\n${YELLOW}This script was made by Thuruvan Thavapalan with help of AI.${RESET}"
