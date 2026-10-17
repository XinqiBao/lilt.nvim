# Run from the repository root. Requires VHS, ttyd, FFmpeg, and this font.
# Real Neovim input and terminal output; display options only, no mock UI.
Output doc/demo.gif
Require nvim

Set Shell "bash"
Set FontFamily "DejaVu Sans Mono"
Set FontSize 20
Set LineHeight 1.2
Set Width 1040
Set Height 420
Set Padding 24
Set Framerate 12
Set TypingSpeed 70ms

Hide
Type@0ms `nvim --clean -i NONE --cmd "set rtp^=." -c 'runtime plugin/lilt.lua' -c 'set termguicolors showtabline=0 noruler noshowcmd' -c LiltGhost`
Enter
Sleep 1s
Show
Sleep 800ms
Type "iAlice wax beginning to get very tired"
Sleep 500ms
Escape
Type@100ms "0w2l"
Sleep 1500ms
Screenshot doc/ghost.png
Type@150ms "rs"
Sleep 600ms
Type "A of sitting by her sister on the"
Enter
Type "bank, and of having nothing to do:"
Sleep 1500ms
Escape
Sleep 500ms
