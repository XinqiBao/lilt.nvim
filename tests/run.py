"""Bounded, isolated verification. Run with the test virtual environment's Python."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from fixtures.epub import write_epub, write_navigation_epub

SUITES = {
    "compare": "core/compare.lua",
    "work": "core/work.lua",
    "epub": "core/epub.lua",
    "library": "core/library.lua",
    "manuscript": "editor/manuscript.lua",
    "session": "editor/session.lua",
    "lifecycle": "editor/lifecycle.lua",
    "cache": "editor/cache.lua",
    "picker": "editor/picker.lua",
    "online": "editor/online.lua",
    "ui": "ui.py",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nvim", default="nvim", help="Neovim executable (default: PATH)")
    parser.add_argument("--suite", action="append", choices=SUITES,
                        help="run only this suite (repeatable; default: all)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="lilt-tests-") as directory:
        env = os.environ.copy()
        for name in ("CONFIG", "DATA", "STATE", "CACHE"):
            env["XDG_" + name + "_HOME"] = str(Path(directory) / name.lower())
        env["NVIM_APPNAME"] = "lilt-tests"
        fixture = Path(directory) / "source.epub"
        write_epub(fixture)
        env["LILT_TEST_EPUB"] = str(fixture)
        for mode in ("nav", "broken-nav", "unusable-nav", "no-toc", "long", "caption-label", "unlabelled"):
            write_navigation_epub(Path(directory) / (mode + ".epub"), mode)
        commands = [
            [args.nvim, "--version"],
            ["stylua", "--version"],
            ["selene", "--version"],
            ["pandoc", "--version"],
            ["stylua", "--check", "lua", "plugin", "pandoc", "tests"],
            ["selene", "lua", "plugin", "pandoc", "tests"],
        ]
        for suite in args.suite or SUITES:
            path = "tests/" + SUITES[suite]
            if path.endswith(".lua"):
                commands.append([args.nvim, "--headless", "-u", "NONE", "-i", "NONE",
                                 "--cmd", "set rtp^=.", "-l", path])
            else:
                commands.append([sys.executable, path, args.nvim])
        print(sys.version, flush=True)
        for command in commands:
            print("+ " + " ".join(command), flush=True)
            try:
                subprocess.run(command, cwd=root, env=env, check=True, timeout=60)
            except (OSError, subprocess.SubprocessError) as error:
                parser.exit(1, f"Verification failed: {error}\n")


if __name__ == "__main__":
    main()
