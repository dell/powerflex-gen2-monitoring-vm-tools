#! /bin/bash

# Graceful method - Restart the services in order

/usr/bin/systemctl stop grafana-server
/usr/bin/systemctl stop telegraf
/usr/bin/systemctl stop influxdb

sleep 3

/usr/bin/systemctl start influxdb
/usr/bin/systemctl start telegraf
/usr/bin/systemctl start grafana-server
