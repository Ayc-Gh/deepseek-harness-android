#!/bin/bash
set -euo pipefail
cd /home/dsh/runtime
umask 077
id
grep -E '^(CapEff|CapBnd|NoNewPrivs):' /proc/self/status
node -e 'fetch("https://registry.npmjs.org/@deepseek-ai%2fdsh/0.2.2-rc.1").then(r=>{if(!r.ok)throw Error(r.status);return r.json()}).then(p=>console.log(JSON.stringify({registry:p.name,version:p.version})))'
npm init --yes >/dev/null
npm install --save-exact --no-audit --no-fund @deepseek-ai/dsh@0.2.2-rc.1
./node_modules/.bin/dsh --version
