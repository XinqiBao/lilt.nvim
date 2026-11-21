"""Real Neovim UI integration; development-only dependency: pynvim.

Run from the repository root: python3 tests/ui.py [path/to/nvim]
"""
import json
import shutil
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
import pynvim

from fixtures.epub import write_epub

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
    waiting = True
    def timeout():
        nonlocal expired
        if waiting:
            expired = True
            nvim.stop_loop()
    timer = threading.Timer(5, lambda: nvim.async_call(timeout))
    timer.daemon = True
    timer.start()
    try:
        nvim.run_loop(None, notification)
    finally:
        waiting = False
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


def choose(label):
    for row, line in enumerate(nvim.current.buffer[:], 1):
        if label in line:
            nvim.current.window.cursor = (row, 0)
            return input_keys("<CR>")
    raise AssertionError("Missing picker action: " + label + "\n" + "\n".join(nvim.current.buffer[:]))


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
    open_example()
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
    open_example()
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


def open_example():
    nvim.command("Lilt")
    input_keys("e")
    choose(json.loads(Path("examples/alice/lilt.json").read_text(encoding="utf-8"))["title"])
    return input_keys("<CR>")


def picker_session_tests(buf):
    user = nvim.current.window
    undo = nvim.funcs.undotree()["seq_cur"]
    text = nvim.current.buffer[:]
    for view in ("Ghost", "Split"):
        nvim.command("Lilt" + view)
        windows = list(nvim.current.tabpage.windows)
        for origin in windows:
            nvim.current.window = origin
            layout = nvim.funcs.winlayout()
            input_keys(":Lilt<CR><Esc>")
            check(nvim.current.window == origin and nvim.funcs.winlayout() == layout,
                  view + " picker cancellation restores focus and layout from either pane")
            check(nvim.api.buf_get_lines(buf, 0, -1, False) == text,
                  "picker cancellation preserves unsaved manuscript")
        nvim.current.window = user
        check(nvim.funcs.undotree()["seq_cur"] == undo, "picker leaves native undo history intact")
    input_keys(":Lilt<CR>l")
    check(nvim.api.buf_get_lines(buf, 0, -1, False) == text, "preview during reading preserves unsaved writing")
    input_keys("<CR>")
    check(nvim.current.buffer.number == buf and nvim.current.buffer[:] == text,
          "selecting the active unit reuses its unsaved buffer")


