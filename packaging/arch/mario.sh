#!/bin/sh
# Launcher placed in /usr/bin so the binary at /opt/mario/mario picks up its
# bundled libs without LD_LIBRARY_PATH gymnastics on the caller side.
exec /opt/mario/mario "$@"
