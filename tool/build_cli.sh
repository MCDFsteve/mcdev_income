#!/bin/sh
set -eu
MCDEV_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MCDEV_DART=${DART:-dart}
cd "$MCDEV_ROOT"
mkdir -p build/cli
"$MCDEV_DART" compile exe bin/mcdev.dart -o build/cli/mcdev
