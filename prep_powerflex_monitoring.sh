#!/usr/bin/env bash
# Copyright 2026 Dell, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

# ----------------------------------------------------------------------
#  prep_powerflex_monitoring.sh – Ensure the PowerFlex monitoring tools have not previously been configured on this system.
#  If they have, abort the script. If not, continue with the configuration process.
# ----------------------------------------------------------------------

# -------------------------------------------------
#  1.  Verify the PowerFlex monitoring tools have not previously been configured.
# -------------------------------------------------

if [[ -f ~/.configured ]]
then
    ans="N"
    echo -e "\n$(tput setaf 1)** This system has been previously configured with this script. It is not designed for re-use.\n"
    echo -e " * To change the current configuration, edit the file /var/local/telegraf-powerflex/clusters.yaml."
    echo -e " * To add another cluster, first add another entry to clusters.yaml." 
    echo -e " * Then edit /etc/telegraf/telegraf.d/powerflex-telegraf-influxdb.conf and restart the telegraf service.\n"
    tput sgr0
    echo -n "Press any key to exit. "
    read -t 30 -n 1 ans
    case $ans in
        *)
            echo ""
            echo -e "\nAborting configuration.\n"
            exit 1
            ;;
    esac
fi

# -------------------------------------------------
#  2.  Configure static IP address via NetworkManager (nmcli).
# -------------------------------------------------

echo -e "****************************************************************"
echo -e "***        Configure Static IP Address                      ***"
echo -e "****************************************************************\n\n"

# Discover the first wired (ethernet) connection managed by NetworkManager
NM_CON=$(nmcli -t -f NAME,TYPE connection show | grep ':.*ethernet' | head -1 | cut -d: -f1)
if [[ -z $NM_CON ]]; then
    echo -e "$(tput setaf 1)Error: No ethernet connection found in NetworkManager.\n"
    echo -e "Please ensure NetworkManager is running and an ethernet device is available.$(tput sgr0)\n"
    echo -n "Press any key to exit. "
    read -t 30 -n 1 ans
    echo -e "\nAborting configuration.\n"
    exit 1
fi

NM_DEV=$(nmcli -t -f GENERAL.DEVICE connection show "$NM_CON" 2>/dev/null | cut -d: -f2)
echo -e "Detected NetworkManager connection: $(tput setaf 6)${NM_CON}$(tput sgr0) on device $(tput setaf 6)${NM_DEV}$(tput sgr0)\n"

# Check if a static IP is already configured
current_method=$(nmcli -t -f ipv4.method connection show "$NM_CON" | cut -d: -f2)
current_ip=$(nmcli -t -f ipv4.addresses connection show "$NM_CON" | cut -d: -f2)
current_gateway=$(nmcli -t -f ipv4.gateway connection show "$NM_CON" | cut -d: -f2)
current_dns=$(nmcli -t -f ipv4.dns connection show "$NM_CON" | cut -d: -f2)

if [[ $current_method == "manual" ]] && [[ -n $current_ip ]]; then
    echo -e "$(tput setaf 3)A static IP configuration is already present:$(tput sgr0)"
    echo -e "  Address: $current_ip"
    [[ -n $current_gateway ]] && echo -e "  Gateway: $current_gateway"
    [[ -n $current_dns ]]     && echo -e "  DNS:     $current_dns"
    echo -e ""

    while true; do
        echo -n "Would you like to (S)kip this step and proceed with monitoring configuration, (C)hange the current IP configuration, or (A)bort? [C/S/A]: "
        read -n 1 choice
        echo ""
        case $choice in
            [Cc]* )
                echo -e "\n$(tput setaf 2)Proceeding with IP configuration change.$(tput sgr0)\n"
                break
                ;;
            [Ss]* )
                echo -e "\n$(tput setaf 2)Skipping IP configuration.$(tput sgr0)\n"
                goto_step3=true
                break 2
                ;;
            [Aa]* )
                echo -e "\nAborting configuration.\n"
                exit 1
                ;;
            * )
                echo -e "$(tput setaf 1)Invalid choice. Please enter C, S, or A.$(tput sgr0)\n"
                ;;
        esac
    done
else
    echo -e "$(tput setaf 2)No static IP configuration found. Proceeding with new configuration.$(tput sgr0)\n"
fi

if [[ $goto_step3 == true ]]; then
    # Skip to step 3 - PowerFlex monitoring configuration
    goto_step3=""
else
    echo -e "Let's configure a static IP address for ${NM_CON}:\n"

# Get IP address
while true; do
    echo -n "Enter the desired static IP address (e.g., 192.168.1.100): "
    read ip_addr
    if [[ $ip_addr =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        break
    else
        echo -e "$(tput setaf 1)Invalid IP address format. Please try again.$(tput sgr0)\n"
    fi
done

# Get netmask (will be converted to PREFIX)
while true; do
    echo -n "Enter the netmask (e.g., 255.255.255.0) or prefix (e.g., 24): "
    read netmask
    if [[ $netmask =~ ^[0-9]+$ ]] && [[ $netmask -ge 0 ]] && [[ $netmask -le 32 ]]; then
        prefix=$netmask
        break
    elif [[ $netmask =~ ^255\.255\.255\.[0-9]{1,3}$ ]] || [[ $netmask =~ ^255\.255\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || [[ $netmask =~ ^255\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        case $netmask in
            255.255.255.255) prefix=32 ;;
            255.255.255.254) prefix=31 ;;
            255.255.255.252) prefix=30 ;;
            255.255.255.248) prefix=29 ;;
            255.255.255.240) prefix=28 ;;
            255.255.255.224) prefix=27 ;;
            255.255.255.192) prefix=26 ;;
            255.255.255.128) prefix=25 ;;
            255.255.255.0) prefix=24 ;;
            255.255.254.0) prefix=23 ;;
            255.255.252.0) prefix=22 ;;
            255.255.248.0) prefix=21 ;;
            255.255.240.0) prefix=20 ;;
            255.255.224.0) prefix=19 ;;
            255.255.192.0) prefix=18 ;;
            255.255.128.0) prefix=17 ;;
            255.255.0.0) prefix=16 ;;
            255.254.0.0) prefix=15 ;;
            255.252.0.0) prefix=14 ;;
            255.248.0.0) prefix=13 ;;
            255.240.0.0) prefix=12 ;;
            255.224.0.0) prefix=11 ;;
            255.192.0.0) prefix=10 ;;
            255.128.0.0) prefix=9 ;;
            255.0.0.0) prefix=8 ;;
            *) prefix=24 ;;
        esac
        break
    else
        echo -e "$(tput setaf 1)Invalid netmask or prefix format. Please try again.$(tput sgr0)\n"
    fi
