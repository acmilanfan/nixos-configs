#!/bin/bash
# Run as the GUI user, never root: repairing user-writable paths must not
# change ownership or permissions on a symlink/hardlink target as root.
set -euo pipefail

if [ "$#" -ne 1 ] || [ "$EUID" -eq 0 ]; then
    echo "usage: prepare-gui-logs LOG_DIRECTORY (run as the GUI user, not root)" >&2
    exit 1
fi

log_dir=$1
mkdir -p "$log_dir"
backup_dir=""

for name in darwin-startup.log darwin-startup.err.log \
    vicinae-em-keepalive.log vicinae-em-keepalive.err.log; do
    log="$log_dir/$name"
    if [ -L "$log" ] || { [ -e "$log" ] && [ ! -f "$log" ]; }; then
        echo "Refusing non-regular or symlinked GUI log: $log" >&2
        exit 1
    fi
    if [ -e "$log" ] && { [ ! -O "$log" ] || [ ! -w "$log" ]; }; then
        if [ -z "$backup_dir" ]; then
            backup_dir=$(mktemp -d "$log_dir/.darwin-startup-logs.XXXXXXXX")
        fi
        # Rename rather than truncate or chown: preserve the old inode/history.
        mv "$log" "$backup_dir/$name"
        echo "Preserved unwritable GUI log: $backup_dir/$name"
    fi
    (umask 077; : >> "$log")
done
