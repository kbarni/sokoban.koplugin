#!/usr/bin/env python3
"""Convert a Sokoban level file in "; N" format to a KOReader Lua module.

Usage:
    python3 convert.py Microban.txt
    python3 convert.py Microban.txt --name "Microban" --author "David W. Skinner"

The output file is written next to the input file with a .lua extension.
"""

import argparse
import os
import re
import sys


def parse_levels(text):
    """Split text on '; N [optional title]' headers and return a list of level strings."""
    parts = re.split(r"^;\s*\d+[^\n]*\n", text, flags=re.MULTILINE)
    levels = []
    for part in parts[1:]:
        lines = part.split("\n")
        while lines and lines[0].strip() == "":
            lines.pop(0)
        while lines and lines[-1].strip() == "":
            lines.pop()
        if lines:
            levels.append("\n".join(lines))
    return levels


def to_lua(levels, name, author, source=None):
    lines = []
    if author:
        lines.append(f"-- {name} by {author}")
    if source:
        lines.append(f"-- Source: {source}")
    lines.append("local M = {}")
    lines.append(f'M.name   = "{name}"')
    if author:
        lines.append(f'M.author = "{author}"')
    lines.append("M.levels = {")
    for i, lvl in enumerate(levels, 1):
        lines.append(f"[{i}] = [[")
        lines.append(lvl + "]],")
    lines.append("}")
    lines.append("return M")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Convert Sokoban .txt to Lua module.")
    parser.add_argument("input", help="Input .txt file")
    parser.add_argument("--name", help="Level set name (default: filename stem)")
    parser.add_argument("--author", default="", help="Author name")
    parser.add_argument("--source", default="", help="Source URL comment")
    args = parser.parse_args()

    input_path = args.input
    if not os.path.isfile(input_path):
        print(f"Error: file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    with open(input_path, encoding="utf-8") as f:
        text = f.read()

    levels = parse_levels(text)
    if not levels:
        print("Error: no levels found in file.", file=sys.stderr)
        sys.exit(1)

    stem = os.path.splitext(os.path.basename(input_path))[0]
    name = args.name or stem
    output_path = os.path.join(os.path.dirname(input_path), stem.lower() + ".lua")

    lua = to_lua(levels, name, args.author, args.source)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(lua)

    print(f"Written {len(levels)} levels to {output_path}")


if __name__ == "__main__":
    main()
