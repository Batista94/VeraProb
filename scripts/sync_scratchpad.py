#!/usr/bin/env python3
"""Scratchpad state sync (INV-42). No external dependencies."""

import argparse
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def filter_caveman(text):
    """Remove subjective noise phrases. Preserve facts."""
    patterns = [
        r"eu acho (que )?",
        r"acho (que )?",
        r"talvez ",
        r"basicamente ",
        r"tentei ",
        r"digamos (que )?",
        r"kind of ",
        r"sort of ",
        r"basically ",
        r"kinda ",
    ]
    result = text
    for pattern in patterns:
        result = re.sub(pattern, "", result, flags=re.IGNORECASE)
    return result.strip()


def get_timestamp():
    """Return UTC timestamp: YYYY-MM-DD HH:MM"""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")


def ensure_file_exists(root_path):
    """Create .veraprob/scratchpad.md with full INV-42 structure if missing."""
    veraprob_dir = Path(root_path) / ".veraprob"
    scratchpad_file = veraprob_dir / "scratchpad.md"

    if scratchpad_file.exists():
        return scratchpad_file

    veraprob_dir.mkdir(exist_ok=True)

    structure = """# VERA-PROB-FORENSIC-STATE

## Architect Decisions
(no entries yet)

## Current Mission State
(no entries yet)
"""
    scratchpad_file.write_text(structure, encoding="utf-8")
    return scratchpad_file


def find_section(content, section_name):
    """Find section header and its boundaries. Returns (start, end) line indices."""
    lines = content.split("\n")
    start = None

    for i, line in enumerate(lines):
        if line.startswith(f"## {section_name}"):
            start = i
            break

    if start is None:
        return None, None

    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break

    return start, end


def update_scratchpad(scratchpad_path, persona, section, action, content):
    """Smart merge: append or overwrite per section."""
    if not content.strip():
        return

    content = filter_caveman(content)
    if not content.strip():
        return

    current = scratchpad_path.read_text(encoding="utf-8")
    lines = current.split("\n")

    start, end = find_section(current, section)
    if start is None:
        raise ValueError(f"Section '{section}' not found")

    timestamp = get_timestamp()
    entry = f"[{persona} | {timestamp}]\n{content}"
    entry_lines = entry.split("\n")

    # Remove placeholder if present
    section_content_start = start + 1
    if (
        section_content_start < len(lines)
        and lines[section_content_start].strip() == "(no entries yet)"
    ):
        lines.pop(section_content_start)
        end -= 1

    if action == "append":
        lines = lines[:end] + entry_lines + [""] + lines[end:]
    elif action == "overwrite":
        lines = lines[: start + 1] + entry_lines + [""] + lines[end:]
    else:
        raise ValueError(f"Unknown action: {action}")

    scratchpad_path.write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(
        description="Scratchpad state sync (INV-42)",
        add_help=False,
    )
    parser.add_argument("--persona", required=True, help="Persona name")
    parser.add_argument("--section", required=True, help="Section name")
    parser.add_argument("--action", required=True, help="append or overwrite")
    parser.add_argument("--content", required=True, help="State content")
    parser.add_argument("--root", default=".", help="Project root path")

    args = parser.parse_args()

    try:
        scratchpad_path = ensure_file_exists(args.root)
        update_scratchpad(
            scratchpad_path,
            args.persona,
            args.section,
            args.action,
            args.content,
        )
        print("[INV-42] State Synced.")
        sys.exit(0)
    except Exception as e:
        print(f"[INV-42] Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
