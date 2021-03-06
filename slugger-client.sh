#!/bin/sh

if [ -z "$__SLUGGER_FLOCKED__" ]; then
    export __SLUGGER_FLOCKED__=1
    flock -E42 -xn /tmp/$(whoami)_slugger_lock "$0" "$@"
    WAT=$?
    if [ $WAT = 0 ]; then
        rm -f /tmp/$(whoami)_slugger_lock
    elif [ $WAT = 42 ]; then
        echo "Another Slugger client instance is already running, or the lock is stale."
        echo "If you're certain another client isn't running, delete /tmp/$(whoami)_slugger_lock and try again."
    fi
    exit $WAT
fi

KILL_AGENT=
if [ -z "$SSH_AGENT_PID" -a -z "$SSH_AUTH_SOCK" ]; then
    exec env CALL_SSH_ADD=1 ssh-agent "$0" "$@"
fi
if [ ! -z "$CALL_SSH_ADD" ]; then
    ssh-add
fi

if [ -z "$SLUGGER_DIR" ]; then
    if [ -d "$HOME/.slugger" ]; then
        SLUGGER_DIR="$HOME/.slugger"
    else
        SLUGGER_DIR="/etc/slugger"
    fi
fi

set -e

if [ \! \( -r $SLUGGER_DIR/host -a -r $SLUGGER_DIR/dir -a -r $SLUGGER_DIR/sources -a -r $SLUGGER_DIR/exclude \) ]; then
    echo "Slugger client not fully configured. The following files need to be created:"
    [ -r $SLUGGER_DIR/host ] || echo "* $SLUGGER_DIR/host (destination host for this machine's backups)"
    [ -r $SLUGGER_DIR/dir ] || echo "* $SLUGGER_DIR/dir (destination dir on host for this machine's backups)"
    [ -r $SLUGGER_DIR/sources ] || echo "* $SLUGGER_DIR/sources (paths on this machine to back up)"
    [ -r $SLUGGER_DIR/exclude ] || echo "* $SLUGGER_DIR/exclude (passed to rsync --exclude-from)"
    exit 3
fi

if [ -r $SLUGGER_DIR/extras ]; then
    EXTRAS="$(cat $SLUGGER_DIR/extras)"
else
    EXTRAS=
fi

if [ -z "$RSYNC_RSH" ]; then
    if [ -r $SLUGGER_DIR/rsh ]; then
        export RSYNC_RSH="$(cat $SLUGGER_DIR/rsh)"
    else
        export RSYNC_RSH=ssh
    fi
fi

if [ -t 1 -a "$#" -le 0 ]; then
    PROGRESS_OPTIONS="--human-readable --progress"
else
    PROGRESS_OPTIONS=""
fi

rsync --timeout=30 --archive --recursive $PROGRESS_OPTIONS --one-file-system --links --delete-during --delete-excluded --ignore-existing --inplace --chmod=u+rw -M--fake-super --files-from=$SLUGGER_DIR/sources --exclude-from=$SLUGGER_DIR/exclude --link-dest=../latest $EXTRAS "$@" / "$(cat $SLUGGER_DIR/host):$(cat $SLUGGER_DIR/dir)/current" || exit 2
$RSYNC_RSH "$(cat $SLUGGER_DIR/host)" slugger-snap "$(cat $SLUGGER_DIR/dir)" || exit 5
