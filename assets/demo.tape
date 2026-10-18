# Run from the repository root. Requires VHS, ttyd, FFmpeg, and this font.
# Real Neovim input and terminal output; display options only, no mock UI.
Output assets/demo.gif
Require nvim

Set Shell "bash"
Set FontFamily "DejaVu Sans Mono"
Set FontSize 20
Set LineHeight 1.2
Set Width 1480
Set Height 550
Set Padding 24
Set Framerate 12
Set TypingSpeed 70ms
Set CursorBlink false

Hide
Type@0ms `demo_root=$(mktemp -d) && XDG_DATA_HOME="$demo_root/data" XDG_STATE_HOME="$demo_root/state" XDG_CACHE_HOME="$demo_root/cache" nvim --clean -i NONE --cmd "set rtp^=." -c 'set termguicolors showtabline=0 noruler noshowcmd laststatus=2'; rm -rf "$demo_root"`
Enter
Sleep 1s
Show
Type@100ms ":Lilt"
Enter
Sleep 1s
Type "e"
Sleep 1200ms
Enter
Sleep 2700ms
Enter
Sleep 1s
Type "iAlice wax beginning to get very tired"
Sleep 500ms
Escape
Type@100ms "0w2l"
Sleep 1500ms
Type@150ms "rs"
Sleep 600ms
Type "A of sitting by her sister on the"
Enter
Type@55ms "bank, and of having nothing to do: once or twice she had peeped into the"
Enter
Type "book her sister was reading"
Escape
Sleep 800ms

# Both views share the real manuscript. At this width Split stacks the panes.
Type@60ms ":LiltSplit"
Enter
Ctrl+l
Sleep 1500ms

# Search ahead in the reference without moving the manuscript.
Ctrl+w
Type "k"
Type@100ms "/Rabbit"
Enter
Sleep 1800ms
Ctrl+w
Type "j"
Sleep 600ms
Type "A, but it had no pictures"
Escape
Sleep 1200ms

# Return to Ghost with the same text, ready to continue reading.
Type@60ms ":LiltGhost"
Enter
Ctrl+l
Sleep 1800ms

Hide
Type@0ms ":qa!"
Enter
Sleep 300ms
