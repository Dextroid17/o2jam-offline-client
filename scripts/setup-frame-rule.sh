#!/bin/bash
# Give the O2Jam client a NORMAL WINDOW FRAME: a draggable titlebar with minimise /
# maximise / close buttons - while keeping it resizable and still free of the client's own
# black 4:3 side bars.
#
#   usage: setup-frame-rule.sh [decorated|borderless]
#          decorated  (default) - titlebar + buttons, drag it, minimise it, close it
#          borderless           - old look: no titlebar at all (move/stretch with Alt+drag)
#
# Why a KWin rule instead of an SFML style: the client asks for a titlebar, but decorations
# can only be forced on reliably from the window manager side (the rule below FORCEs the
# border state), so it survives changes to the client's own hints.
set -u
MODE="${1:-decorated}"
R="$HOME/.config/kwinrulesrc"
SEL="O2-JAM"
NEW="o2jam-window-frame"
OLD="o2jam-no-titlebar"

case "$MODE" in
  decorated)   NOBORDER="false"; DESC="O2Jam client: normal window frame (drag bar + minimise/maximise/close), resizable, no black side bars" ;;
  borderless)  NOBORDER="true";  DESC="O2Jam client: borderless (no titlebar/frame), still resizable - move/stretch with Alt+drag" ;;
  *) echo "usage: $0 [decorated|borderless]" >&2; exit 2 ;;
esac

# Retire the old rule: an empty group is harmless to KWin, and a stale "force no titlebar"
# rule would fight the new one for the same window class.
for k in Description noborder noborderrule types wmclass wmclasscomplete wmclassmatch; do
  kwriteconfig6 --file kwinrulesrc --group "$OLD" --key "$k" --delete 2>/dev/null
done

kwriteconfig6 --file kwinrulesrc --group "$NEW" --key Description   "$DESC"
kwriteconfig6 --file kwinrulesrc --group "$NEW" --key wmclass       "$SEL"
kwriteconfig6 --file kwinrulesrc --group "$NEW" --key wmclasscomplete false
kwriteconfig6 --file kwinrulesrc --group "$NEW" --key wmclassmatch 1
kwriteconfig6 --file kwinrulesrc --group "$NEW" --key types         1
kwriteconfig6 --file kwinrulesrc --group "$NEW" --key noborder      "$NOBORDER"
kwriteconfig6 --file kwinrulesrc --group "$NEW" --key noborderrule  2   # 2 = Force this state
kwriteconfig6 --file kwinrulesrc --group General --key rules "$NEW"
kwriteconfig6 --file kwinrulesrc --group General --key count 1

echo "=== KWin rule '$NEW' (mode: $MODE) ==="
echo "  rules      : $(kreadconfig6 --file kwinrulesrc --group General --key rules) (count=$(kreadconfig6 --file kwinrulesrc --group General --key count))"
echo "  wmclass    : $(kreadconfig6 --file kwinrulesrc --group "$NEW" --key wmclass)"
echo "  noborder   : $(kreadconfig6 --file kwinrulesrc --group "$NEW" --key noborder) (rule=$(kreadconfig6 --file kwinrulesrc --group "$NEW" --key noborderrule))  -> $( [ "$NOBORDER" = false ] && echo 'FORCE a titlebar/frame ON' || echo 'FORCE the frame OFF')"
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 && echo "  KWin reconfigured OK" || echo "  (KWin did not answer reconfigure; it also auto-reloads kwinrulesrc on change)"
echo "  note: applies to windows opened AFTER this ran - restart the game to see it"
