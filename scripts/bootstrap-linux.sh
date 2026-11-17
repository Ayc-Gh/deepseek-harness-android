#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d
apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=25 update
apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=25 install -y --no-install-recommends ca-certificates curl git python3 python3-venv util-linux procps iproute2 ripgrep build-essential pkg-config cmake
groupadd -g 2000 dsh
groupadd -g 3003 inet
useradd -u 2000 -g dsh -G inet -m -s /bin/bash dsh
install -d -o dsh -g dsh -m 700 /home/dsh/.dsh /home/dsh/runtime /home/dsh/workspace
id dsh
node --version
npm --version
