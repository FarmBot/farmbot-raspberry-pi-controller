#!/bin/bash

set -e
set -o pipefail

export MIX_ENV=test

cd farmbot_telemetry

echo "######### farmbot_telemetry"
cd ../farmbot_telemetry
mix format
mix deps.get --all
MIX_ENV=test mix compile --force
# mix coveralls.html
rm -f *.coverdata

echo "######### farmbot_core"
cd ../farmbot_core
mix format
mix deps.get --all
MIX_ENV=test mix compile --force
# mix coveralls.html
rm -f *.coverdata

echo "######### farmbot_ext"
cd ../farmbot_ext
mix format
mix deps.get --all
MIX_ENV=test mix compile --force
# mix coveralls.html
rm -f *.coverdata

echo "######### farmbot_os"
cd ../farmbot_os
mix format
mix deps.get --all
MIX_ENV=test mix compile --force
# mix coveralls.html
rm -f *.coverdata

cd ..
cd farmbot_os

echo "######### Build RPI3 FW"

MIX_TARGET=rpi3 MIX_ENV=prod mix deps.get
MIX_TARGET=rpi3 MIX_ENV=prod mix compile --force
MIX_TARGET=rpi3 MIX_ENV=prod mix firmware

echo "######### Build RPI0 FW"
MIX_TARGET=rpi MIX_ENV=prod mix deps.get
MIX_TARGET=rpi MIX_ENV=prod mix compile --force
MIX_TARGET=rpi MIX_ENV=prod mix firmware
