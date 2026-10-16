"""Real Neovim UI integration; development-only dependency: pynvim.

Run from the repository root: python3 tests/ui.py [path/to/nvim]
"""
import sys
import threading
import time
from pathlib import Path
import pynvim

nvim = pynvim.attach("child", argv=[sys.argv[1] if len(sys.argv) > 1 else "nvim",
                                  "--embed", "--headless", "-u", "NONE", "-i", "NONE"])
grid, highlights, colors = {}, {}, {}
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
                    colors[attr] = rgb
    expired = False
    def timeout():
        nonlocal expired
        expired = True
        nvim.stop_loop()
    timer = threading.Timer(5, lambda: nvim.async_call(timeout))
    timer.daemon = True
    timer.start()
    try:
        nvim.run_loop(None, notification)
    finally:
        timer.cancel()
    if expired:
        raise TimeoutError("Neovim did not flush UI notifications within 5 seconds")
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


def pause(ms):
    nvim.exec_lua("vim.wait(..., function() return false end)", ms)
    return screen()


def floats():
    return [win for win in nvim.windows if nvim.api.win_get_config(win.handle)["relative"]]


def wait_for_hint():
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        if floats():
            return screen()
        time.sleep(0.01)
    raise TimeoutError("Expected hint did not appear\n" + "\n".join(screen()))


def hint_tests(buf, reference):
    user = nvim.current.window
    nvim.current.buffer[:] = ["Blice"]
    input_keys("gg0")
    pause(100)
    check(not floats(), "hint waits before showing")
    rows = wait_for_hint()
    check(any("Expected  Alice" in row for row in rows) and any("Typed     Blice" in row for row in rows),
          "delayed hint displays a local word comparison")
    check(nvim.current.window == user and nvim.current.buffer.number == buf, "hint never steals editing focus")
    check(not nvim.api.win_get_config(floats()[0].handle)["focusable"], "hint is nonfocusable")
    input_keys("2l")
    check(not floats(), "cursor motion immediately dismisses hint")
    pause(280)
    check(not floats(), "correct character never triggers hint")
    input_keys("0")
    pause(100)
    input_keys("2l")
    pause(100)
    input_keys("0")
    pause(100)
    check(not floats(), "rapid movement cancels earlier hint deadlines")
    wait_for_hint()
    check(bool(floats()), "settled error cursor gets a fresh delayed hint")
    input_keys("i")
    check(not floats(), "InsertEnter dismisses hint")
    pause(280)
    check(not floats() and nvim.eval("mode()") == "i", "hints stay hidden in Insert Mode")
    input_keys("<Esc>")
    wait_for_hint()
    check(bool(floats()), "returning to Normal Mode can show hint")
    # Buffer edits invalidate a visible hint even without cursor movement.
    nvim.current.buffer[:] = ["Alice"]
    input_keys("")
    check(not floats(), "editing dismisses existing hint")
    pause(280)
    check(not floats(), "correct text leaves no hint")
    nvim.current.buffer[:] = ["Aice"]
    input_keys("0l")
    rows = wait_for_hint()
    check(any("Expected  Alice" in row for row in rows) and any("Typed     Aice" in row for row in rows),
          "missing-character hint anchors to next real character")
    input_keys("l")
    pause(280)
    check(not floats(), "missing character does not make whole line trigger")
    nvim.current.buffer[:] = ["Allice"]
    input_keys("02l")
    rows = wait_for_hint()
    check(any("Expected  Alice" in row for row in rows) and any("Typed     Allice" in row for row in rows),
          "extra-character hint includes corresponding expected word")
    nvim.current.buffer[:] = ["Alicewas"]
    input_keys("05l")
    rows = wait_for_hint()
    check(any("Expected  Alice was" in row for row in rows) and any("Typed     Alicewas" in row for row in rows),
          "whitespace omission context includes neighboring words")
    nvim.current.buffer[:] = ["Alicia"]
    input_keys("04l")
    rows = wait_for_hint()
    check(any("Expected  Alice" in row for row in rows) and any("Typed     Alicia" in row for row in rows),
          "nearby replacement and extra share local word context")
    nvim.current.buffer[:] = ["X" * len(reference[0])]
    input_keys("060l")
    wait_for_hint()
    hint = floats()[0].buffer[:]
    check("…" in hint[0] and hint[0].endswith("the") and len(hint[1]) <= 64,
          "long error spans clip context around cursor rather than span beginning")
    nvim.current.buffer[:] = reference[:4]
    nvim.current.buffer[3] = reference[3].replace("“", '"', 1)
    input_keys("4G04l")
    rows = wait_for_hint()
    check(any("Expected  “and" in row for row in rows) and any('Typed     "and' in row for row in rows),
          "hint context preserves multibyte reference punctuation")
    nvim.command("LiltSplit")
    pause(280)
    check(not floats(), "switching to Split removes hint resources")
    nvim.command("LiltGhost")
    nvim.current.buffer[:] = ["Blice"]
    input_keys("0")
    # Depart while a timer is pending; returning starts its own deadline.
    nvim.command("vsplit")
    other = nvim.current.window
    pause(280)
    check(not floats(), "leaving manuscript window invalidates pending hint")
    nvim.current.window = user
    wait_for_hint()
    check(bool(floats()), "returning to owned window schedules new hint")
    nvim.current.window = other
    input_keys("")
    check(not floats(), "leaving owned window dismisses visible hint")
    nvim.api.win_close(other.handle, True)
    nvim.current.window = user
    input_keys("0")
    nvim.command("LiltClose")
    nvim.command("LiltGhost")
    nvim.current.buffer[:] = ["Alice"]
    input_keys("0")
    pause(300)
    check(not floats(), "callback from previous session cannot reopen hint")
    check(nvim.current.buffer.number == buf, "hint cycles preserve manuscript")
    nvim.current.buffer[:] = ["Blice"]
    input_keys("0")
    wait_for_hint()
    nvim.api.win_close(nvim.current.window.handle, True)
    pause(300)
    check(not floats(), "manual manuscript window closure removes visible hint")
    check(nvim.exec_lua("local ok = pcall(vim.api.nvim_get_autocmds, {group='LiltGhost'}); return ok") is False,
          "closing manuscript releases Ghost autocmd group")
    nvim.command("LiltGhost")
    check(not nvim.eval("v:errmsg"), "hint lifecycle emits no Neovim errors")