def library_tests():
    global width, height
    with tempfile.TemporaryDirectory(prefix="lilt-library-") as directory:
        root = Path(directory)
        source = root / "source" / "letters #100% [draft] 文学"
        source.mkdir(parents=True)
        (source / "opening.txt").write_text("First line.\n\nLast line.\n", encoding="utf-8")
        (source / "reply.txt").write_text("Reply.\n", encoding="utf-8")
        (source / "lilt.json").write_text(json.dumps({
            "title": "Letters", "authors": ["A writer with a long biographical name " * 5], "units": [
                {"title": "Opening", "path": "opening.txt"},
                {"title": "Reply", "path": "reply.txt"},
            ]}), encoding="utf-8")
        home = root / "personal library"
        nvim.exec_lua("require('lilt').setup({library=...})", str(home))
        rows = input_keys(":Lilt<CR>")
        check(any("Library (empty)" in row for row in rows), "empty library is explicit")
        check(any("Add local work" in row for row in rows), "empty library offers local import")
        check(any("Examples" in row for row in rows), "examples follow import action")
        picker = nvim.current.window
        config = nvim.api.win_get_config(picker.handle)
        check(config["relative"] == "editor" and config["col"] > 0 and config["row"] > 0,
              "picker floats in the center of the editor")
        nvim.command("Lilt")
        check(nvim.current.window == picker and len(floats()) == 1, "reopening focuses the same picker")
        origin = next(win for win in nvim.windows if win != picker)
        menu_buf = nvim.current.buffer.number
        choose("Add local work")
        rows = screen()
        check(any("Local work directory" in row for row in rows)
              and nvim.current.window == picker and len(floats()) == 1
              and nvim.eval("mode()") == "i",
              "local path uses the existing focused Picker float")
        path_buf = nvim.current.buffer.number
        rows = input_keys("<CR>")
        check(any("Enter a local work directory" in row for row in rows), "empty path stays editable with feedback")
        rows = input_keys(str(root / "missing") + "<CR>")
        check(any("ENOENT" in row for row in rows) and nvim.current.buffer.number == path_buf,
              "missing path preserves input and shows the failure reason")
        rows = input_keys("<BS>")
        check(not any("ENOENT" in row for row in rows), "editing clears an obsolete path error")
        input_keys("<Esc>")
        check(nvim.current.buffer.number == menu_buf and not nvim.api.buf_is_valid(path_buf)
              and "Add local work" in nvim.current.buffer[nvim.current.window.cursor[0] - 1]
              and nvim.eval("mode()") == "n", "Escape restores the same menu and selection")
        choose("Add local work")
        input_keys("discard<C-c>")
        check(nvim.current.buffer.number == menu_buf, "Ctrl-C cancels only path input")
        input_keys("h")
        check(not floats() and nvim.current.window == origin, "back after cancel restores editor focus")

        input_keys(":Lilt<CR>a")
        path_buf = nvim.current.buffer.number
        nvim.current.window = origin
        input_keys("")
        check(not floats() and not nvim.api.buf_is_valid(path_buf)
              and nvim.eval("mode()") == "n", "leaving path input releases Picker resources and Insert mode")
        input_keys(":Lilt<CR>a")
        path_buf = nvim.current.buffer.number
        nvim.api.win_close(nvim.current.window.handle, True)
        input_keys("")
        check(not floats() and not nvim.api.buf_is_valid(path_buf), "closing the path float releases its buffer")

        input_keys(":Lilt<CR>a")
        previous_cwd = nvim.funcs.getcwd()
        nvim.command("lcd " + nvim.funcs.fnameescape(str(root)))
        other = root / "source" / "letters other"
        other.mkdir()
        input_keys("./source/le<Tab>")
        first_completion = nvim.current.buffer[0]
        input_keys("<Tab>")
        check(nvim.current.buffer[0] != first_completion, "Tab cycles native directory candidates")
        input_keys("<S-Tab>")
        check(nvim.current.buffer[0] == first_completion, "Shift-Tab cycles candidates backward")
        input_keys("<C-e><C-u>./source/letters other<CR>")
        rows = screen()
        check(any("regular manifest file" in row for row in rows),
              "relative directory validation exposes a missing manifest")
        input_keys("<Esc>")
        nvim.command("lcd " + nvim.funcs.fnameescape(previous_cwd))
        other.rmdir()
        input_keys("a")
        old_home = nvim.exec_lua("return vim.env.HOME")
        nvim.exec_lua("vim.env.HOME = ...", str(root))
        try:
            rows = input_keys("~/source/le<Tab>")
            check(nvim.eval("pumvisible()") == 1 and any("letters #100%" in row for row in rows),
                  "Tab displays directory completion including spaces and Unicode")
            input_keys("<CR>")
            check(nvim.current.buffer[:] == ["~/source/" + source.name + "/"]
                  and nvim.eval("pumvisible()") == 0,
                  "Enter accepts a completion without submitting the path")
            input_keys("<Esc>")
            check(not (home / "references").exists(), "canceling completed path installs nothing")
            input_keys("a~/source/le<S-Tab><CR>")
            width, height = 24, 8
            nvim.ui_try_resize(width, height)
            input_keys("")
            check(nvim.current.buffer[:] == ["~/source/" + source.name + "/"]
                  and nvim.eval("mode()") == "i", "Shift-Tab and resize retain the complete editable path")
            width, height = 90, 22
            nvim.ui_try_resize(width, height)
            # A glob expansion would select this sibling instead of [draft].
            (source.parent / "letters #100% d 文学").mkdir()
            rows = input_keys("<CR>")
        finally:
            nvim.exec_lua("vim.env.HOME = ...", old_home)
        check(any("Library directory name" in row for row in rows), "local import offers a directory name")
        check(nvim.eval("mode()") == "i", "path submission hands Insert focus to naming")
        check(nvim.current.buffer[0] == "Letters", "directory name starts with the official title")
        rows = input_keys("<C-u>…<CR>")
        check(any("needs a letter or number" in row for row in rows), "invalid name keeps a visible error after input events")
        check(nvim.current.buffer[0] == "…", "invalid directory name remains editable")
        rows = input_keys("<C-u>Letters")
        check(not any("needs a letter or number" in row for row in rows), "editing clears an obsolete name error")
        (home / "manuscripts/letters").mkdir(parents=True)
        rows = input_keys("<CR>")
        check(any("work name already exists" in row for row in rows), "collision error stays visible")
        check(nvim.current.buffer[0] == "Letters", "collision preserves the chosen input")
        (home / "manuscripts/letters").rmdir()
        (home / "manuscripts").rmdir()
        rows = input_keys("<CR>")
        check(any("Opening" in row and "—" in row for row in rows), "import proceeds to ordered unit selection")
        list_win = nvim.current.window
        preview_win = next(win for win in floats() if win != list_win)
        check(nvim.current.window == list_win and len(floats()) == 2, "unit selection previews automatically without focus changes")
        check(preview_win.buffer[:] == ["First line.", "", "Last line."], "preview preserves the reference opening")
        input_keys("j")
        check(preview_win.buffer[:] == ["Reply."], "moving the list changes the excerpt")
        input_keys("k")
        width, height = 120, 30
        nvim.ui_try_resize(width, height)
        rows = input_keys("")
        check(nvim.api.win_get_position(preview_win.handle)[1] > nvim.api.win_get_position(list_win.handle)[1],
              "wide terminals show preview on the right")
        check(any("First line." in row for row in rows), "reference excerpt is visible beside selection")
        width, height = 80, 24
        nvim.ui_try_resize(width, height)
        rows = input_keys("")
        check(nvim.api.win_get_position(preview_win.handle)[0] > nvim.api.win_get_position(list_win.handle)[0],
              "narrow terminals show preview below")
        width, height = 24, 8
        nvim.ui_try_resize(width, height)
        rows = input_keys("")
        config = nvim.api.win_get_config(list_win.handle)
        check(config["width"] + 2 <= width and config["height"] + 2 <= height and len(floats()) == 1,
              "small terminals prioritize the unit list")
        check("Opening" in nvim.current.buffer[nvim.current.window.cursor[0] - 1], "resize preserves unit selection")
        rows = input_keys("G")
        check(not any("A writer" in row for row in rows), "unit scrolling can hide the work metadata")
        rows = input_keys("99k")
        check(nvim.current.window.cursor[0] == 1 and any("Letters" in row for row in rows),
              "upward movement brings the work title back into view")
        menu_buf = nvim.current.buffer.number
        input_keys("<CR>l<Right>")
        check(nvim.current.buffer.number == menu_buf and not nvim.current.window.options["cursorline"],
              "work metadata is navigable but does not activate or highlight as an action")
        check(not (home / "manuscripts").exists(), "preview leaves manuscripts and progress untouched")
        author_row = next(row for row, line in enumerate(nvim.current.buffer[:], 1) if "A writer" in line)
        nvim.current.window.cursor = (author_row, 0)
        input_keys("j")
        width, height = 90, 22
        nvim.ui_try_resize(width, height)
        input_keys("")
        check(nvim.current.window.cursor[0] == author_row + 1 and not nvim.current.window.options["cursorline"],
              "resize restores the cursor within wrapped metadata without selecting an action")
        choose("Opening")
        manuscript = home / "manuscripts" / "letters" / "opening.txt"
        check(nvim.current.buffer.name == str(manuscript), "selection opens predictable named manuscript")
        buf = nvim.current.buffer.number
        input_keys("iFirst<Esc>")
        picker_session_tests(buf)
        input_keys(":w<CR>")
        check(manuscript.read_text(encoding="utf-8") == "First\n", "native write saves manuscript")
        rows = input_keys(":Lilt<CR>l")
        check(any("Opening" in row and "33%" in row for row in rows), "unit picker shows saved progress")
        input_keys("jl")
        second = nvim.current.buffer.number
        input_keys("iReply<Esc>")
        input_keys(":Lilt<CR>ll")
        check(nvim.current.buffer.number == buf, "chapter selection reuses named buffer")
        check(nvim.api.buf_get_lines(second, 0, -1, False) == ["Reply"], "chapter switch retains unsaved edits")
        input_keys(":Lilt<CR>elh")
        check(any("Alice" in line for line in nvim.current.buffer[:]), "h returns from units to example works")
        input_keys("q")
        check(nvim.current.buffer.number == buf, "quit from nested pages restores reading focus")
        nvim.command("LiltClose")
        nvim.api.buf_delete(buf, {})
        # A separate process has no retained state and loads a readonly plugin.
        runtime = root / "readonly-plugin"
        for tree in ("lua", "plugin", "examples"):
            shutil.copytree(tree, runtime / tree)
        for path in runtime.rglob("*"):
            path.chmod(0o555 if path.is_dir() else 0o444)
        runtime.chmod(0o555)
        resumed = pynvim.attach("child", argv=[sys.argv[1] if len(sys.argv) > 1 else "nvim",
                                              "--embed", "--headless", "-u", "NONE", "-i", "NONE"])
        try:
            resumed.options["runtimepath"] = str(runtime) + "," + resumed.options["runtimepath"]
            resumed.exec_lua("require('lilt').setup({library=...}); require('lilt').open()", str(home))
            resumed.exec_lua("vim.api.nvim_feedkeys('ll', 'xt', false)")
            check(resumed.current.buffer[:] == ["First"], "new Neovim process resumes saved manuscript through picker")
            resumed.exec_lua("require('lilt').open(); vim.api.nvim_feedkeys('ell', 'xt', false)")
            check(resumed.current.buffer.name == "", "example opens from a readonly plugin installation")
        finally:
            try:
                resumed.command("qa!")
            except (EOFError, OSError):
                pass
            resumed.close()
            runtime.chmod(0o755)
            for path in runtime.rglob("*"):
                path.chmod(0o755 if path.is_dir() else 0o644)
        # A source tree changes navigation, not manuscript identity.
        installed_manifest = home / "references" / "letters" / "lilt.json"
        structured = json.loads(installed_manifest.read_text(encoding="utf-8"))
        structured["toc"] = [{"title": "Volume", "children": [
            {"title": "First chapter", "path": "opening.txt", "children": [
                {"title": "Second chapter", "path": "reply.txt"},
            ]},
            {"title": "First alias", "path": "opening.txt"},
        ]}]
        installed_manifest.write_text(json.dumps(structured), encoding="utf-8")
        nvim.command("Lilt")
        choose("Letters")
        contents = nvim.current.buffer[:]
        parent = next(line for line in contents if "First chapter" in line)
        child = next(line for line in contents if "Second chapter" in line)
        check(len(child) - len(child.lstrip()) > len(parent) - len(parent.lstrip()),
              "nested navigation entries retain a visible hierarchy")
        group_row = next(i for i, line in enumerate(contents, 1) if "Volume" in line)
        nvim.current.window.cursor = (group_row, 0)
        menu = nvim.current.buffer.number
        input_keys("<CR>")
        check(nvim.current.buffer.number == menu and not nvim.current.window.options["cursorline"],
              "navigation groups remain informational")
        choose("First alias")
        check(Path(nvim.current.buffer.name).resolve() == manuscript.resolve()
              and nvim.current.buffer[:] == ["First"],
              "navigation aliases resume the same saved manuscript")
        nvim.command("LiltClose")
        open_example()
        check(nvim.current.buffer.name == "", "example is reachable through the unified picker")
        nvim.command("LiltClose")
        nvim.command("Lilt")
        width, height = 24, 8
        nvim.ui_try_resize(width, height)
        rows = input_keys("G")
        config = nvim.api.win_get_config(nvim.current.window.handle)
        check(nvim.current.window.options["cursorline"], "resize preserves the selection highlight")
        check(config["width"] + 2 <= width and config["height"] + 2 <= height,
              "picker fits after narrowing and shortening the terminal")
        check(any("Examples" in row for row in rows), "native G scrolls to the final item in a short picker")
        check(any("q quit" in row for row in rows), "compact picker keeps cancellation controls readable")
        input_keys("<Esc>")
        check(not floats(), "small picker closes without resources")
        width, height = 90, 22
        nvim.ui_try_resize(width, height)
        input_keys("")