done

# Get gateway
while true; do
    echo -n "Enter the gateway IP address (e.g., 192.168.1.1) or press Enter to skip this step: "
    read gateway
    if [[ -z $gateway ]]; then
        gateway=""
        break
    elif [[ $gateway =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        break
    else
        echo -e "$(tput setaf 1)Invalid gateway IP address format. Please try again.$(tput sgr0)\n"
    fi
done

# Get DNS server
while true; do
    echo -n "Enter the DNS server IP address (e.g., 8.8.8.8) or press Enter to skip this step: "
    read dns_server
    if [[ -z $dns_server ]]; then
        dns_server=""
        break
    elif [[ $dns_server =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        break
    else
        echo -e "$(tput setaf 1)Invalid DNS server IP address format. Please try again.$(tput sgr0)\n"
    fi
done

# Apply the configuration via nmcli
echo -e "\nApplying static IP configuration to connection '${NM_CON}':"
echo -e "  Address: $ip_addr/$prefix"
[[ -n $gateway ]]    && echo -e "  Gateway: $gateway"
[[ -n $dns_server ]] && echo -e "  DNS:     $dns_server"

nmcli con mod "$NM_CON" ipv4.method manual ipv4.addresses "$ip_addr/$prefix"
[[ -n $gateway ]]    && nmcli con mod "$NM_CON" ipv4.gateway "$gateway"
[[ -n $dns_server ]] && nmcli con mod "$NM_CON" ipv4.dns "$dns_server"

echo -e "\n$(tput setaf 2)Static IP configuration completed.$(tput sgr0)"
echo -e "Activating connection to apply changes...\n"

nmcli con up "$NM_CON"

echo -e "\nConnection reactivated.\n"

# Display the new IP address
new_ip=$(nmcli -t -f IP4.ADDRESS device show "$NM_DEV" 2>/dev/null | head -1 | cut -d: -f2)
echo -e "The new IP address is: ${new_ip}\n"

fi

# -------------------------------------------------
#  3.  Prompt for the gateway IP / ingress IP and credentials; verify they are correct; write to configuration file; restart services.
# -------------------------------------------------

echo -e "****************************************************************"
echo -e "***      Now let's configure the PowerFlex monitoring tools.     ***"
echo -e "****************************************************************\n\n"
( "/root/tools/configure_gw_rest_ip.sh" )

touch ~/.configured

# -------------------------------------------------
#  3c. Generate a unique TLS certificate for Grafana, replacing the demo cert.
#      Pass the current IP address so it can be included as a SAN.
# -------------------------------------------------

current_ip=$(hostname -I | awk '{print $1}')
( "/root/tools/generate_grafana_cert.sh" "$current_ip" )

echo -e "****************************************************************"
echo -e "***  Please wait. Restarting PowerFlex Monitoring Services.  ***"
echo -e "****************************************************************\n\n"

# Graceful method - Restart the services in order
/usr/bin/systemctl stop grafana-server
/usr/bin/systemctl stop telegraf
/usr/bin/systemctl stop influxdb

sleep 3

/usr/bin/systemctl start influxdb
/usr/bin/systemctl start telegraf
/usr/bin/systemctl start grafana-server

# -------------------------------------------------
#  3b. Set InfluxDB retention policy (6 months, 7-day shards).
#      The telegraf database is auto-created by Telegraf with an infinite
#      retention policy. We ALTER it here to enforce a 26-week (≈6 month)
#      retention so old shards are dropped automatically.
# -------------------------------------------------

echo -e "Configuring InfluxDB retention policy..."
for i in $(seq 1 30); do
    if influx -execute 'SHOW DATABASES' 2>/dev/null | grep -q '^telegraf$'; then
        influx -execute 'ALTER RETENTION POLICY "autogen" ON "telegraf" DURATION 26w SHARD DURATION 1w'
        echo -e "$(tput setaf 2)Retention policy set: 26 weeks (≈6 months), 7-day shards.$(tput sgr0)\n"
        break
    fi
    sleep 2
done

# -------------------------------------------------
#  4. Provide the URL(s) for logging in to the dashboards.
# -------------------------------------------------

echo -e "***************************************************************************"
echo -e "***  $(tput setaf 2)Done. Please login to the Grafana dashboards at the following URL:$(tput sgr0) ***"
ips=$(hostname -I)
for ip in $ips; do
    echo -e "***  https://$ip  ***"
done
echo -e "***  Default username: admin  ***"
echo -e "***  Default password: powerflex  ***"
echo -e "***************************************************************************\n\n"

exit 0
