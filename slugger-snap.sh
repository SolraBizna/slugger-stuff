#!/bin/sh

set -e

if [ $# -ne 1 ]; then
    echo Usage: slugger-snap /base/machine
    exit 1
fi

if [ ! -e "$1/current" ]; then
    echo "slugger-snap: current directory didn't exist, doing nothing"
    exit 0
fi

NOW=`date +%Y.%m.%d-%H%M.%S`

if [ -e "$1/@$NOW" ]; then
    echo "Already exists, try again later"
    exit 1
fi

rm -f "$1/latest"
mv "$1/current" "$1/@$NOW"
ln -s "@$NOW" "$1"/latest
