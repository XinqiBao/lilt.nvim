"""Real Neovim UI integration; development-only dependency: pynvim.

Run from the repository root: python3 tests/ui.py [path/to/nvim]
"""
import sys
from pathlib import Path
import pynvim

nvim = pynvim.attach("child", argv=[sys.argv[1] if len(sys.argv) > 1 else "nvim",
                                  "--embed", "--headless", "-u", "NONE", "-i", "NONE"])
grid, highlights = {}, {}
width, height = 90, 22
checks = 0


def check(condition, description):
    global checks
    checks += 1
    if not condition:
        raise AssertionError(description + "\n" + "\n".join(screen()))


def screen():
    # Requests flush preceding input and queued redraw notifications.
    nvim.command("redraw!")
    nvim.exec_lua("vim.rpcnotify(..., 'lilt_test_flush')", nvim.channel_id, async_=True)
    def notification(method, args):
        if method == "lilt_test_flush":
            nvim.stop_loop()
            return
        if method != "redraw":
            return
        for event in args:
            name, entries = event[0], event[1:]
            if name == "grid_line":
                for _, row, col, cells, *_ in entries:
                    attr = 0
                    for cell in cells:
                        if len(cell) > 1:
                            attr = cell[1]
                        for _ in range(cell[2] if len(cell) > 2 else 1):
                            grid[row, col] = (cell[0], attr)
                            col += 1
            elif name == "grid_scroll":
                for _, top, bottom, left, right, rows, cols in entries:
                    old = grid.copy()
                    for row in range(top, bottom):
                        for col in range(left, right):
                            grid[row, col] = (old.get((row + rows, col + cols), (" ", 0))
                                              if top <= row + rows < bottom and left <= col + cols < right
                                              else (" ", 0))
            elif name == "grid_clear":
                grid.clear()
            elif name == "hl_attr_define":
                for attr, rgb, cterm, info in entries:
                    highlights[attr] = info
    nvim.run_loop(None, notification)
    return ["".join(grid.get((row, col), (" ", 0))[0] for col in range(width)).rstrip()
            for row in range(height)]


def input_keys(text):
    nvim.input(text)
    # This lets Neovim process native input and scheduled resize/lifecycle work.
    nvim.exec_lua("vim.wait(20, function() return false end)")
    return screen()


def group_at(row, col, group):
    group = nvim.exec_lua("return vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(...)), 'name')", group)
    return any(item.get("hi_name") == group for item in highlights.get(grid[row, col][1], []))


