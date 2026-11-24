#!/usr/bin/env bash
# Launch the daily dev apps, each on its own Hyprland (Omarchy) workspace.
#
# Workspace layout:
#   1  Alacritty
#   2  VS Code
#   3  Alacritty running Claude (work_assistance + WorkAssistance Android project)
#   4  Google Chrome
#   5  Chromium
#   6  Android Studio
#   7  Beekeeper Studio

set -u

LOG="$HOME/dev_setup/workspace_launch.log"
exec > >(tee "$LOG") 2>&1
echo "== $(date) =="

WEB_PROJECT="/home/geenath/projects/work_assistance"
ANDROID_PROJECT="/home/geenath/AndroidStudioProjects/WorkAssistance"

# Seconds to wait between launches so windows map in a predictable order.
DELAY=0.5

# Omarchy gives every monitor its own block of 10 workspaces (1-10, 11-20, ...).
# Find the block of the monitor that is focused right now, so "workspace 3" means
# the 3rd workspace on THIS monitor.
active_ws=$(hyprctl activeworkspace -j | jq -r '.id')
BASE=$(( (active_ws - 1) / 10 * 10 ))
echo "Focused workspace: $active_ws -> using workspaces $((BASE + 1))-$((BASE + 10))"

# Addresses of all currently open windows.
window_addresses() { hyprctl clients -j | jq -r '.[].address'; }

# Move every window that is not in $before (a list of addresses) onto workspace $ws.
# Needed because single-instance apps (VS Code, Chromium, ...) hand the request to an
# already-running process, which ignores the workspace rule and opens on the current one.
move_new_windows() {
    local ws="$1" before="$2" addr
    while read -r addr; do
        [ -z "$addr" ] && continue
        grep -qx "$addr" <<<"$before" && continue
        hyprctl dispatch "hl.dsp.window.move({ workspace = \"$ws\", follow = false, window = \"address:$addr\" })" >/dev/null
        echo "   moved $addr -> ws $ws"
    done < <(hyprctl clients -j | jq -r --arg ws "$ws" '.[] | select(.workspace.id != ($ws|tonumber)) | .address')
}

# launch <workspace> <command...>
# Opens the app, then makes sure all of its new windows end up on that workspace.
launch() {
    local ws=$(( BASE + $1 ))
    shift
    local cmd before
    printf -v cmd '%q ' "$@"
    echo ">> ws $ws: $cmd"
    before=$(window_addresses)

    # Hyprland now uses Lua: hyprctl dispatch takes a Lua expression, not "exec [rules] cmd".
    local full="uwsm-app -- $cmd"
    full="${full//\\/\\\\}"   # escape backslashes for the Lua string
    full="${full//\"/\\\"}"    # escape double quotes for the Lua string
    hyprctl dispatch "hl.dsp.exec_cmd(\"$full\", { workspace = \"$ws silent\" })"
    echo "   hyprctl rc=$?"

    # Wait (up to ~15s) for the first new window, then keep sweeping a few more
    # seconds to catch splash screens / extra windows.
    local i seen=0 settle=0
    for ((i = 0; i < 30; i++)); do
        sleep 0.5
        if [ "$(window_addresses | grep -vxFf <(echo "$before") | wc -l)" -gt 0 ]; then
            seen=1
            move_new_windows "$ws" "$before"
        fi
        if [ "$seen" = 1 ]; then
            ((settle++ >= 6)) && break
        fi
    done
    [ "$seen" = 0 ] && echo "   no new window for: $cmd (probably already running - left where it is)"
}

# 1 - plain terminal
#launch 1 alacritty

# 2 - VS Code
launch 2 code

# 3 - Claude with both projects as context (starts in the web project, adds the Android one)
launch 3 alacritty --working-directory "$WEB_PROJECT" -e claude --add-dir "$ANDROID_PROJECT"

# 4 - Google Chrome
launch 4 google-chrome-stable

# 5 - Chromium
launch 5 chromium

# 6 - Android Studio
launch 6 android-studio

# 7 - Beekeeper Studio
launch 7 beekeeper-studio

# Finish on the first workspace.
hyprctl dispatch "hl.dsp.focus({ workspace = \"$((BASE + 1))\" })"
