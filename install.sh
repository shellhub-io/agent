#!/bin/sh

ROOTFS_VERSION=${ROOTFS_VERSION:-v0.9.4}
ROOTFS_ARCH=$ROOTFS_ARCH

RUNC_VERSION=${RUNC_VERSION:-v1.1.3}
RUNC_ARCH=$RUNC_ARCH

INSTALL_DIR=/opt/shellhub
TMP_DIR=`mktemp -d`

# download the runc static binary for the specified arch
download_runc() {
    curl -fsSL "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${RUNC_ARCH}" --output $TMP_DIR/runc \
	&& chmod 755 $TMP_DIR/runc
}

# download the OCI runtime spec file
download_spec() {
    curl -fsSL "https://raw.githubusercontent.com/shellhub-io/agent/master/config.json" --output $TMP_DIR/config.json
}

# download the rootfs image for the specified arch
download_rootfs() {
    curl -fsSL https://transfer.sh/get/zcdzRO/rootfs.tar.gz --output $TMP_DIR/rootfs.tar.gz
}

# extract rootfs image into a directory
extract_rootfs() {
    mkdir -p $TMP_DIR/rootfs
    tar -C $TMP_DIR/rootfs -xzf $TMP_DIR/rootfs.tar.gz
    rm -f $TMP_DIR/rootfs.tar.gz
}

cleanup() {
    rm -rf $TMP_DIR
}

# Auto detect arch if it has not already been set
if [ -z "$RUNC_ARCH" ]; then
    case `uname -m` in
	x86_64)
	    RUNC_ARCH=amd64
	    ;;
    esac
fi

download_runc || { echo "Failed to download runc binary" && cleanup && exit 1; }
download_rootfs || { echo "Failed to download rootfs"; cleanup; exit 1; }
extract_rootfs || { echo "Failed to extract rootfs"; cleanup; exit 1; }
download_spec || { echo "Failed to download spec"; cleanup; exit 1; }

sed -i "s,__SHELLHUB_SERVER_ADDRESS__,$SHELLHUB_SERVER_ADDRESS,g" $TMP_DIR/config.json
sed -i "s,__SHELLHUB_TENANT_ID__,$SHELLHUB_TENANT_ID,g" $TMP_DIR/config.json
sed -i "s,__ROOT_PATH__,$INSTALL_DIR/rootfs,g" $TMP_DIR/config.json

mv $TMP_DIR $INSTALL_DIR || { echo "Failed to copy install files"; cleanup; exit 1; }

# Create systemd service unit
tee /etc/systemd/system/shellhub-agent.service > /dev/null <<EOF
[Unit]
Description=ShellHub Agent
Wants=network.target
After=local-fs.target network.target time-sync.target
Requires=local-fs.target

[Service]
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/runc run shellhub-agent
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable shellhub-agent
systemctl start shellhub-agent