def run():
    global width, height
    nvim.ui_attach(width, height, rgb=True, ext_linegrid=True, ext_hlstate=True)
    nvim.options["runtimepath"] = str(Path.cwd()) + "," + nvim.options["runtimepath"]
    nvim.command("runtime plugin/lilt.lua")
    nvim.command("LiltGhost")
    buf = nvim.current.buffer.number
    reference = Path("samples/alice.txt").read_text().splitlines()
    rows = screen()
    start = rows.index(reference[0])
    visible = 15
    check(rows[start:start + visible] == reference[:visible], "complete initial reference viewport")
    check(group_at(start, 0, "LiltPending"), "initial text uses pending highlight")
    rows = input_keys("iAlice wax<CR>bank, and")
    check(rows[start] == "Alice wax" + reference[0][9:], "actual typo and pending preceding suffix")
    check(rows[start + 1] == reference[1], "typed second prefix blends into its complete reference row")
    check(rows[start + 2:start + visible] == reference[2:visible], "later lines neither move nor duplicate")
    check(group_at(start, 8, "LiltError"), "wrong character uses error highlight")
    check(not group_at(start, 0, "LiltPending"), "correct authored character uses native foreground")
    check(group_at(start, 9, "LiltPending"), "unfinished preceding suffix remains pending")
    rows = input_keys("<BS><Esc>gg0w$")
    check(rows[start] == "Alice wax" + reference[0][9:], "Backspace and cursor motion preserve earlier pending text")
    check(rows[start + 1] == reference[1], "Backspace restores pending character at same position")
    before = nvim.current.buffer[:]
    nvim.current.buffer[:] = reference[:4]
    rows = input_keys("G$")
    check(rows[start:start + 4] == reference[:4], "curly punctuation renders without byte displacement")
    check(not group_at(start + 3, reference[3].index("“"), "LiltError"), "correct curly quote matches normally")
    nvim.current.buffer[:] = reference
    rows = input_keys("Gzt")
    check(nvim.exec_lua("return #vim.api.nvim_buf_get_extmarks(0,require('lilt.render').namespace,0,-1,{})") == 0,
          "complete correct manuscript has no pending content or errors")
    check(reference[-1] in rows, "completed last row remains visible")
    nvim.current.buffer[:] = before
    input_keys("ggzt")
    input_keys("G10<C-e>")
    check(nvim.funcs.winsaveview()["topline"] <= 2, "vertical scroll cannot enter virtual future rows")
    input_keys("gg0")
    # Allow authored overflow: the same leftcol must apply to real and virtual rows.
    nvim.current.buffer[:] = ["A" * 110]
    rows = input_keys("$ze")
    left = nvim.funcs.winsaveview()["leftcol"]
    check(left > 0, "long authored line triggers native horizontal scrolling")
    check(reference[1][left:] in rows, "virtual future row shares horizontal scroll offset")
    nvim.current.buffer[:] = before
    input_keys("gg0zh")
    # Once rows are authored, ordinary scrolling reaches later reference rows.
    nvim.current.buffer[:] = [line[:5] for line in reference[:25]]
    rows = input_keys("Gzt")
    later = rows.index(reference[24])
    check(rows[later:later + 10] == reference[24:34], "scrolled authored/future boundary has no duplicate rows")
    rows = input_keys("ggzt")
    check(rows[start:start + visible] == reference[:visible], "scrolling back retains every earlier pending suffix")
    nvim.current.buffer[:] = before
    input_keys("gg0")
    # Resize while still in Insert mode, then continue typing in the same buffer.
    input_keys("GA")
    width, height = 42, 22
    nvim.ui_try_resize(width, height)
    rows = input_keys("X")
    check(nvim.current.buffer.number == buf, "resize fallback keeps authoritative buffer")
    check(nvim.current.buffer[-1].endswith("X"), "typing continues during resize fallback")
    check(nvim.eval("mode()") == "i", "resize fallback preserves Insert mode")
    input_keys("<Esc>")
    windows = nvim.current.tabpage.windows
    check(len(windows) == 2, "narrow resize changes Ghost to Split")
    check(all(nvim.api.get_option_value("wrap", {"win": win.handle}) for win in windows),
          "both narrow windows wrap rather than truncate")
    check(not any("Lilt · Ghost" in row for row in rows), "narrow screen identifies the Split fallback")
    authored = nvim.current.buffer[:]
    # Repeated explicit Ghost at narrow widths must remain usable, without leaks.
    for _ in range(3):
        nvim.command("LiltGhost")
        check(len(nvim.current.tabpage.windows) == 2, "narrow Ghost request remains Split")
        check(nvim.current.buffer[:] == authored, "fallback retains text exactly")
    # Reference is an ordinary independently browsable window, including final row.
    userwin = nvim.current.window
    refwin = next(win for win in nvim.current.tabpage.windows if win != userwin)
    nvim.current.window = refwin
    rows = input_keys("G$")
    check(nvim.current.window.cursor[0] == len(reference), "reference can browse all future lines")
    check(nvim.current.buffer[:] == reference, "narrow reference contains every full line")
    nvim.current.window = userwin
    width = 90
    nvim.ui_try_resize(width, height)
    input_keys("")
    nvim.command("LiltGhost")
    check(len(nvim.current.tabpage.windows) == 1, "explicit Ghost works after widening")
    check(nvim.current.buffer[:] == authored, "resize and view cycles retain writing")
    # Replacing / closing reference windows must not leak session resources.
    nvim.command("LiltSplit")
    refwin = next(win for win in nvim.current.tabpage.windows if win != nvim.current.window)
    nvim.api.win_close(refwin, True)
    input_keys("")
    check(nvim.exec_lua("return #vim.api.nvim_buf_get_extmarks(...,require('lilt.render').namespace,0,-1,{})", buf) == 0,
          "manual reference closure cleans manuscript marks")
    check(nvim.api.buf_is_valid(buf), "manual closure retains authored buffer")
    nvim.command("LiltGhost")
    check(nvim.current.buffer.number == buf, "can resume after manual reference closure")
    nvim.command("LiltClose")
    check(len(nvim.tabpages) == 1, "all reading windows removed on close")
    check(nvim.api.buf_get_lines(buf, 0, -1, False) == authored, "close retains actual writing")
    print(f"Lilt UI: {checks} assertions passed on {nvim.exec_lua('return tostring(vim.version())')}")


try:
    run()
finally:
    try:
        nvim.command("qa!")
    except (EOFError, OSError):
        pass
    nvim.close()
