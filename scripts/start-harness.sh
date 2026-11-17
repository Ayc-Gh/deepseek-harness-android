#!/bin/bash
set -euo pipefail
umask 077
cd /home/dsh/workspace
exec /home/dsh/runtime/node_modules/.bin/dsh web --host 127.0.0.1 --port 3080 --no-open
