#!/bin/bash

# Ruby 3.3.8 Stable Server
# Downgraded from 3.4.6 to avoid Prism parser and net-http stability issues

cd "$(dirname "$0")"
ENABLE_BROADCASTER=1 ruby json_server.rb "$@"