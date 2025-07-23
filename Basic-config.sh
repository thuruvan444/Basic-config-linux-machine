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
log_info "Prompting for basic system details..."
read -p "Enter your Username: " USERNAME

# Validate Username
if ! id "$USERNAME" &>/dev/null; then
    log_error "User '$USERNAME' does not exist. Please create the user first or enter an existing one. Exiting."
    exit 1
fi

read -p "Enter VM Name (e.g., L1VM): " VM_NAME

# === Set Hostname ===
log_info "Setting hostname to '$VM_NAME'..."
if sudo hostnamectl set-hostname "$VM_NAME"; then
    log_success "Hostname set to '$VM_NAME'."
else
    log_error "Failed to set hostname. Exiting."
    exit 1
fi

# === Optional Terminal Prompt Customization ===
read -p "Do you want to customize the terminal prompt for the user? (y/n): " DO_PROMPT
if [[ "$DO_PROMPT" =~ ^[Yy]$ ]]; then
    read -p "Enter Course Name (e.g., SRT411): " COURSE_NAME

    BASHRC_FILE="/home/$USERNAME/.bashrc"
    log_info "Configuring custom terminal prompt for user '$USERNAME'..."

    if [ ! -f "$BASHRC_FILE" ]; then
        log_error ".bashrc not found for user $USERNAME. Creating one."
        touch "$BASHRC_FILE"
        chown "$USERNAME":"$USERNAME" "$BASHRC_FILE"
    fi

    if grep -q "Custom prompt" "$BASHRC_FILE"; then
        log_info "Existing custom prompt found. Backing up .bashrc to ${BASHRC_FILE}.bak"
        cp "$BASHRC_FILE" "${BASHRC_FILE}.bak"
        sudo sed -i '/# Custom prompt/,/^PS1=.*$/d' "$BASHRC_FILE"
    fi

    cat << EOF | sudo tee -a "$BASHRC_FILE"

# Custom prompt
PS1="${BLUE}${COURSE_NAME}-${MAGENTA}${VM_NAME}-${YELLOW}${USERNAME}${RESET} ${GREEN}\\$(date +%a\\ %b\\ %d\\ -\\ %H:%M:%S)${RESET} \\$ "
EOF
    log_success "Custom terminal prompt configured."
else
    log_info "Skipped terminal prompt customization by user choice."
fi


# Custom prompt
PS1="${BLUE}${COURSE_NAME}-${MAGENTA}${VM_NAME}-${YELLOW}${USERNAME}${RESET} ${GREEN}\$(date +%a\ %b\ %d\ -\ %H:%M:%S)${RESET} \$ "
EOF
    log_success "Custom terminal prompt configured."
else
    log_info "Skipped terminal prompt customization by user choice."
fi

# === Optional Network Interface Configuration ===
read -p "Do you want to configure network interfaces? (y/n): " DO_NETPLAN
if [[ "$DO_NETPLAN" =~ ^[Yy]$ ]]; then
    log_info "Configuring network interfaces."
    read -p "Enter the number of network adapters to configure: " NUM_ADAPTERS

    if ! [[ "$NUM_ADAPTERS" =~ ^[0-9]+$ ]] || [ "$NUM_ADAPTERS" -eq 0 ]; then
        log_error "Invalid number of adapters. Must be a positive integer. Exiting."
        exit 1
    fi

    NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
    log_info "Creating Netplan configuration file: $NETPLAN_FILE"
    echo "network:" | sudo tee $NETPLAN_FILE > /dev/null
    echo "  version: 2" | sudo tee -a $NETPLAN_FILE > /dev/null
    echo "  ethernets:" | sudo tee -a $NETPLAN_FILE > /dev/null

    for (( i=1; i<=NUM_ADAPTERS; i++ ))
    do
        echo -e "\n${YELLOW}--- Configuring adapter #$i ---${RESET}"
        read -p "  Adapter name (e.g., ens33): " ADAPTER
        read -p "  Static IP Address (e.g., 192.168.1.10): " IPADDR
        read -p "  Subnet Mask (e.g., 24): " NETMASK
        read -p "  Default Gateway (optional, press Enter to skip): " GATEWAY
        read -p "  DNS Servers (space separated, optional, press Enter to skip): " DNS
        read -p "  Static Routes (e.g., 192.168.5.0/24:192.168.2.1): " ROUTES

        sudo bash -c "cat >> '$NETPLAN_FILE'" << EOF
    $ADAPTER:
      dhcp4: no
      addresses: [$IPADDR/$NETMASK]
EOF
        if [[ -n "$GATEWAY" || -n "$ROUTES" ]]; then
            echo "      routes:" | sudo tee -a "$NETPLAN_FILE" > /dev/null
        fi

        if [[ -n "$GATEWAY" ]]; then
            echo "        - to: default" | sudo tee -a "$NETPLAN_FILE"
            echo "          via: $GATEWAY" | sudo tee -a "$NETPLAN_FILE"
        fi

        if [[ -n "$ROUTES" ]]; then
            IFS=',' read -ra ROUTE_ARRAY <<< "$ROUTES"
            for route_entry in "${ROUTE_ARRAY[@]}"; do
                DEST=$(echo "$route_entry" | cut -d':' -f1)
                VIA=$(echo "$route_entry" | cut -d':' -f2)
                echo "        - to: $DEST" | sudo tee -a "$NETPLAN_FILE"
                echo "          via: $VIA" | sudo tee -a "$NETPLAN_FILE"
            done
        fi

        if [[ -n "$DNS" ]]; then
            echo "      nameservers:" | sudo tee -a "$NETPLAN_FILE"
            echo "        addresses: [${DNS// /, }]" | sudo tee -a "$NETPLAN_FILE"
        fi

        log_success "Configuration added for adapter '$ADAPTER'."
    done

    log_info "Setting secure permissions for Netplan configuration file..."
    sudo chmod 600 "$NETPLAN_FILE" && sudo chown root:root "$NETPLAN_FILE"

    echo -e "\n${CYAN}Applying network configuration...${RESET}"
    if sudo netplan apply; then
        log_success "Network configuration applied successfully."
    else
        log_error "Failed to apply network configuration. Check Netplan logs for errors."
        exit 1
    fi
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

    log_info "Setting up NAT using nftables..."
    sudo nft flush ruleset
    sudo nft add table ip nat
    sudo nft add chain ip nat POSTROUTING '{ type nat hook postrouting priority 100; policy accept; }'

    read -p "Enter the outbound interface for NAT (e.g., ens33): " OUT_IFACE
    sudo nft add rule ip nat POSTROUTING oifname "$OUT_IFACE" counter masquerade
    sudo nft list ruleset | sudo tee /etc/nftables.ruleset

    log_info "Setting up persistence for nftables..."
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
echo -e "${RED}This script has been created by Thuruvan Thavapalan with the help of AI :-)"
