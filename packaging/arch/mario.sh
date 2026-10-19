#!/bin/sh
# Launcher placed in /usr/bin/mario to launch the Electron app at /opt/mario.
if [ -x /usr/bin/electron44 ]; then
  exec /usr/bin/electron44 /opt/mario "$@"
elif [ -x /usr/bin/electron42 ]; then
  exec /usr/bin/electron42 /opt/mario "$@"
else
  exec electron /opt/mario "$@"
fi
