#!/bin/bash

if [[ $UID -ge 10000 ]]; then
    GID=$(id -g)
    sed -e "s/^postgres:x:[^:]*:[^:]*:/postgres:x:$UID:$GID:/" /etc/passwd > /tmp/passwd
    cat /tmp/passwd > /etc/passwd
    rm /tmp/passwd
fi

# Use /home/postgres/ssl for node certificate generation.
if [ ! -f /home/postgres/ssl/server.crt ]; then
    echo "Generating per-node TLS certificate using the shared CA..."
    mkdir -p /home/postgres/ssl
    # Generate node private key.
    openssl genrsa -out /home/postgres/ssl/server.key 2048
    # Create a CSR using the hostname as the Common Name.
    openssl req -new -key /home/postgres/ssl/server.key -out /tmp/server.csr -subj "/CN=$(hostname)"
    # Sign the certificate with the shared CA.
    ls /ca
    openssl x509 -req -in /tmp/server.csr -CA /ca/ca.crt -CAkey /ca/ca.key -CAcreateserial -CAserial /home/postgres/ca.srl -out /home/postgres/ssl/server.crt -days 365 -sha256
    rm -f /tmp/server.csr
fi

cat > /home/postgres/patroni.yml <<__EOF__
bootstrap:
  dcs:
    postgresql:
      use_pg_rewind: true
      pg_hba:
      - host all all 0.0.0.0/0 md5
      - host replication ${PATRONI_REPLICATION_USERNAME} ${PATRONI_KUBERNETES_POD_IP}/16 md5
      - host replication ${PATRONI_REPLICATION_USERNAME} 127.0.0.1/32 md5
  initdb:
  - auth-host: md5
  - auth-local: trust
  - encoding: UTF8
  - locale: en_US.UTF-8
  - data-checksums
restapi:
  connect_address: '${PATRONI_KUBERNETES_POD_IP}:8008'
postgresql:
  connect_address: '${PATRONI_KUBERNETES_POD_IP}:5432'
  authentication:
    superuser:
      password: '${PATRONI_SUPERUSER_PASSWORD}'
    replication:
      password: '${PATRONI_REPLICATION_PASSWORD}'
__EOF__

unset PATRONI_SUPERUSER_PASSWORD PATRONI_REPLICATION_PASSWORD

exec /usr/bin/python3 /usr/local/bin/patroni /home/postgres/patroni.yml
