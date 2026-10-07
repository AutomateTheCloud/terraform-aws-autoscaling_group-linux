#!/bin/bash
# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Mounts an Amazon EFS file system with encryption in transit (TLS), now and at every boot.
# Usage: mount-efs <efs-utils|stunnel> <file system ID> <mount point> <file system DNS name>
#
# efs-utils: the Amazon EFS client, packaged for Amazon Linux.
# stunnel:   for Ubuntu, where the Amazon EFS client is not packaged. stunnel opens the TLS
#            connection to the file system, checking its certificate and name, and NFS
#            connects through it on 127.0.0.1.
set -euo pipefail
METHOD=$1 FS_ID=$2 MOUNT_POINT=$3 FS_DNS=$4
STUNNEL_PORT=20049
mkdir -p "$MOUNT_POINT"

case "$METHOD" in
  efs-utils)
    entry="$FS_ID:/ $MOUNT_POINT efs _netdev,noresvport,tls 0 0"
    ;;
  stunnel)
    cat > /etc/stunnel/efs.conf <<CONF
foreground = yes
pid =
[efs]
client = yes
accept = 127.0.0.1:$STUNNEL_PORT
connect = $FS_DNS:2049
sslVersion = TLSv1.2
verifyChain = yes
CAfile = /etc/ssl/certs/ca-certificates.crt
checkHost = $FS_DNS
renegotiation = no
TIMEOUTclose = 0
TIMEOUTidle = 43200
CONF
    cat > /etc/systemd/system/efs-stunnel.service <<UNIT
[Unit]
Description=TLS tunnel to Amazon EFS file system $FS_ID
After=network-online.target
Wants=network-online.target
Before=remote-fs-pre.target
Wants=remote-fs-pre.target

[Service]
ExecStart=/usr/bin/stunnel /etc/stunnel/efs.conf
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now efs-stunnel.service
    entry="127.0.0.1:/ $MOUNT_POINT nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,port=$STUNNEL_PORT,_netdev,x-systemd.requires=efs-stunnel.service 0 0"
    ;;
  *)
    echo "unknown method $METHOD" >&2
    exit 2
    ;;
esac

# Replace any earlier entry for the mount point, then mount it.
grep -v " $MOUNT_POINT " /etc/fstab > /etc/fstab.new || true
echo "$entry" >> /etc/fstab.new
mv /etc/fstab.new /etc/fstab
systemctl daemon-reload
mountpoint -q "$MOUNT_POINT" || mount "$MOUNT_POINT"
