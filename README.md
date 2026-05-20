# Gen2 PowerFlex Monitoring VM Tools

This project contains setup and configuration tools for deploying a PowerFlex Gen2 monitoring virtual machine. 
In the pre-packed VM,  which is provided as a release artifact for the base projct at https://github.com/dell/powerflex-gen2-monitoring, these tools live in the /root/tools directory.

## Scripts Overview

### Main Setup Scripts

- **`prep_powerflex_monitoring.sh`** - Primary configuration script that:
  - Verifies the system hasn't been previously configured
  - Configures static IP address via NetworkManager
  - Prompts for PowerFlex gateway/ingress IP and credentials
  - Validates Gen2 cluster compatibility (Erasure Coding only)
  - Sets up InfluxDB retention policy (6 months)
  - Provides Grafana dashboard URLs for access

- **`configure_gw_rest_ip.sh`** - Gateway configuration helper that:
  - Collects PowerFlex gateway/ingress IP and credentials
  - Tests REST API reachability and authentication
  - Validates cluster is Gen2 with Erasure Coding storage pools
  - Stores verified configuration in `clusters.yaml`

### Utility Scripts

- **`prep_vm_for_template_or_deploy.sh`** - VM preparation script that:
  - Stops all monitoring services
  - Cleans logs, cache, and temporary files
  - Resets network configuration to DHCP
  - Removes SSH keys and machine-specific identifiers
  - Prepares VM for use as a deployment template

- **`generate_grafana_cert.sh`** - TLS certificate generation script that:
  - Generates a unique self-signed RSA 4096-bit certificate for Grafana HTTPS
  - Includes the VM's IP address as a Subject Alternative Name (SAN)
  - Called automatically by `prep_powerflex_monitoring.sh` during first setup

### Configuration Files

- **`clusters.yaml.template`** - Template for PowerFlex cluster configuration:
  - Placeholder variables for gateway IP, username, and password
  - Used by VM prep script to generate expected `clusters.yaml`

- **`etc-issue-copy-el9`** - Login banner template for Enterprise Linux 9:
  - Displays VM information and setup instructions in console login banner
  - Provides default credentials and guidance for users

## Requirements

- PowerFlex Gen2 cluster with Erasure Coding storage pools
- Network access to PowerFlex REST API (gateway or ingress IP)
- Valid PowerFlex user credentials (monitor-role user recommended)

## Notes

- Scripts are designed for one-time configuration use
- Cluster configuration changes after setup should be made via `/var/local/telegraf-powerflex/clusters.yaml`
- InfluxDB retention is set to 6 months with 7-day shards
- Gen1 (Mirroring) clusters are not supported - use the Gen1 toolkit instead
