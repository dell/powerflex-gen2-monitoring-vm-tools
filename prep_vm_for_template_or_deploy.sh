#! /bin/bash
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

# Prepare Monitoring VM for Template or re-deployment
# Grab a snapshot before running this, so we can revert to where we left off.

# Stop collection and UI of the monitoring services, if running.
/usr/bin/systemctl stop grafana-server
/usr/bin/systemctl stop telegraf

# Drop the telegraf database - it will be recreated upon first configuration and startup
/usr/bin/influx --execute 'drop database telegraf'
# Stop the InfluxDB service
/usr/bin/systemctl stop influxdb

# Clean out YUM/DNF
/usr/bin/dnf clean all

# Remove the .configured file, if it was there while developing
/usr/bin/rm -f /root/.configured

# Force the logs to rotate and delete old cruft.
/usr/sbin/logrotate -f /etc/logrotate.conf
/usr/bin/rm -f /var/log/*-???????? /var/log/*.gz /var/log/*/*-???????? /var/log/grafana/grafana.log.????-??-??*

# Remove compiled python remnants and __pycache__ directories
/usr/bin/rm -f /var/local/telegraf-powerflex/*.pyc /var/local/telegraf-powerflex/sio_sdk/*.pyc
/usr/bin/rm -rf /var/local/telegraf-powerflex/__pycache__ /var/local/telegraf-powerflex/sio_sdk/__pycache__ /var/local/telegraf-powerflex/tests/__pycache__

# Clear the audit log & wtmp.
/usr/bin/cat /dev/null > /var/log/audit/audit.log
/usr/bin/cat /dev/null > /var/log/wtmp

# Truncate active logs not caught by the logrotate glob
> /var/log/messages
> /var/log/secure
> /var/log/cron
> /var/log/btmp
> /var/log/lastlog
> /var/log/dnf.log
> /var/log/dnf.librepo.log
> /var/log/dnf.rpm.log
> /var/log/tuned/tuned.log

# Remove installer logs (no longer needed post-build)
rm -rf /var/log/anaconda

# Remove VMware tools logs
rm -f /var/log/vmware-*.log

# Truncate journal
journalctl --rotate --vacuum-time=1s

# Clean /tmp out.
/usr/bin/rm -rf /tmp/*
/usr/bin/rm -rf /var/tmp/*

# Clean out root user authorized ssh keys
> /root/.ssh/authorized_keys

# Remove host SSH identity keys and re-generate on first boot
rm -f /etc/ssh/ssh_host_*

# Reset machine-id (systemd-firstboot will regenerate on next boot)
> /etc/machine-id

# Clean out development artifacts in /root/
rm -rf /root/.codeium /root/.windsurf* /root/CascadeProjects

# Reset all ethernet connections back to DHCP (removes static IP, gateway, DNS)
for con in $(nmcli -t -f NAME,TYPE connection show | grep ':.*ethernet' | cut -d: -f1); do
    nmcli con mod "$con" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
done

# Set the clusters.yaml file back to preconfigured state
/usr/bin/cp -f /root/tools/clusters.yaml.template /var/local/telegraf-powerflex/clusters.yaml

# # Write zeroes to the whole disk so we can punch them out later. Only needed on old VMFS5 volumes
#dd if=/dev/zero of=/root/zeroes bs=1M; sleep 1;rm -f /root/zeroes
#sleep 5

# trim the disk
fstrim -av

# Remove the influx cli history
> /root/.influx_history

# Remove the root user’s shell history
> /root/.bash_history
unset HISTFILE

echo ""
echo "All finished cleaning up!"
echo "Don't forget to run 'history -c'"
