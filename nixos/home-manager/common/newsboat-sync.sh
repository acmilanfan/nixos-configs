# Synced-cache wrapper for newsboat.
#
# The authoritative cache lives locally and is never touched by the cloud
# sync daemon. A portable copy lives in the synced folder and is only
# written by this script while no newsboat process has the database open,
# which makes SQLite corruption impossible.
#
# Deployed via writeShellScriptBin (shebang prepended there).
set -u

SYNC_DB="$HOME/Nextcloud/newsboat/cache.db"
LOCAL_DB="$HOME/.local/share/newsboat/cache.db"
STAGING_DIR="$HOME/.cache/newsboat-sync"
URLS_FILE="$HOME/org/rss"

db_is_healthy() {
    sqlite3 "$1" "PRAGMA integrity_check;" 2>/dev/null | grep -q '^ok$'
}

pull_and_check() {
    # Returns 0 only if the synced copy was pulled down and verified.
    if [ ! -f "$SYNC_DB" ]; then
        return 1
    fi
    if db_is_healthy "$SYNC_DB"; then
        cp "$SYNC_DB" "$LOCAL_DB.part" \
            && mv -f "$LOCAL_DB.part" "$LOCAL_DB"
        return 0
    else
        echo "WARNING: synced cache is malformed, refusing to use it." >&2
        echo "         Continuing with the local copy at $LOCAL_DB." >&2
        echo "         Recover the synced copy from Nextcloud versions if" >&2
        echo "         the local one is not up to date." >&2
        return 1
    fi
}

mkdir -p "$STAGING_DIR" "$(dirname "$LOCAL_DB")"

# Pull: prefer the synced copy only if it is present and strictly newer.
if [ ! -f "$LOCAL_DB" ] || [ "$SYNC_DB" -nt "$LOCAL_DB" ]; then
    if pull_and_check; then
        echo "newsboat-sync: pulled fresh cache from Nextcloud."
    fi
fi

# Run the real newsboat (blocking). Args pass through, so "-x" still works.
newsboat --url-file="$URLS_FILE" --cache-file="$LOCAL_DB" "$@"
rc=$?

# Push: only push a healthy local cache.
if [ ! -f "$LOCAL_DB" ]; then
    :  # newsboat ran without creating a cache (e.g. some "-x" uses); skip push
elif db_is_healthy "$LOCAL_DB"; then
    if ! cp "$LOCAL_DB" "$SYNC_DB.part" || ! mv -f "$SYNC_DB.part" "$SYNC_DB"; then
        echo "WARNING: failed to update the synced copy of the cache." >&2
        rc=$rc
    else
        echo "newsboat-sync: pushed local cache to Nextcloud."
    fi
else
    echo "ERROR: local cache is malformed, refusing to overwrite the" >&2
    echo "       synced copy. Nothing was pushed. Nextcloud still holds" >&2
    echo "       the last known-good version." >&2
    [ $rc -eq 0 ] && rc=1
fi

exit $rc
