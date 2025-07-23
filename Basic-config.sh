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
read -p "Do you want to update and install basic tools (requires internet)? (y/n): " DO_UPDATE
if [[ "$DO_UPDATE" =~ ^[Yy]$ ]]; then
    log_info "Updating package list and installing basic tools..."
    if sudo apt update && sudo apt install -y build-essential iputils-ping curl wget git vim nano net-tools cockpit; then
        log_success "Basic tools installed successfully."
    else
        log_error "Failed to install basic tools. Check your internet connection. Exiting."
        exit 1
    fi
else
    log_info "Skipped package update and installation by user choice."
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

    # Optional: Gateway, DNS, and Custom Routes
    read -p "  Default Gateway (optional, press Enter to skip): " GATEWAY
    read -p "  DNS Servers (space separated, optional, press Enter to skip): " DNS

    # Custom routes input (can be multiple routes separated by commas)
    read -p "  Static Routes (format: <destination_cidr>:<via>, separate multiple with commas, e.g., 192.168.5.0/24:192.168.2.1): " ROUTES

    # Basic validation for IP and Netmask
    if [[ -z "$ADAPTER" || -z "$IPADDR" || -z "$NETMASK" ]]; then
        log_error "Adapter name, IP address, and Subnet Mask are required for adapter #$i. Exiting."
        exit 1
    fi

    # Append adapter configuration to Netplan YAML
    sudo bash -c "cat >> \"$NETPLAN_FILE\"" << EOF
    $ADAPTER:
      dhcp4: no
      addresses: [$IPADDR/$NETMASK]
EOF

    # Add routes if any
    if [[ -n "$GATEWAY" || -n "$ROUTES" ]]; then
        echo "      routes:" | sudo tee -a "$NETPLAN_FILE" > /dev/null
    fi

    if [[ -n "$GATEWAY" ]]; then
        echo "        - to: default" | sudo tee -a "$NETPLAN_FILE" > /dev/null
        echo "          via: $GATEWAY" | sudo tee -a "$NETPLAN_FILE" > /dev/null
    fi

    if [[ -n "$ROUTES" ]]; then
        IFS=',' read -ra ROUTE_ARRAY <<< "$ROUTES"
        for route_entry in "${ROUTE_ARRAY[@]}"; do
            DEST=$(echo "$route_entry" | cut -d':' -f1)
            VIA=$(echo "$route_entry" | cut -d':' -f2)
            if [[ -n "$DEST" && -n "$VIA" ]]; then
                echo "        - to: $DEST" | sudo tee -a "$NETPLAN_FILE" > /dev/null
                echo "          via: $VIA" | sudo tee -a "$NETPLAN_FILE" > /dev/null
            fi
        done
    fi

    # Add DNS if provided
    if [[ -n "$DNS" ]]; then
        echo "      nameservers:" | sudo tee -a "$NETPLAN_FILE" > /dev/null
        echo "        addresses: [${DNS// /, }]" | sudo tee -a "$NETPLAN_FILE" > /dev/null
    fi

    log_success "Configuration added for adapter '$ADAPTER'."

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
# === Optional Router Setup ===
read -p "Do you want to make this machine act as a router? (y/n): " IS_ROUTER
if [[ "$IS_ROUTER" =~ ^[Yy]$ ]]; then
    log_info "Enabling IP forwarding temporarily..."
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
    cat /proc/sys/net/ipv4/ip_forward

    log_info "Making IP forwarding permanent in /etc/sysctl.conf..."
    sudo cp /etc/sysctl.conf /etc/sysctl.conf.original
    sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sudo grep "^net.ipv4.ip_forward" /etc/sysctl.conf

    # === Setup NAT using nftables ===
    log_info "Setting up NAT using nftables..."
    sudo nft flush ruleset
    sudo nft add table ip nat
    sudo nft add chain ip nat POSTROUTING '{ type nat hook postrouting priority 100; policy accept; }'

    read -p "Enter the outbound interface for NAT (e.g., ens33): " OUT_IFACE
    if [[ -z "$OUT_IFACE" ]]; then
        log_error "No interface entered. Cannot continue router setup."
        exit 1
    fi
    sudo nft add rule ip nat POSTROUTING oifname "$OUT_IFACE" counter masquerade
    sudo nft list ruleset | sudo tee /etc/nftables.ruleset > /dev/null
    cat /etc/nftables.ruleset

    # === Set up persistent dispatcher hook ===
    log_info "Setting up persistence for nftables using dispatcher hook..."
    sudo mkdir -p /etc/networkd-dispatcher/routable.d
    sudo touch /etc/networkd-dispatcher/routable.d/50-ifup.hooks
    sudo chmod a+x /etc/networkd-dispatcher/routable.d/50-ifup.hooks

    read -p "Do you want this router NAT setup to persist across reboots? (y/n): " MAKE_PERSISTENT
    if [[ "$MAKE_PERSISTENT" =~ ^[Yy]$ ]]; then
        sudo bash -c 'cat > /etc/networkd-dispatcher/routable.d/50-ifup.hooks' << 'EOF'
#!/bin/bash
/usr/sbin/nft flush ruleset
/usr/sbin/nft --file /etc/nftables.ruleset
EOF
        log_success "Persistence enabled: nftables rules will be reloaded on interface up."
    else
        log_info "Persistence skipped. NAT rules will not survive reboot."
    fi
fi


log_success "Setup complete!"
echo -e "Hostname set to: ${YELLOW}$VM_NAME${RESET}"
echo -e "The custom prompt has been configured to: ${BLUE}${COURSE_NAME}-${MAGENTA}${VM_NAME}-${YELLOW}${USERNAME}${RESET} ${GREEN}<Current Date/Time>${RESET} \$ "
echo -e "${YELLOW}IMPORTANT:${RESET} To see the new prompt in this current terminal session, you MUST run:"
echo -e "${YELLOW}  source ~/.bashrc${RESET}"
echo -e "${YELLOW}Or simply close and reopen your terminal. ${RESET}"
echo -e "All other system configurations (updates, tools, hostname, network) are already active."
echo -e "${RED}This script has been created by Thuruvan Thavapaln and with the help of AI :-)"
