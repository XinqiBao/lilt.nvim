# Run from the repository root. Requires VHS, ttyd, FFmpeg, and this font.
# Real Neovim input; short verse keeps both Split panes readable at README width.
Output assets/demo.gif
Require nvim

Set Shell "bash"
Set FontFamily "DejaVu Sans Mono"
Set FontSize 22
Set LineHeight 1.15
Set Width 1200
Set Height 680
Set Padding 20
Set Framerate 12
Set TypingSpeed 85ms
Set CursorBlink false

Hide
Type@0ms `demo_root=$(mktemp -d) && XDG_CONFIG_HOME="$demo_root/config" XDG_DATA_HOME="$demo_root/data" XDG_STATE_HOME="$demo_root/state" XDG_CACHE_HOME="$demo_root/cache" nvim --clean -i NONE --cmd "set rtp^=." -c 'set termguicolors showtabline=0 noruler noshowcmd laststatus=2' -c 'lua vim.opt.fillchars:append({ eob = " " })'; rm -rf "$demo_root"`
Enter
Sleep 1s
Type@0ms ":Lilt"
Enter
Sleep 300ms
Type "e"
Sleep 300ms
Type "G"
Enter
Sleep 300ms
# Start at the unit preview, without spending the opening on menu traversal.
Show
Sleep 1500ms
Enter
Sleep 500ms
# Two physical rows show Ghost; a deliberate typo gets a delayed local hint.
Type "iTyger Tyger. burning brighx,"
Escape
Type "h"
Sleep 1500ms
Type@150ms "rt"
Sleep 500ms
Type "A"
Enter
Type "In the forests of the night;"
Escape
Sleep 800ms

# The reference scrolls independently; the manuscript stays on its two rows.
Type@45ms ":LiltSplit"
Enter
Ctrl+l
Sleep 1200ms
Ctrl+w
Type "h"
Type@70ms "/Lamb"
Enter
Sleep 2000ms
Ctrl+w
Type "l"
Sleep 400ms

# Return to the same writing before the loop.
Type@45ms ":LiltGhost"
Enter
Ctrl+l
Sleep 1400ms
Hide
Type@0ms ":qa!"
Enter
Sleep 300ms
