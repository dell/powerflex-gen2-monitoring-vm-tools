#!/usr/bin/env bash
# Copyright 2026 Brian Dean
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
#  configure_gw_rest_ip.sh – verify gateway reachability and credentials
# ----------------------------------------------------------------------

# -------------------------------------------------
#  1.  Prompt for the gateway IP / ingress IP and credentials
# -------------------------------------------------
read -p "Please enter either the PowerFlex Gateway IP or the cluster ingress IP: " gwip
read -p "Please enter a PowerFlex cluster user (e.g. admin or monitor): " gwuser
read -s -p "Please enter the PowerFlex user's password: " gwpass
echo    # newline after hidden password entry

# -------------------------------------------------
#  2.  Build the login URL
# -------------------------------------------------
URL="https://$gwip/rest/auth/login"  

echo -e "\nTesting the PowerFlex REST API at $URL …\n"

# -------------------------------------------------
# Helper functions to verify the IP is reachable and that the credentials are good. If not, make the user re-enter the information.
# -------------------------------------------------

function checkgw_ip {
     if [ $ip_resp -eq 0 ]; then
         echo -e "\n *** The PowerFlex REST API can be reached at this address\n"
         else
            if [ $ip_resp -eq 6 ]; then
                echo -e "An error occurred getting $URL - Unable to resolve PowerFlex Gateway/Ingress DNS\n\nPlease re-enter the IP and credentials\n"; exec "/root/tools/configure_gw_rest_ip.sh"
         else
            if [ $ip_resp -eq 7 ]; then
                echo -e "An error occurred getting $URL - Unable to connect to PowerFlex Gateway/Ingress at $gwip\n\nPlease re-enter the IP and credentials\n"; exec "/root/tools/configure_gw_rest_ip.sh"
         else
            if [ $ip_resp -eq 28 ]; then
                echo -e "An error occurred getting $URL - Seems unreachable. Operation timed out\n\nPlease re-enter the IP and credentials\n"; exec "/root/tools/configure_gw_rest_ip.sh"
            fi
          fi
        fi
     fi
}

function checkgw_creds {
     if [ $auth_resp -eq 200 ]; then
         echo -e " *** The credentials entered for the PowerFlex REST API authenticated successfully.\n"
         else
            if [ $auth_resp -eq 401 ]; then
                echo -e " *** But an error occurred authenticating with the User and Pass given.\n\n  Please re-enter the IP and credentials:\n"; exec "/root/tools/configure_gw_rest_ip.sh"
            fi
     fi
}

function checkgw_gen2 {
    if [ -z "$access_token" ]; then
        echo -e " *** WARNING: Could not obtain access token. Skipping Gen2 cluster validation.\n"
        return
    fi

    inventory=$(curl -k -s -m 10 \
        -H "Authorization: Bearer $access_token" \
        "https://$gwip/api/instances")

    gen_check=$(echo "$inventory" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    sps = data.get("storagePoolList", [])
    if not sps:
        print("NO_SPS")
    else:
        types = set(sp.get("dataLayout", "unknown") for sp in sps)
        parts = []
        for sp in sps:
            n = sp.get("name", "unknown")
            d = sp.get("dataLayout", "unknown")
            parts.append(n + " (" + d + ")")
        names = ", ".join(parts)
        if types & {"FineGranularity", "MediumGranularity"}:
            print("GEN1:" + names)
        elif types.issubset({"ErasureCoding"}):
            print("OK:" + names)
        else:
            print("UNKNOWN:" + names)
except Exception as e:
    print("ERROR:" + str(e))
' 2>/dev/null)

    case "$gen_check" in
        OK:*)
            echo -e " *** Gen2 (Erasure Coding) cluster confirmed. All storage pools use Erasure Coding."
            echo -e "     ${gen_check#OK:}\n"
            ;;
        GEN1:*)
            echo -e " *** ERROR: This toolkit requires a PowerFlex Gen2 cluster with Erasure Coding."
            echo -e "     Storage pools found: ${gen_check#GEN1:}"
            echo -e "     Fine/Medium Granularity storage pools indicate a Gen1 (Mirroring) cluster.\n"
            echo -e "     There is a monitoring toolkit available for PowerFlex Gen1 clusters.\n"
            exit 1
            ;;
        NO_SPS)
            echo -e " *** WARNING: No storage pools found on the cluster. Cannot verify Gen2 status.\n"
            ;;
        UNKNOWN:*)
            echo -e " *** ERROR: This toolkit requires a PowerFlex Gen2 cluster with Erasure Coding."
            echo -e "     Storage pools found: ${gen_check#UNKNOWN:}"
            echo -e "     Unrecognized storage pool layout type(s) detected. Cannot confirm Gen2 status.\n"
            exit 1
            ;;
        *)
            echo -e " *** WARNING: Could not determine cluster generation. Inventory query failed.\n"
            ;;
    esac
}

# -------------------------------------------------
#  3.  Verify the host is reachable (basic curl test)
# -------------------------------------------------
curl -k -s -o /dev/null -m 3 --basic --user "$gwuser:$gwpass" "$URL"
ip_resp=$?
# Uncomment the line below to debug the curl reponse codes
#echo -e "Reachability response code = $ip_resp\n"

# -------------------------------------------------
#  4.  Verify the credentials (JSON POST)
# -------------------------------------------------
# Build a properly‑escaped JSON payload
json_payload=$(printf '{"username":"%s","password":"%s"}' "$gwuser" "$gwpass")

auth_full=$(curl -k \
                -s -w '\n%{http_code}' \
                -m 3 \
                -X POST \
                -H "Content-Type: application/json" \
                -d "$json_payload" \
                "$URL")

auth_resp=$(echo "$auth_full" | tail -1)
auth_body=$(echo "$auth_full" | sed '$d')
access_token=$(echo "$auth_body" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)

# Uncomment the line below to debug the HTTP reponse codes
#echo -e "Authentication HTTP response code = $auth_resp\n"

# -------------------------------------------------
#  5.  Run the helper checks 
# -------------------------------------------------
checkgw_ip
checkgw_creds
checkgw_gen2

# -------------------------------------------------
#  6.  Store the verified values in clusters.yaml
# -------------------------------------------------
sed -i "s/__My_Gateway_IP__/$gwip/g"   /var/local/telegraf-powerflex/clusters.yaml
sed -i "s/__My_MDM_User__/$gwuser/g"  /var/local/telegraf-powerflex/clusters.yaml
sed -i "s/__My_MDM_Password__/$gwpass/g" /var/local/telegraf-powerflex/clusters.yaml

exit 0
