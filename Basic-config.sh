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