def theme_tests(start):
    for background in ("dark", "light"):
        nvim.options["background"] = background
        nvim.command("colorscheme default")
        nvim.current.buffer[:] = ["Blice"]
        rows = input_keys("gg0")
        normal = nvim.api.get_hl(0, {"name": "Normal", "link": False})
        check(colors[grid[start, 0][1]].get("foreground") != normal.get("fg"),
              background + " theme shows replacement foreground")
        check(group_at(start, 5, "LiltPending"), background + " theme retains pending highlight")
        nvim.current.buffer[:] = ["Aice"]
        screen()
        attr = colors[grid[start, 1][1]]
        check(attr.get("undercurl") or attr.get("underline"), background + " theme shows omission boundary")
        check(not group_at(start, 0, "LiltPending"), background + " theme keeps equal text native")
    nvim.api.set_hl(0, "LiltError", {"fg": 0xBC6543, "bold": True})
    nvim.command("doautocmd ColorScheme")
    nvim.current.buffer[:] = ["Blice"]
    screen()
    check(colors[grid[start, 0][1]].get("foreground") == 0xBC6543,
          "semantic highlight respects explicit user override")
    nvim.options["background"] = "dark"
    nvim.command("colorscheme default")


def run():
    global width, height
    nvim.ui_attach(width, height, rgb=True, ext_linegrid=True, ext_hlstate=True)
    nvim.options["runtimepath"] = str(Path.cwd()) + "," + nvim.options["runtimepath"]
    nvim.command("runtime plugin/lilt.lua")
    nvim.command("LiltGhost")
    buf = nvim.current.buffer.number
    reference = Path("samples/alice.txt").read_text(encoding="utf-8").splitlines()
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
    nvim.current.buffer[:] = ["Aice"]
    rows = input_keys("gg0")
    check(rows[start] == "Aice" + reference[0][5:], "omission adds no Ghost placeholder or duplicate suffix")
    check(group_at(start, 1, "LiltMissing"), "Ghost omission underlines next authored character")
    nvim.current.buffer[:] = ["Allice"]
    rows = screen()
    check(rows[start] == "Allice" + reference[0][5:], "extra character remains visible beside aligned pending suffix")
    check(group_at(start, 2, "LiltExtra"), "extra character has semantic emphasis")
    # Split decorates ordinary reference glyphs using the same comparison.
    width = 160
    nvim.ui_try_resize(width, height)
    input_keys("")
    nvim.command("LiltSplit")
    user = nvim.current.window
    ref = next(win for win in nvim.current.tabpage.windows if win != user)
    check(nvim.api.win_get_position(ref.handle)[1] < nvim.api.win_get_position(user.handle)[1],
          "wide Split starts side by side")
    nvim.current.buffer[:] = ["Aice"]
    rows = screen()
    r, c = nvim.api.win_get_position(ref.handle)
    check(rows[r][c:c + len(reference[0])] == reference[0], "Split prints immutable reference beside omission")
    check(not group_at(r, c, "LiltPending"), "equal reference prefix uses normal foreground")
    check(group_at(r, c + 1, "LiltMissing"), "Split highlights missing reference character")
    check(group_at(r, c + 5, "LiltPending"), "Split subdues aligned pending suffix")
    nvim.current.buffer[:] = ["Blice"]
    rows = screen()
    ur, uc = nvim.api.win_get_position(user.handle)
    check(group_at(r, c, "LiltError") and group_at(ur, uc, "LiltError"),
          "replacement visible in both Split panes")
    width = 90
    nvim.ui_try_resize(width, height)
    input_keys("")
    check(nvim.api.win_get_position(ref.handle)[0] == nvim.api.win_get_position(user.handle)[0],
          "resize never changes Split orientation")
    nvim.current.window = ref
    nvim.command("wincmd J")
    rows = screen()
    check(nvim.api.win_get_position(ref.handle)[0] > nvim.api.win_get_position(user.handle)[0],
          "native window rearrangement remains usable")
    nvim.current.window = user
    nvim.command("LiltGhost")
    hint_tests(buf, reference)
    theme_tests(start)
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
    check(nvim.current.buffer.number == buf, "resize keeps authoritative buffer")
    check(nvim.current.buffer[-1].endswith("X"), "typing continues after resize")
    check(nvim.eval("mode()") == "i", "resize preserves Insert mode")
    input_keys("<Esc>")
    check(len(nvim.current.tabpage.windows) == 1, "narrow resize preserves Ghost")
    check(not nvim.current.window.options["wrap"], "narrow Ghost retains fixed rows")
    check(any("Lilt · Ghost" in row for row in rows), "narrow screen still identifies Ghost")
    authored = nvim.current.buffer[:]
    for _ in range(3):
        nvim.command("LiltGhost")
        check(len(nvim.current.tabpage.windows) == 1, "narrow Ghost request stays Ghost")
        check(nvim.current.buffer[:] == authored, "narrow Ghost retains text exactly")
    nvim.command("LiltSplit")
    windows = nvim.current.tabpage.windows
    check(len(windows) == 2, "explicit narrow Split opens reference")
    check(all(win.options["wrap"] for win in windows), "narrow Split windows wrap")
    check(windows[0].width == windows[1].width, "narrow Split uses above/below layout")
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
    check(not floats() and len(nvim.buffers) == 2, "close leaves no hint or reference buffers")
    print(f"Lilt UI: {checks} assertions passed on {nvim.exec_lua('return tostring(vim.version())')}")


try:
    run()
finally:
    try:
        nvim.command("qa!")
    except (EOFError, OSError):
        pass
    nvim.close()