def local_presentation_tests():
    global width, height
    with tempfile.TemporaryDirectory(prefix="lilt-local-presentation-") as directory:
        home = Path(directory) / "library"
        samples = Path(directory) / "examples"
        long_title = "Collected letters from the Cambridge historical edition " * 3
        long_author = "An Author With A Lengthy Bibliographical Name " * 4
        accent_title = "Accent " + "e\u0301" * 100
        records = [
            ("letters", "Letters", ["First Writer", "Second Writer"]),
            ("a", long_title, ["A. Writer"]),
            ("b", long_title, ["A. Writer"]),
            ("essays", "Essays", [long_author]),
            ("accent", accent_title, []),
            ("cjk", "天地玄黄宇宙洪荒" * 12, []),
            ("anonymous", "Anonymous", []),
            ("oversized-" * 12, long_title, ["A. Writer"]),
        ]
        for base in (home / "references", samples):
            for name, title, authors in records:
                target = base / name
                target.mkdir(parents=True)
                (target / "unit.txt").write_text("Reference.\n", encoding="utf-8")
                (target / "lilt.json").write_text(json.dumps({
                    "title": title, "authors": authors,
                    "units": [{"title": "Unit " + name, "path": "unit.txt"}],
                }), encoding="utf-8")

        width, height = 120, 30
        nvim.ui_try_resize(width, height)
        nvim.exec_lua("require('lilt.picker').open(...)", str(home), str(samples))
        screen()
        local_rows = nvim.current.buffer[:]
        check(nvim.current.window.width == 76, "Library retains its ordinary width")
        for name in ("a", "b"):
            row = next(line for line in local_rows if line.endswith("[" + name + "]"))
            check("Collected letters" in row and "…" in row and "A. Writer" not in row,
                  "duplicate directory suffix reserves room before title ellipsis and optional authors")
        choose("Letters")
        rows = input_keys("gg")
        author_row = next(i for i, row in enumerate(rows) if "First Writer; Second Writer" in row)
        check(group_at(author_row, rows[author_row].index("First Writer"), "Comment"),
              "unit-page authors use Comment styling")
        input_keys("h")
        choose("Examples")
        screen()
        example_rows = nvim.current.buffer[:]
        check(nvim.current.window.width == 76 and example_rows[1:] == local_rows[1:1 + len(records)],
              "Examples and Library share the same single-row work presentation and width")
        input_keys("hgg")
        rows = screen()
        author_row = next(i for i, row in enumerate(rows) if "First Writer; Second Writer" in row)
        check(group_at(author_row, rows[author_row].index("First Writer"), "Comment")
              and not group_at(author_row, rows[author_row].index("Letters"), "Comment"),
              "compact local authors are muted while titles retain normal styling")
        essay = next(row for row in local_rows if "Essays" in row)
        check(essay.endswith("…") and "An Author" in essay, "long local authors use bounded ellipsis")
        accent = next(row for row in local_rows if "Accent" in row)
        check(accent.endswith("e\u0301…"), "local title ellipsis preserves composing characters")
        check(all(nvim.funcs.strdisplaywidth(row) <= 76 for row in local_rows),
              "local Unicode rows fit their display-cell width")

        choose("[b]")
        check("Unit b" in "\n".join(nvim.current.buffer[:]), "duplicate suffix opens the exact local work")
        input_keys("ih")
        input_keys("h")
        width, height = 28, 12
        nvim.ui_try_resize(width, height)
        input_keys("")
        check(nvim.current.buffer[nvim.current.window.cursor[0] - 1].endswith("[b]"),
              "narrow resize retains exact duplicate selection and its short suffix")
        rows = nvim.current.buffer[:]
        check(all(nvim.funcs.strdisplaywidth(row) <= nvim.current.window.width for row in rows),
              "narrow duplicate rows stay within the float")
        duplicates = [(i, row) for i, row in enumerate(rows, 1) if "Collected" in row]
        check(len(duplicates) == 3 and sum("[" in row for _, row in duplicates) == 2,
              "oversized directory suffix retains the existing omission behavior")
        oversized_row = next(i for i, row in duplicates if "[" not in row)
        nvim.current.window.cursor = (oversized_row, 0)
        input_keys("<CR>i")
        info = "".join("".join(nvim.current.buffer[:]).split())
        check("Directory:" + "oversized-" * 12 in info,
              "omitted suffix still opens exact complete offline directory information")
        input_keys("hh")
        width, height = 120, 30
        nvim.ui_try_resize(width, height)
        input_keys("")
        input_keys("q")
        check(not (home / "manuscripts").exists(), "presentation and information create no writing")


def library_diagnostic_tests():
    global width, height
    with tempfile.TemporaryDirectory(prefix="lilt-library-diagnostic-") as directory:
        home = Path(directory) / ("long-library-path-" * 8)
        broken = home / "references" / ("invalid-work-" * 10)
        broken.mkdir(parents=True)
        (broken.parent / "invalid\nwork").mkdir()
        (broken / "lilt.json").write_text(json.dumps({
            "title": "Broken work", "units": [{"title": "Missing unit", "path": "missing.txt"}],
        }), encoding="utf-8")
        nvim.exec_lua("require('lilt').setup({library=...})", str(home))
        width, height = 24, 8
        nvim.ui_try_resize(width, height)
        input_keys(":Lilt<CR>gg")
        content = nvim.current.buffer[:]
        compact = "".join("".join(line.split()) for line in content)
        cause = "missing file or unsupported symlink in unit path: missing.txt"
        check("".join(cause.split()) in compact and str(broken) in compact,
              "library diagnostics retain the complete long path and validation cause")
        check("invalidworkdirectoryname:" in compact and "invalidwork" in compact,
              "a directory name containing a newline remains a readable discovery diagnostic")
        for index, line in enumerate(content):
            if index:
                rows = input_keys("j")
            else:
                rows = screen()
            check(any(line.strip() in row for row in rows), "native scrolling exposes each library diagnostic row")
        input_keys("a<Esc>q")
        check(not floats() and not (home / "manuscripts").exists(),
              "long diagnostics leave local import and Picker cleanup usable")
        width, height = 90, 22
        nvim.ui_try_resize(width, height)


