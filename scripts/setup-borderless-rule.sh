#!/bin/bash
# DEPRECATED - kept so old notes/commands keep working.
# "borderless" is now one mode of the general frame rule:
#   setup-frame-rule.sh decorated   <- default: draggable titlebar + minimise/close buttons
#   setup-frame-rule.sh borderless  <- no titlebar (move/stretch with Alt+drag)
exec "$(dirname "$0")/setup-frame-rule.sh" borderless "$@"
