#!/bin/bash
# Generate compile_commands.json for both am and klib in abstract-machine

set -e

# Default ARCH, can be overridden by environment variable
ARCH=${ARCH:-riscv32-nemu}

echo "Generating compile_commands.json for ARCH=$ARCH"

# Check if bear is installed
if ! command -v bear &> /dev/null; then
    echo "Error: bear is not installed. Please install it first."
    echo "On Ubuntu/Debian: sudo apt install bear"
    echo "On macOS: brew install bear"
    exit 1
fi

# Get the absolute path of the script's directory (assuming script is in abstract-machine root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

AM_HOME="$SCRIPT_DIR"
export AM_HOME
export ARCH

echo "Working directory: $AM_HOME"

# Clean up old compile_commands.json if exists
rm -f compile_commands.json
rm -f am/compile_commands.json
rm -f klib/compile_commands.json

# Function to build a component
build_component() {
    local comp_name=$1
    local comp_dir="$AM_HOME/$comp_name"

    if [ ! -d "$comp_dir" ]; then
        echo "Warning: Directory $comp_dir does not exist, skipping."
        return
    fi

    echo "Building $comp_name..."
    cd "$comp_dir"

    # Force clean: Remove build artifacts manually to ensure recompilation.
    # 'make clean' might not always work as expected across different ARCHs or if dependencies are stale.
    rm -rf build *.o *.a .cache

    # Use bear to intercept compilation commands
    # We run 'make archive' to ensure all source files are compiled
    bear -- make archive ARCH=$ARCH || true
    cd "$AM_HOME"
}

# Build am
build_component "am"

# Build klib
build_component "klib"

# Merge compile_commands.json files
echo "Merging compile_commands.json..."

# Check if any compile_commands.json were generated
if [ ! -f "am/compile_commands.json" ] && [ ! -f "klib/compile_commands.json" ]; then
    echo "Error: No compile_commands.json generated in am or klib."
    exit 1
fi

# Use python3 to merge if available, otherwise use jq
if command -v python3 &> /dev/null; then
    python3 -c "
import json
import os

files = []
if os.path.exists('am/compile_commands.json'):
    files.append('am/compile_commands.json')
if os.path.exists('klib/compile_commands.json'):
    files.append('klib/compile_commands.json')

merged = []
for f in files:
    try:
        with open(f, 'r') as fp:
            data = json.load(fp)
            if isinstance(data, list):
                merged.extend(data)
    except Exception as e:
        print(f'Warning: Error reading {f}: {e}')

with open('compile_commands.json', 'w') as out:
    json.dump(merged, out, indent=2)
print(f'Merged {len(merged)} entries into compile_commands.json')
"
elif command -v jq &> /dev/null; then
    # Handle cases where one file might be missing
    if [ -f "am/compile_commands.json" ] && [ -f "klib/compile_commands.json" ]; then
        jq -s '.[0] + .[1]' am/compile_commands.json klib/compile_commands.json > compile_commands.json
    elif [ -f "am/compile_commands.json" ]; then
        cp am/compile_commands.json compile_commands.json
    else
        cp klib/compile_commands.json compile_commands.json
    fi
    echo "Merged compile_commands.json created using jq"
else
    echo "Error: Neither python3 nor jq found. Cannot merge JSON files automatically."
    echo "Please install python3 or jq."
    exit 1
fi

# Clean up subdirectory compile_commands.json files
rm -f am/compile_commands.json klib/compile_commands.json

echo "Done! compile_commands.json has been generated at: $AM_HOME/compile_commands.json"
echo "You can now configure your LSP (e.g., clangd) to use this file."
