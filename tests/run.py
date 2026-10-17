"""Bounded, isolated verification. Run with the test virtual environment's Python."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nvim", default="nvim", help="Neovim executable (default: PATH)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="lilt-tests-") as directory:
        env = os.environ.copy()
        for name in ("CONFIG", "DATA", "STATE", "CACHE"):
            env["XDG_" + name + "_HOME"] = str(Path(directory) / name.lower())
        env["NVIM_APPNAME"] = "lilt-tests"
        commands = [
            [args.nvim, "--version"],
            ["stylua", "--version"],
            ["selene", "--version"],
            ["stylua", "--check", "lua", "plugin", "tests"],
            ["selene", "lua", "plugin", "tests"],
        ]
        for suite in ("compare", "work", "library", "reading", "picker", "online", "headless", "lifecycle", "cache"):
            commands.append([args.nvim, "--headless", "-u", "NONE", "-i", "NONE",
                             "--cmd", "set rtp^=.", "-l", f"tests/{suite}.lua"])
        commands.append([sys.executable, "tests/ui.py", args.nvim])
        print(sys.version, flush=True)
        for command in commands:
            print("+ " + " ".join(command), flush=True)
            try:
                subprocess.run(command, cwd=root, env=env, check=True, timeout=60)
            except (OSError, subprocess.SubprocessError) as error:
                parser.exit(1, f"Verification failed: {error}\n")


if __name__ == "__main__":
    main()
