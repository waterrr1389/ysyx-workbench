#!/usr/bin/env python3

import argparse
import os
from pathlib import Path
import sys
import tempfile
import tomllib


TRACE_KEYS = {
    "instruction": "NPC_ITRACE",
    "function": "NPC_FTRACE",
    "memory": "NPC_MTRACE",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate the NPC build configuration header")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_config(path: Path) -> dict[str, bool]:
    with path.open("rb") as config_file:
        config = tomllib.load(config_file)

    unknown_sections = set(config) - {"trace"}
    if unknown_sections:
        names = ", ".join(sorted(unknown_sections))
        raise ValueError(f"unknown configuration section(s): {names}")

    trace = config.get("trace")
    if not isinstance(trace, dict):
        raise ValueError("missing [trace] configuration section")

    unknown_keys = set(trace) - set(TRACE_KEYS)
    if unknown_keys:
        names = ", ".join(sorted(unknown_keys))
        raise ValueError(f"unknown trace option(s): {names}")

    missing_keys = set(TRACE_KEYS) - set(trace)
    if missing_keys:
        names = ", ".join(sorted(missing_keys))
        raise ValueError(f"missing trace option(s): {names}")

    for key, value in trace.items():
        if not isinstance(value, bool):
            raise ValueError(f"trace.{key} must be a boolean")

    return trace


def render_header(trace: dict[str, bool], source: Path) -> str:
    lines = [
        "#pragma once",
        "",
        f"/* Generated from {source.as_posix()}. */",
        "",
    ]
    for key, macro in TRACE_KEYS.items():
        lines.append(f"#define {macro} {int(trace[key])}")
    lines.extend(
        [
            "",
            "#define NPC_NEED_INST_TRACE (NPC_ITRACE || NPC_FTRACE)",
            "",
        ]
    )
    return "\n".join(lines)


def update_if_changed(path: Path, content: str) -> None:
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", text=True
    )
    try:
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as temporary_file:
            temporary_file.write(content)
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def main() -> None:
    args = parse_args()
    try:
        trace = load_config(args.input)
    except (OSError, tomllib.TOMLDecodeError, ValueError) as error:
        print(f"configuration error: {error}", file=sys.stderr)
        raise SystemExit(2) from error
    update_if_changed(args.output, render_header(trace, args.input))
    print(f"NPC configuration: {args.input}")


if __name__ == "__main__":
    main()
