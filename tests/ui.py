"""Real Neovim UI integration; development-only dependency: pynvim.

Run from the repository root: python3 tests/ui.py [path/to/nvim]
"""
import json
import shutil
import sys
import tempfile
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
    return input_keys("Glll")


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
            for _ in range(2):
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


def native_edit_tests():
    with tempfile.TemporaryDirectory(prefix="lilt-native-edit-") as directory:
        path = Path(directory) / "other.txt"
        path.write_text("Other writing\n", encoding="utf-8")
        for view, reference in (("Ghost", False), ("Split", False), ("Split", True)):
            open_example()
            buf = nvim.current.buffer.number
            text = nvim.current.buffer[:]
            nvim.command("Lilt" + view)
            if reference:
                nvim.command("wincmd k")
            win = nvim.current.window
            input_keys(":edit " + str(path) + "<CR>")
            check(nvim.current.window == win and Path(nvim.current.buffer.name).resolve() == path.resolve(),
                  "native edit keeps focus in the repurposed " + view + " pane")
            check(nvim.current.buffer[:] == ["Other writing"] and not floats(),
                  "repurposed window displays the new file without presentation resources")
            check(nvim.api.buf_get_lines(buf, 0, -1, False) == text,
                  "native edit retains the manuscript")
            input_keys(":q<CR>")
            check(len(nvim.tabpages) == 1, "native quit closes the repurposed tab")


