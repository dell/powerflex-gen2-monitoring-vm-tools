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
#  generate_grafana_cert.sh - Generate a unique self-signed TLS certificate
#  for Grafana HTTPS. Replaces the demo certificate shipped with the VM.
# ----------------------------------------------------------------------

CERT_DIR="/etc/grafana"
CERT_FILE="${CERT_DIR}/powerflex.crt"
KEY_FILE="${CERT_DIR}/powerflex.key"
CERT_DAYS=3650
KEY_BITS=4096

# Use the IP address passed as argument, or fall back to hostname
IP_ADDR="${1:-}"
CN="PowerFlex Monitoring"

echo -e "Generating unique TLS certificate for Grafana..."

if [[ -n "${IP_ADDR}" ]]; then
    # Include the IP as a Subject Alternative Name
    openssl req -x509 -nodes -days ${CERT_DAYS} -newkey rsa:${KEY_BITS} \
        -keyout "${KEY_FILE}" \
        -out "${CERT_FILE}" \
        -subj "/CN=${CN}" \
        -addext "subjectAltName=IP:${IP_ADDR}" \
        2>/dev/null
else
    openssl req -x509 -nodes -days ${CERT_DAYS} -newkey rsa:${KEY_BITS} \
        -keyout "${KEY_FILE}" \
        -out "${CERT_FILE}" \
        -subj "/CN=${CN}" \
        2>/dev/null
fi

if [[ $? -eq 0 ]]; then
    chmod 600 "${KEY_FILE}"
    chmod 644 "${CERT_FILE}"
    chown grafana:grafana "${CERT_FILE}" "${KEY_FILE}" 2>/dev/null
    echo -e "$(tput setaf 2)TLS certificate generated successfully.$(tput sgr0)"
    echo -e "  Certificate: ${CERT_FILE}"
    echo -e "  Private key: ${KEY_FILE}\n"
else
    echo -e "$(tput setaf 1)ERROR: Failed to generate TLS certificate.$(tput sgr0)"
    echo -e "Grafana will fall back to the demo certificate if one exists.\n"
fi