def information_tests():
    global width, height
    with tempfile.TemporaryDirectory(prefix="lilt-information-ui-") as directory:
        home = Path(directory) / "library"
        work = home / "references" / "saved-edition"
        work.mkdir(parents=True)
        title = "天地玄黃宇宙洪荒" * 12 + " e\u0301 🐇"
        source_url = "https://example.invalid/" + "unspaced-source-path-" * 15
        subjects = ["Subject " + str(i) + " — " + "文學" * 14 for i in range(6)]
        metadata = {
            "title": title, "authors": ["A. Writer"], "translators": ["A. Translator"],
            "languages": ["en", "fr"], "subjects": subjects, "bookshelves": ["Letters", "Classics"],
            "description": "A source description.\n\nSecond paragraph with Unicode — 文學.",
            "rights": "CC BY 4.0 curated data; public-domain primary text",
            "rights_url": "https://example.invalid/licenses/4.0",
            "publisher": "Source Press", "published": "1912",
            "source": {"provider": "test-source", "id": "42", "url": source_url,
                       "version": "0.2", "title": "Illustrated copy"},
            "preparation": {"wrap_columns": 72, "plain_quotes": True},
            "units": [{"title": "Unit " + str(i), "path": str(i) + ".txt"} for i in range(1, 25)],
        }
        for unit in metadata["units"]:
            (work / unit["path"]).write_text("Reference\n", encoding="utf-8")
        manifest = work / "lilt.json"
        manifest.write_text(json.dumps(metadata, ensure_ascii=False), encoding="utf-8")
        before = manifest.read_bytes()
        nvim.exec_lua("require('lilt').setup({library=...})", str(home))
        input_keys(":Lilt<CR>lG")
        selected = (nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"])
        rows = input_keys("i")
        check(any("Work information" in row for row in rows) and len(floats()) == 1,
              "information replaces the passive preview and opens from a unit shortcut")
        input_keys("h")
        check((nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"]) == selected,
              "information back restores a scrolled unit and its viewport")
        input_keys("i")
        width, height = 24, 8
        nvim.ui_try_resize(width, height)
        rows = input_keys("gg")
        content = nvim.current.buffer[:]
        second_paragraph = next(index for index, line in enumerate(content)
                                if "Second paragraph" in line)
        check(second_paragraph > 0 and not content[second_paragraph - 1].strip()
              and "source description." in " ".join(" ".join(content[:second_paragraph - 1]).split()),
              "description paragraphs retain a distinct blank row at narrow width")
        seen = set()
        for index, line in enumerate(content):
            if index:
                rows = input_keys("j")
            if any(line.strip() in row for row in rows):
                seen.add(index)
        check(len(seen) == len(content), "native narrow scrolling exposes every information row without clipping")
        compact = "".join("".join(line.split()) for line in content)
        for value in [title, source_url, *subjects]:
            check("".join(value.split()) in compact, "long CJK title, source URL and every subject remain complete")
        check("A.Translator" in compact and "Languages:en;fr" in compact and "Bookshelves:Letters;Classics" in compact,
              "shared bibliographic fields survive narrow wrapping")
        for key in ["description", "rights", "rights_url", "publisher", "published"]:
            check("".join(metadata[key].split()) in compact,
                  "saved source " + key + " remains readable offline at narrow width")
        check("Savedcatalogfile:" not in compact, "missing raw snapshot needs no placeholder or error")
        check("Sourceversion:0.2" in compact, "supplied acquisition revision remains visible offline")
        check("Sourcecopytitle:Illustratedcopy" in compact, "supplied acquisition copy title remains visible offline")
        width, height = 90, 22
        nvim.ui_try_resize(width, height)
        input_keys("")
        choose("Back to reading units")
        check("Unit 24" in nvim.current.buffer[nvim.current.window.cursor[0] - 1],
              "resizing information retains its original reading-unit selection")
        check(not (home / "manuscripts").exists() and manifest.read_bytes() == before,
              "information neither starts writing nor changes saved metadata")
        input_keys("iq")
        check(not floats(), "quitting information releases the picker and preview")


def catalog_feedback_tests():
    global width, height
    release = threading.Event()
    received = []
    fail_error = True
    book = {"id": 11, "title": "Local catalog work", "authors": [], "formats": {}}

    class CatalogHandler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            query = parse_qs(urlsplit(self.path).query)
            received.append(query)
            search = query.get("search", [""])[0]
            if search in ("", "slow", "timeout"):
                release.wait(5)
            if search == "error" and fail_error:
                self.send_response(503)
                self.end_headers()
                return
            later = int(query.get("page", ["1"])[0]) > 1
            books = [] if search == "empty" else [dict(book, id=12 if later else 11, title=(
                "Second catalog page" if later else book["title"]))]
            body = json.dumps({"count": 2 if books else 0, "results": books,
                               "next": "/books/?page=2" if books and not later else None}).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass  # Cancelled requests may already have disconnected.

    server = ThreadingHTTPServer(("127.0.0.1", 0), CatalogHandler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    with tempfile.TemporaryDirectory(prefix="lilt-catalog-ui-") as directory:
        nvim.exec_lua("""
            local home, base = ...
            _G.lilt_catalog_providers = require('lilt.online.providers').list
            require('lilt.online.providers').list = function(base)
                return {require('lilt.online.providers.gutenberg').new(base)}
            end
            _G.lilt_catalog_system = vim.system
            _G.lilt_catalog_jobs = {}
            -- Route real curl to this fixture without weakening production HTTPS
            -- or spending 45 seconds exercising its timeout path.
            vim.system = function(args, opts, callback)
                assert(args[1] == 'curl')
                local job = {}
                table.insert(_G.lilt_catalog_jobs, job)
                args = vim.deepcopy(args)
                for i, arg in ipairs(args) do
                    if arg == '--url' then job.url = args[i + 1] end
                end
                for i, arg in ipairs(args) do
                    if arg == '--url' then
                        args[i + 1] = base .. job.url:match('/books/.*')
                    elseif arg == '--output' then
                        job.path = args[i + 1]
                    elseif arg == '--proto' or arg == '--proto-redir' then
                        assert(args[i + 1] == '=https')
                        args[i + 1] = '=http'
                    elseif arg == '--max-time' then
                        assert(args[i + 1] == '45')
                        args[i + 1] = job.url:find('search=timeout', 1, true) and '0.3' or '5'
                    end
                end
                vim.list_extend(args, {'--noproxy', '*'})
                local process = _G.lilt_catalog_system(args, opts, function(result)
                    job.exited = true
                    callback(result)
                end)
                return {kill=function(_, signal) job.killed=true; process:kill(signal) end}
            end
            require('lilt').setup({library=home})
        """, directory, f"http://127.0.0.1:{server.server_port}")

        def settled(text):
            ready = nvim.exec_lua("""local target = ...; return vim.wait(2000, function()
                return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n'):find(target, 1, true)
            end, 5)""", text)
            check(ready, "catalog reaches " + text)
            return screen()

        try:
            width, height = 52, 10
            nvim.ui_try_resize(width, height)
            input_keys(":Lilt<CR>")
            choose("Discover online")
            rows = screen()
            check(sum("Loading…" in row for row in rows) == 1
                  and "h back" in "\n".join(rows), "initial progress appears once and footer advertises navigation")
            input_keys("s")
            check(nvim.eval("mode()") == "i", "Search is available while initial Explore request is pending")
            rows = input_keys("<Esc>")
            check(any("Loading…" in row for row in rows)
                  and nvim.exec_lua("return #_G.lilt_catalog_jobs") == 1,
                  "cancelling search input preserves the pending catalog request")
            input_keys("s")
            input_keys("empty<CR>")
            rows = settled("No matching works found")
            check(any("No matching works found" in row for row in rows), "empty results are visible without scrolling")
            check("No matching works found" in nvim.current.buffer[nvim.current.window.cursor[0] - 1],
                  "empty results select their explanation")
            check(nvim.exec_lua("return _G.lilt_catalog_jobs[1].killed"), "search submission cancels initial browsing")
            release.set()
            pause(50)
            check("No matching works found" in "\n".join(nvim.current.buffer[:]), "late Explore completion preserves empty search")

            input_keys("s<C-u>error<CR>")
            rows = settled("Could not complete search.")
            check(any("Retry failed" in row for row in rows) and not any("No matching works found" in row for row in rows),
                  "HTTP failures offer retry and never claim zero matches")
            check("503" in "\n".join(nvim.current.buffer[:]), "HTTP failure retains its transport cause")
            before_retry = len(received)
            fail_error = False
            input_keys("r")
            settled("Local catalog work")
            check(len(received) == before_retry + 1 and received[-1].get("search") == ["error"],
                  "retry repeats the failed query and recovers when the service returns")

            release.clear()
            input_keys("s<C-u>timeout<CR>")
            rows = settled("Could not complete search.")
            check("timed out" in "\n".join(nvim.current.buffer[:]) and not any("No matching works found" in row for row in rows),
                  "real curl timeout ends loading with an error")
            input_keys("s<C-u>found<CR>")
            rows = settled("Local catalog work")
            check(any("Local catalog work" in row for row in rows), "new query recovers after timeout")
            input_keys("]")
            rows = settled("Second catalog page")
            check("Second catalog page" in "\n".join(nvim.current.buffer[:]) and received[-1].get("page") == ["2"],
                  "paging preserves the search")
            check("Local catalog work" in "\n".join(nvim.current.buffer[:]),
                  "load more retains earlier results")

            input_keys("s<C-u>slow<CR>")
            input_keys("s<C-u>empty<CR>")
            settled("No matching works found")
            check(nvim.exec_lua("return _G.lilt_catalog_jobs[#_G.lilt_catalog_jobs-1].killed"),
                  "new search cancels a pending search")
            input_keys("s<C-u>slow<CR>hh")
            check("Discover online" in "\n".join(nvim.current.buffer[:]), "back leaves a pending search")
            choose("Discover online")
            input_keys("q")
            release.set()
            check(not floats(), "close releases the pending catalog window")
            check(nvim.exec_lua("""return vim.wait(2000, function()
                for _, job in ipairs(_G.lilt_catalog_jobs) do
                    if not job.exited or vim.uv.fs_stat(job.path) then return false end
                end
                return true
            end, 5)"""), "cancellation reaps curl and removes its response files")
        finally:
            release.set()
            input_keys("<Esc>")
            nvim.exec_lua("require('lilt.online.providers').list=_G.lilt_catalog_providers; _G.lilt_catalog_providers=nil; vim.system=_G.lilt_catalog_system; _G.lilt_catalog_system=nil; _G.lilt_catalog_jobs=nil")
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)
            width, height = 90, 22
            nvim.ui_try_resize(width, height)


def online_tests():
    global width, height
    with tempfile.TemporaryDirectory(prefix="lilt-online-ui-") as directory:
        home = Path(directory) / "library"
        fixture = Path(directory) / "source.epub"
        write_epub(fixture)
        book = {
            "id": 11, "title": "Test Letters", "authors": [{"name": "A. Writer"}],
            "subjects": ["Letters -- Fiction"], "languages": ["en"], "copyright": False,
            "translators": [{"name": "A. Translator"}], "bookshelves": ["Letters"],
            "media_type": "Text", "formats": {"application/epub+zip": "https://www.gutenberg.org/ebooks/11.epub.noimages"},
        }
        other_book = dict(book, id=12, title="Other Letters", copyright=True)
        long_title = "天地玄黃宇宙洪荒" * 12
        long_author = "A writer with a lengthy unabridged name " * 3
        long_books = [dict(other_book, id=identity, title=long_title + ending,
                           authors=[{"name": long_author}])
                      for identity, ending in ((13, "上卷"), (14, "下卷"))]
        long_books[0]["copyright"] = False
        catalog = json.dumps({"count": 4, "next": None, "results": [book, other_book, *long_books]})
        # Control only the process boundary; exercise the real floating search,
        # async redraw, catalog parser, converter, installation, and reading UI.
        nvim.exec_lua("""
            local home, catalog, source = ...
            local file = assert(io.open(source, 'rb'))
            local text = file:read('*a')
            file:close()
            _G.lilt_test_providers = require('lilt.online.providers').list
            require('lilt.online.providers').list = function(base)
                return {require('lilt.online.providers.gutenberg').new(base)}
            end
            _G.lilt_test_system = vim.system
            _G.lilt_test_requests = {}
            vim.system = function(args, opts, callback)
                if args[1] == 'pandoc' then return _G.lilt_test_system(args, opts, callback) end
                local path, url
                for i, arg in ipairs(args) do
                    if arg == '--output' then path = args[i + 1] end
                    if arg == '--url' then url = args[i + 1] end
                end
                table.insert(_G.lilt_test_requests, url)
                local killed = false
                vim.defer_fn(function()
                    if killed then return end
                    local file = assert(io.open(path, 'wb'))
                    file:write(url:find('/books/', 1, true) and catalog or text)
                    file:close()
                    callback({code=0, stderr=''})
                end, 100)
                return {kill=function() killed=true end}
            end
            require('lilt').setup({library=home})
        """, str(home), catalog, str(fixture))
        try:
            input_keys(":Lilt<CR>")
            choose("Discover online")
            rows = screen()
            loading_size = nvim.api.win_get_config(nvim.current.window.handle)
            check(any("Loading…" in row for row in rows), "catalog loading stays visible")
            rows = pause(130)
            loaded_size = nvim.api.win_get_config(nvim.current.window.handle)
            check((loading_size["width"], loading_size["height"]) == (loaded_size["width"], loaded_size["height"]),
                  "catalog completion keeps the float dimensions")
            check(any("Test Letters" in row for row in rows), "online entry browses works without a query")
            width, height = 28, 10
            nvim.ui_try_resize(width, height)
            input_keys("")
            result_rows = [row for row, line in enumerate(nvim.current.buffer[:], 1) if "天地" in line]
            check(len(result_rows) == 2 and all(nvim.current.buffer[row - 1].rstrip().endswith("…") for row in result_rows),
                  "long Unicode works each occupy one clipped result row")
            for identity, result_row in zip((13, 14), result_rows):
                rows = input_keys(str(result_row) + "G")
                check(nvim.current.window.options["cursorline"], "clipped result rows remain native actions")
                result_view = (nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"])
                input_keys("<CR>")
                details = "".join("".join(line.split()) for line in nvim.current.buffer[:])
                check("gutenberg:" + str(identity) in details
                      and "".join(long_books[identity - 13]["title"].split()) in details
                      and "".join(long_author.split()) in details,
                      "identical clipped labels open their exact source with complete title and author")
                rows = screen()
                if identity == 13:
                    check(any("a Add" in row for row in rows),
                          "28x10 information advertises Add despite a title longer than the viewport")
                    before_name = nvim.exec_lua("return #_G.lilt_test_requests")
                    input_keys("a")
                    check(nvim.eval("mode()") == "i" and nvim.current.buffer[0] == long_books[0]["title"],
                          "advertised Add opens naming directly without downloading text")
                    input_keys("<Esc>")
                    check(nvim.exec_lua("return #_G.lilt_test_requests") == before_name,
                          "cancelling naming from long information makes no acquisition request")
                else:
                    check(not any("a Add" in row or "o Open" in row for row in rows),
                          "unsupported information advertises no acquisition action")
                input_keys("h")
                check((nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"]) == result_view,
                      "details back restores the compact result row and viewport")
            width, height = 90, 22
            nvim.ui_try_resize(width, height)
            input_keys("")
            formatting = {name: nvim.api.get_option_value(name, {"scope": "global"})
                          for name in ("textwidth", "wrapmargin", "formatoptions")}
            try:
                for name, value in {"textwidth": 12, "wrapmargin": 2, "formatoptions": "t"}.items():
                    nvim.api.set_option_value(name, value, {"scope": "global"})
                input_keys("s")
                query = "a writer with a long literary name"
                input_keys(query)
                check(nvim.current.buffer[:] == [query], "editor formatting does not split a search query")
                input_keys("<CR>")
                pause(130)
                check(nvim.exec_lua("return _G.lilt_test_requests[#_G.lilt_test_requests]").endswith(
                    "search=a%20writer%20with%20a%20long%20literary%20name"),
                    "search submits the complete query despite editor formatting defaults")
            finally:
                for name, value in formatting.items():
                    nvim.api.set_option_value(name, value, {"scope": "global"})
            rows = input_keys("s")
            input_keys("<C-u>")
            check(any("Search title or author" in row for row in rows), "search stays inside the Picker float")
            check(nvim.eval("mode()") == "i" and len(floats()) == 1, "search focuses one editable line in the same float")
            width, height = 24, 8
            nvim.ui_try_resize(width, height)
            rows = input_keys("writx<BS>er")
            config = nvim.api.win_get_config(nvim.current.window.handle)
            check(config["width"] + 2 <= width and nvim.eval("mode()") == "i", "search resizes without losing editing focus")
            check(nvim.current.buffer[:] == ["writer"], "search retains native insertion and Backspace")
            width, height = 90, 22
            nvim.ui_try_resize(width, height)
            input_keys("<CR>")
            rows = pause(130)
            check(any("Test Letters" in row for row in rows), "search returns to the online picker")
            check(nvim.exec_lua("return _G.lilt_test_requests[#_G.lilt_test_requests]:find('search=writer',1,true) ~= nil"),
                  "query reaches the catalog")
            previous = (nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"])
            requests = nvim.exec_lua("return #_G.lilt_test_requests")
            input_keys("s")
            check(nvim.current.buffer[:] == ["writer"], "search reopens the current query")
            input_keys("<C-u>discard me<Esc>")
            check(nvim.exec_lua("return #_G.lilt_test_requests") == requests, "cancelled search sends no request")
            check(nvim.current.window.cursor == previous[0] and nvim.funcs.winsaveview()["topline"] == previous[1],
                  "cancelled search restores selection and scroll")
            order_row = next(row for row, line in enumerate(nvim.current.buffer[:], 1)
                             if line.strip().startswith("Search:"))
            nvim.current.window.cursor = (order_row, 0)
            input_keys("")
            metadata_view = (nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"])
            input_keys("s<Esc>")
            check(nvim.current.window.cursor == metadata_view[0]
                  and nvim.funcs.winsaveview()["topline"] == metadata_view[1]
                  and not nvim.current.window.options["cursorline"],
                  "cancelled search also restores an informational row")
            width, height = 40, 10
            nvim.ui_try_resize(width, height)
            input_keys("")
            for title in ("Test Letters", "Other Letters", "Test Letters"):
                result_row = next(row for row, line in enumerate(nvim.current.buffer[:], 1) if title in line)
                nvim.current.window.cursor = (result_row, 0)
                input_keys("")
                result_view = (nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"])
                rows = input_keys("<CR>")
                check(nvim.funcs.winsaveview()["topline"] == 1 and any(title in row for row in rows),
                      "each online work opens its details from the title")
                input_keys("G")
                check(nvim.funcs.winsaveview()["topline"] > 1, "details can scroll away from the title")
                input_keys("h")
                check(nvim.current.window.cursor == result_view[0]
                      and nvim.funcs.winsaveview()["topline"] == result_view[1],
                      "return from scrolled details restores result selection and scroll")
            width, height = 90, 22
            nvim.ui_try_resize(width, height)
            input_keys("")
            choose("Test Letters")
            input_keys("h")
            check(nvim.exec_lua("return #_G.lilt_test_requests") == requests, "details back retains loaded results")
            check("Test Letters" in nvim.current.buffer[nvim.current.window.cursor[0] - 1], "details back restores work selection")
            choose("Test Letters")
            rows = screen()
            check(any("gutenberg.org/ebooks/11" in row for row in rows), "selection exposes canonical provenance")
            metadata_text = "\n".join(nvim.current.buffer[:])
            check("Current online catalog metadata" in metadata_text
                  and "Translators: A. Translator" in metadata_text and "Bookshelves: Letters" in metadata_text,
                  "online details share bibliographic formatting with explicit catalog provenance")
            check(metadata_text.index("[a] Add to library") < metadata_text.index("Translators:")
                  and metadata_text.count("Author: A. Writer") == 1
                  and metadata_text.count("Test Letters") == 1,
                  "identity appears once and acquisition precedes remaining complete metadata")
            check(any("Add to library" in row for row in rows), "online details expose their primary action on the first screen")
            width, height = 40, 10
            nvim.ui_try_resize(width, height)
            rows = input_keys("G")
            check(not any("Test Letters" in row for row in rows), "short details window scrolls the title out of view")
            rows = input_keys("99k")
            check(nvim.current.window.cursor[0] == 1 and any("Test Letters" in row for row in rows),
                  "upward movement restores the online work title")
            menu_buf = nvim.current.buffer.number
            input_keys("<CR>l<Right>")
            check(nvim.exec_lua("return #_G.lilt_test_requests") == requests
                  and nvim.current.buffer.number == menu_buf,
                  "activating online metadata neither acquires nor leaves the details")
            rows = input_keys("<Down><Down>")
            check(any("Author: A. Writer" in row for row in rows) and not nvim.current.window.options["cursorline"],
                  "arrow movement can inspect online metadata")
            input_keys("<Up><Up>")
            check(nvim.current.window.cursor[0] == 1, "up arrow reaches the online title")
            width, height = 90, 22
            nvim.ui_try_resize(width, height)
            input_keys("")
            detail_size = nvim.api.win_get_config(nvim.current.window.handle)
            rows = input_keys("a")
            check(any("Library directory name" in row for row in rows), "acquisition asks for a directory name")
            check(nvim.current.buffer[0] == "Test Letters", "official title is editable without retyping")
            check(any("test-letters-gutenberg-11" in row for row in rows), "directory normalization is previewed")
            input_keys("<C-u>My_Letters")
            rows = input_keys("<CR>")
            pending_size = nvim.api.win_get_config(nvim.current.window.handle)
            check(any("Downloading" in row for row in rows), "acquisition progress stays visible")
            check((detail_size["width"], detail_size["height"]) == (pending_size["width"], pending_size["height"]),
                  "acquisition keeps the detail float dimensions")
            ready = nvim.exec_lua("""return vim.wait(5000, function()
                return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n'):find('The letter', 1, true) ~= nil
            end, 10)""")
            rows = screen()
            check(ready and any("The letter" in row for row in rows), "download goes straight to unit selection")
            rows = choose("The letter — 第一封信")
            check(nvim.current.buffer.name == str(home / "manuscripts/my-letters-gutenberg-11/002.txt"),
                  "acquired units use ordinary named manuscripts")
            check(any("Café" in row for row in rows), "prepared Unicode content appears in Ghost")
            nvim.command("LiltClose")
            input_keys(":Lilt<CR>")
            choose("Discover online")
            pause(130)
            choose("Test Letters")
            width, height = 28, 10
            nvim.ui_try_resize(width, height)
            rows = input_keys("")
            check(any("o Open" in row for row in rows) and not any("a Add" in row for row in rows),
                  "28x10 existing-copy information advertises Open rather than Add")
            input_keys("G")
            check(any("o Open" in row for row in screen()), "primary Open remains discoverable while reading long metadata")
            input_keys("hhq")
            pause(130)
            check(not floats(), "leaving online discovery cancels delayed UI work")
        finally:
            nvim.exec_lua("require('lilt.online.providers').list=_G.lilt_test_providers; _G.lilt_test_providers=nil; vim.system=_G.lilt_test_system; _G.lilt_test_system=nil; _G.lilt_test_requests=nil")


def group_presentation_tests():
    global width, height
    with tempfile.TemporaryDirectory(prefix="lilt-group-ui-") as directory:
        nvim.exec_lua("""
            _G.lilt_group_registry = require('lilt.online.providers').list
            _G.lilt_group_queries = {}
            local provider = {id='unglueit', name='Unglue.it', browse={}}
            provider.browse.explore = function(_, cb)
                cb(nil, {entries={{kind='group', id='collected',
                    label='Collected poems · Choose a copy', query={page=1}}}})
                return function() end
            end
            provider.expand = function(query, cb)
                table.insert(_G.lilt_group_queries, query.page)
                _G.lilt_group_finish = function()
                    local entries = {}
                    for i = 1, 2 do
                        entries[i] = {kind='work', title='Collected poems',
                            label='Collected poems · EPUB · CC BY 4.0 · supplied edition version '
                                .. query.page .. ' · exact copy ' .. i,
                            authors={'A. Poet'}, supported=false, availability='Unavailable: fixture',
                            source={provider='unglueit', id=tostring(i), url='https://example.org/' .. i}}
                    end
                    cb(nil, {title='Collected poems · Choose a copy', entries=entries,
                        count=2, next=query.page == 1 and {page=2} or nil})
                end
                return function() end
            end
            require('lilt.online.providers').list = function() return {provider} end
            require('lilt').setup({library=...})
        """, directory)
        try:
            width, height = 132, 30
            nvim.ui_try_resize(width, height)
            input_keys(":Lilt<CR>")
            choose("Discover online")
            check("Choose a copy ›" in "\n".join(nvim.current.buffer[:]), "aggregate groups visibly advertise expansion")
            width, height = 28, 10
            nvim.ui_try_resize(width, height)
            input_keys("")
            check(any("… ›" in line for line in nvim.current.buffer[:]),
                  "truncated groups keep their expansion marker on the same row")
            width, height = 132, 30
            nvim.ui_try_resize(width, height)
            input_keys("")
            parent = (nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"])
            rows = choose("Collected poems")
            check(any("Collected poems" in row for row in rows)
                  and sum("Loading…" in row for row in rows) == 1,
                  "pending group leads with selected content and one visible progress indicator")
            nvim.exec_lua("_G.lilt_group_finish()")
            rows = screen()
            content = nvim.current.buffer[:]
            check(sum("Unglue.it" in line for line in content) == 1
                  and any("Source: Unglue.it" in row for row in rows),
                  "single-source group retains its official source context")
            check(nvim.current.window.width == 96, "group results use the wider Discover allowance")
            first = next(line for line in content if "Collected poems · EPUB" in line)
            check(nvim.funcs.strdisplaywidth(first) > 64, "copy labels use the full group width")
            copy_row = next(i for i, line in enumerate(content, 1) if "copy 2" in line)
            input_keys(str(copy_row) + "G<CR>")
            check("unglueit:2" in "\n".join(nvim.current.buffer[:]), "compact copy opens its exact identity")
            input_keys("h]")
            check(any("Loading more…" in row for row in screen()), "group continuation keeps visible progress")
            nvim.exec_lua("_G.lilt_group_finish()")
            input_keys("h")
            check((nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"]) == parent
                  and nvim.exec_lua("return _G.lilt_group_queries") == [1, 2],
                  "group paging replaces one layer and Back restores its aggregate parent without a request")
            input_keys("q")
        finally:
            input_keys("<Esc>")
            nvim.exec_lua("""
                require('lilt.online.providers').list = _G.lilt_group_registry
                _G.lilt_group_registry=nil; _G.lilt_group_finish=nil; _G.lilt_group_queries=nil
            """)


def unified_discovery_tests():
    global width, height
    with tempfile.TemporaryDirectory(prefix="lilt-unified-ui-") as directory:
        nvim.exec_lua("""
            _G.lilt_unified_registry = require('lilt.online.providers').list
            _G.lilt_unified_system = vim.system
            vim.system = function() error('fake providers must never start a process') end
            _G.lilt_unified_jobs = {}
            local function source(id, name, search)
                local p = {id=id, name=name, browse={}}
                local function request(cursor, callback)
                    local job = {id=id, cursor=cursor, callback=callback}
                    table.insert(_G.lilt_unified_jobs, job)
                    return function() job.cancelled=true end
                end
                p.browse.explore = request
                if search then p.search = function(_, cursor, callback) return request(cursor, callback) end end
                return p
            end
            local first = source('gutenberg', 'Project Gutenberg', true)
            local slow = source('poetrydb', 'PoetryDB', true)
            local browse = source('unglueit', 'Unglue.it', false)
            require('lilt.online.providers').list = function() return {first, slow, browse} end
            _G.lilt_unified_finish = function(index, err, titles, more)
                local job = _G.lilt_unified_jobs[index]
                local entries = {}
                for i, title in ipairs(titles or {}) do
                    entries[i] = {
                        kind='work', title=title, authors={'A. Writer'}, supported=false,
                        availability='Unavailable: fixture',
                        source={provider=job.id, id=title, url='https://example.org/' .. i},
                    }
                end
                job.callback(err ~= vim.NIL and err or nil, {
                    entries=entries, next=more ~= vim.NIL and more or nil,
                    title='Private source ready title',
                })
            end
            require('lilt').setup({library=...})
        """, directory)

        def finish(index, error=None, titles=None, more=None):
            nvim.exec_lua("_G.lilt_unified_finish(...)", index, error, titles or [], more)
            return screen()

        def text():
            return "\n".join(nvim.current.buffer[:])

        try:
            width, height = 40, 10
            nvim.ui_try_resize(width, height)
            input_keys(":Lilt<CR>")
            rows = choose("Discover online")
            check(any("Search title or author" in row for row in rows) and any("Explore" in row for row in rows),
                  "narrow Discover opens directly on content choices")
            check("Library" not in text() and "Choose source" not in text(), "Discover has no provider chooser")
            titles = ["Early work " + str(i) for i in range(1, 33)]
            titles[23] += " 天地é" * 20
            finish(1, titles=titles, more="next")
            width, height = 120, 24
            nvim.ui_try_resize(width, height)
            input_keys("")
            check(nvim.current.window.width == 96 and len(nvim.current.buffer[:]) == 35
                  and "Gutenberg" not in text(),
                  "wide Discover gives each work one row without a source rail")
            check(all(nvim.funcs.strdisplaywidth(line) <= nvim.current.window.width for line in nvim.current.buffer[:]),
                  "compact Unicode labels fit the available display width")
            check("Early work 1" in text() and sum("Loading…" in row for row in screen()) == 1
                  and "Loading" not in text(), "a successful source appears before slow peers settle")
            check("[r]" not in text() and "Load more" not in text(), "batch actions stay hidden while peers load")
            result_row = next(row for row, line in enumerate(nvim.current.buffer[:], 1) if "Early work 24 " in line)
            input_keys(str(result_row) + "G")
            rows = screen()
            author_row = next(row for row, line in enumerate(rows) if "A. Writer" in line)
            check(group_at(author_row, rows[author_row].index("A. Writer"), "Comment"),
                  "compact author text uses the muted Comment highlight")
            position = (nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"])
            finish(2, error="fixture service unavailable")
            finish(3)
            check((nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"]) == position,
                  "peer failure and completion preserve the selected compact result and scroll")
            check("Some results unavailable" in text() and "fixture service unavailable" in text(),
                  "successful results retain honest partial coverage and failure causes")
            check("Private source ready title" not in text(), "normal source diagnostics do not crowd results")
            input_keys("<CR>")
            check("gutenberg:Early work 24" in text() and "".join(titles[23].split()) in "".join(text().split())
                  and nvim.current.window.width == 76,
                  "compact work opens exact full information at the regular width")
            input_keys("h")
            check((nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"]) == position,
                  "details back restores the result viewport")
            width, height = 28, 10
            nvim.ui_try_resize(width, height)
            input_keys("")
            check(any("r retry" in row for row in screen()),
                  "28x10 keeps retry discoverable while scrolled among successful results")
            input_keys("<CR>")
            check("gutenberg:Earlywork24" in "".join(text().split()), "resize keeps the compact row attached to its work")
            input_keys("h")
            load_row = next(row for row, line in enumerate(nvim.current.buffer[:], 1) if "Load more" in line)
            input_keys(str(load_row) + "G")
            input_keys("<CR>")
            check(sum("Loading more…" in row for row in screen()) == 1 and "Loading" not in text(),
                  "explicit paging keeps a single visible footer indicator while the heading is offscreen")
            check(nvim.current.window.cursor[0] > 3 and nvim.funcs.winsaveview()["topline"] > 1,
                  "clicking Load more from the bottom retains the result boundary")
            finish(4, titles=["Later work"])
            check("Early work 1" in text() and "Later work" in text(), "next batch appends to the flat result list")
            choose("Retry failed")
            check(sum("Retrying…" in row for row in screen()) == 1 and "Retrying" not in text(), "retry keeps one visible footer indicator")
            check(nvim.current.buffer[nvim.current.window.cursor[0] - 1].strip().startswith("Later work")
                  and nvim.funcs.winsaveview()["topline"] > 1,
                  "clicking Retry failed retains the scrolled result boundary")
            check(nvim.exec_lua("return #_G.lilt_unified_jobs == 5 and _G.lilt_unified_jobs[5].id == 'poetrydb'"),
                  "Retry failed contacts only the failed peer")
            finish(5)
            check("Some results unavailable" not in text() and "Retry failed" not in text(), "empty retry success clears stale errors")
            width, height = 90, 24
            nvim.ui_try_resize(width, height)
            input_keys("s")
            input_keys("query<CR>")
            input_keys("s")
            input_keys("<C-u>native draft")
            search_buf = nvim.current.buffer.number
            finish(6, titles=["Search success"])
            finish(7)
            check(nvim.current.buffer.number == search_buf and nvim.current.buffer[:] == ["native draft"]
                  and nvim.eval("mode()") == "i", "progressive and final callbacks keep native search input and focus")
            input_keys("<Esc>")
            compact = " ".join(text().split())
            check("Search success" in compact and "Some collections are browse-only." in compact,
                  "search has one unobtrusive browse-only coverage note")
            input_keys("h")
            check("Explore" in text(), "Back restores the browse layer")
            width, height = 28, 10
            nvim.ui_try_resize(width, height)
            input_keys("s")
            input_keys("empty<CR>")
            finish(8)
            rows = finish(9)
            visible = " ".join(" ".join(row.split("│")[1] if "│" in row else row for row in rows).split())
            check("matching works found." in visible and "browse-only." in visible,
                  "28x10 empty search exposes its feedback and browse-only coverage without scrolling")
            input_keys("s<C-u>failed<CR>")
            finish(10, error="first search failure")
            rows = finish(11, error="second search failure")
            visible = " ".join(" ".join(row.split("│")[1] if "│" in row else row for row in rows).split())
            check("complete search." in visible and "browse-only." in visible and "r retry" in visible,
                  "28x10 failed search exposes incomplete feedback, coverage and recovery")
            input_keys("r")
            check(any("Retrying…" in row for row in screen()), "failed search retries without claiming an empty result")
            rows = finish(12, titles=["Recovered work " + str(i) for i in range(1, 25)])
            finish(13)
            check("Recovered work 1" in nvim.current.buffer[nvim.current.window.cursor[0] - 1]
                  and any("Recovered work 1" in row for row in screen())
                  and nvim.current.window.options["cursorline"],
                  "first successful results after empty/failed search focus a visible work rather than the coverage note")
            input_keys("s<C-u>pending<CR>hq")
            finish(14, titles=["Late result"])
            check(not floats() and nvim.exec_lua("return _G.lilt_unified_jobs[14].cancelled"),
                  "closing a pending feed cancels its sources and cannot resurrect the picker")

            before = nvim.exec_lua("return #_G.lilt_unified_jobs")
            width, height = 90, 24
            nvim.ui_try_resize(width, height)
            input_keys(":Lilt<CR>")
            choose("Discover online")
            finish(before + 1, titles=["Retained work " + str(i) for i in range(1, 33)], more="continue-first")
            finish(before + 2, error="paused peer failed")
            input_keys("b")
            choose("Explore")
            check(nvim.exec_lua("return #_G.lilt_unified_jobs == ... and _G.lilt_unified_jobs[#_G.lilt_unified_jobs].cancelled",
                                before + 3),
                  "returning to the paused category cancels its unfinished peer without auto-resuming")
            for width, height in ((90, 24), (64, 20), (44, 14), (28, 10)):
                nvim.ui_try_resize(width, height)
                rows = input_keys("gg")
                check("Paused" in text() and not any("Load more" in row for row in rows)
                      and "] load" in "\n".join(rows) and "r retry" in "\n".join(rows),
                      f"{width}-column paused footer exposes continuation and retry above offscreen actions")
            input_keys("r")
            check(nvim.exec_lua("return #_G.lilt_unified_jobs == ... and _G.lilt_unified_jobs[#_G.lilt_unified_jobs].id == 'poetrydb'",
                                before + 4)
                  and not any("] load" in row for row in screen()),
                  "retry only contacts the failed peer and hides continuation while loading")
            finish(before + 4)
            check(any("] load" in row for row in screen())
                  and not any("r retry" in row for row in screen()),
                  "settled retry leaves the paused continuation hint without a stale retry hint")
            input_keys("]")
            check(nvim.exec_lua("""
                local count, first = ...
                local jobs = _G.lilt_unified_jobs
                return #jobs == count and jobs[first].id == 'gutenberg'
                    and jobs[first].cursor == 'continue-first' and jobs[first+1].id == 'unglueit'
            """, before + 6, before + 5)
                  and not any("] load" in row for row in screen()),
                  "advertised continuation resumes cancelled and paginated sources without refetching the exhausted peer")
            finish(before + 5)
            finish(before + 6)
            check("Paused" not in text()
                  and not any("] load" in row for row in screen()),
                  "completed feed clears the paused continuation hint")
            input_keys("q")
            check(not Path(directory, "references").exists(), "fake discovery never acquires or changes a library")
        finally:
            input_keys("<Esc>")
            nvim.exec_lua("""
                require('lilt.online.providers').list=_G.lilt_unified_registry
                vim.system=_G.lilt_unified_system
                _G.lilt_unified_registry=nil; _G.lilt_unified_system=nil
                _G.lilt_unified_jobs=nil; _G.lilt_unified_finish=nil
            """)
            width, height = 90, 22
            nvim.ui_try_resize(width, height)


def run():
    global width, height
    nvim.ui_attach(width, height, rgb=True, ext_linegrid=True, ext_hlstate=True)
    nvim.options["runtimepath"] = str(Path.cwd()) + "," + nvim.options["runtimepath"]
    nvim.command("runtime plugin/lilt.lua")
    nvim.exec_lua("require('lilt').setup({library=vim.fn.tempname()})")
    open_example()
    buf = nvim.current.buffer.number
    reference = Path("examples/alice/alice.txt").read_text(encoding="utf-8").splitlines()
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
    check(any("Lilt · Reference" in row for row in rows)
          and any("Lilt · Manuscript" in row for row in rows),
          "both Split panes retain their labels after assigning buffers")
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
    open_example()
    check(nvim.current.buffer.number == buf, "can resume after manual reference closure")
    nvim.command("LiltClose")
    check(len(nvim.tabpages) == 1, "all reading windows removed on close")
    check(nvim.api.buf_get_lines(buf, 0, -1, False) == authored, "close retains actual writing")
    check(not floats() and len(nvim.buffers) == 2, "close leaves no hint or reference buffers")
    library_tests()
    local_presentation_tests()
    library_diagnostic_tests()
    information_tests()
    catalog_feedback_tests()
    online_tests()
    group_presentation_tests()
    unified_discovery_tests()
    print(f"Lilt UI: {checks} assertions passed on {nvim.exec_lua('return tostring(vim.version())')}")


try:
    run()
finally:
    try:
        nvim.command("qa!")
    except (EOFError, OSError):
        pass
    nvim.close()