def library_tests():
    global width, height
    with tempfile.TemporaryDirectory(prefix="lilt-library-") as directory:
        root = Path(directory)
        source = root / "source" / "letters"
        source.mkdir(parents=True)
        (source / "opening.txt").write_text("First line.\n\nLast line.\n", encoding="utf-8")
        (source / "reply.txt").write_text("Reply.\n", encoding="utf-8")
        (source / "lilt.json").write_text(json.dumps({
            "title": "Letters", "author": "A writer with a long biographical name " * 5, "units": [
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
        choose("Add local work")
        rows = input_keys(str(source) + "<CR>")
        check(any("Opening" in row and "—" in row for row in rows), "import proceeds to ordered unit selection")
        list_win = nvim.current.window
        preview_win = next(win for win in floats() if win != list_win)
        check(nvim.current.window == list_win and len(floats()) == 2, "unit selection previews automatically without focus changes")
        check(preview_win.buffer[:] == ["First line.", "", "Last line."], "preview preserves the reference opening")
        check(preview_win.buffer.options["readonly"] and not preview_win.buffer.options["modifiable"],
              "unit preview is read-only")
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
        input_keys(":Lilt<CR>Gllh")
        check(any("Alice" in line for line in nvim.current.buffer[:]), "h returns from units to example works")
        input_keys("q")
        check(nvim.current.buffer.number == buf, "quit from nested pages restores reading focus")
        nvim.command("LiltClose")
        nvim.command("LiltGhost")
        check(len(nvim.tabpages) == 1 and not floats(), "Ghost cannot reopen a closed session")
        nvim.api.buf_delete(buf, {})
        input_keys(":Lilt<CR>ll")
        check(nvim.current.buffer[:] == ["First"], "saved chapter reloads after buffer deletion")
        input_keys("A line.<Esc>:w<CR>")
        saved_buf = nvim.current.buffer.number
        nvim.command("LiltClose")
        nvim.api.buf_delete(saved_buf, {})  # release native swap before another process opens it
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
            check(resumed.current.buffer[:] == ["First line."], "new Neovim process resumes saved manuscript through picker")
            resumed.exec_lua("require('lilt').open(); vim.api.nvim_feedkeys('Glll', 'xt', false)")
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


def online_tests():
    global width, height
    with tempfile.TemporaryDirectory(prefix="lilt-online-ui-") as directory:
        home = Path(directory) / "library"
        fixture = Path("tests/fixtures/gutenberg.txt").read_text(encoding="utf-8")
        book = {
            "id": 11, "title": "Test Letters", "authors": [{"name": "A. Writer"}],
            "subjects": ["Letters -- Fiction"], "languages": ["en"], "copyright": False,
            "media_type": "Text", "formats": {"text/plain; charset=utf-8": "https://www.gutenberg.org/ebooks/11.txt.utf-8"},
        }
        other_book = dict(book, id=12, title="Other Letters", copyright=True)
        catalog = json.dumps({"count": 2, "next": None, "results": [book, other_book]})
        # Control only the process boundary; exercise the real floating search,
        # async redraw, catalog parser, converter, installation, and reading UI.
        nvim.exec_lua("""
            local home, catalog, text = ...
            _G.lilt_test_system = vim.system
            _G.lilt_test_requests = {}
            vim.system = function(args, _, callback)
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
        """, str(home), catalog, fixture)
        try:
            input_keys(":Lilt<CR>")
            rows = choose("Discover online")
            loading_size = nvim.api.win_get_config(nvim.current.window.handle)
            check(any("Loading catalog" in row for row in rows), "catalog loading stays visible")
            rows = pause(130)
            loaded_size = nvim.api.win_get_config(nvim.current.window.handle)
            check((loading_size["width"], loading_size["height"]) == (loaded_size["width"], loaded_size["height"]),
                  "catalog completion keeps the float dimensions")
            check(any("Test Letters" in row for row in rows), "online entry browses works without a query")
            rows = input_keys("s")
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
            check(nvim.exec_lua("return _G.lilt_test_requests[2]:find('search=writer',1,true) ~= nil"),
                  "query reaches the catalog")
            previous = (nvim.current.window.cursor, nvim.funcs.winsaveview()["topline"])
            requests = nvim.exec_lua("return #_G.lilt_test_requests")
            input_keys("s")
            check(nvim.current.buffer[:] == ["writer"], "search reopens the current query")
            input_keys("<C-u>discard me<Esc>")
            check(nvim.exec_lua("return #_G.lilt_test_requests") == requests, "cancelled search sends no request")
            check(nvim.current.window.cursor == previous[0] and nvim.funcs.winsaveview()["topline"] == previous[1],
                  "cancelled search restores selection and scroll")
            input_keys("2gg")  # the informational Order heading
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
            rows = input_keys("<Down>")
            check(any("Author: A. Writer" in row for row in rows) and not nvim.current.window.options["cursorline"],
                  "arrow movement can inspect online metadata")
            input_keys("<Up>")
            check(nvim.current.window.cursor[0] == 1, "up arrow reaches the online title")
            width, height = 90, 22
            nvim.ui_try_resize(width, height)
            input_keys("")
            detail_size = nvim.api.win_get_config(nvim.current.window.handle)
            rows = input_keys("a")
            pending_size = nvim.api.win_get_config(nvim.current.window.handle)
            check(any("Downloading" in row for row in rows), "acquisition progress stays visible")
            check((detail_size["width"], detail_size["height"]) == (pending_size["width"], pending_size["height"]),
                  "acquisition keeps the detail float dimensions")
            rows = pause(130)
            check(any("CHAPTER I." in row for row in rows), "download goes straight to unit selection")
            rows = input_keys("jl")
            check(nvim.current.buffer.name == str(home / "manuscripts/gutenberg-11/002.txt"),
                  "acquired units use ordinary named manuscripts")
            check(any("Café" in row for row in rows), "prepared Unicode content appears in Ghost")
            input_keys("iA letter.<Esc>:w<CR>:LiltSplit<CR>")
            check(len(nvim.current.tabpage.windows) == 2, "acquired work supports Split")
            input_keys(":LiltClose<CR>:Lilt<CR>l")
            check(any("%" in line for line in nvim.current.buffer[:]), "local library reports saved online-work progress")
            input_keys("jl")
            check(nvim.current.buffer[:] == ["A letter."], "local library resumes the acquired manuscript")
            nvim.command("LiltClose")
            input_keys(":Lilt<CR>")
            choose("Discover online")  # close while request is pending
            input_keys("hq")
            pause(130)
            check(not floats(), "leaving online discovery cancels delayed UI work")
        finally:
            nvim.exec_lua("vim.system=_G.lilt_test_system; _G.lilt_test_system=nil; _G.lilt_test_requests=nil")


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
    open_example()
    check(nvim.current.buffer.number == buf, "can resume after manual reference closure")
    nvim.command("LiltClose")
    check(len(nvim.tabpages) == 1, "all reading windows removed on close")
    check(nvim.api.buf_get_lines(buf, 0, -1, False) == authored, "close retains actual writing")
    check(not floats() and len(nvim.buffers) == 2, "close leaves no hint or reference buffers")
    native_edit_tests()
    library_tests()
    online_tests()
    print(f"Lilt UI: {checks} assertions passed on {nvim.exec_lua('return tostring(vim.version())')}")


try:
    run()
finally:
    try:
        nvim.command("qa!")
    except (EOFError, OSError):
        pass
    nvim.close()
