#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
compiler="${CXX:-g++}"
if ! command -v "$compiler" >/dev/null; then
    echo "A C++17 compiler is required (set CXX to its executable)." >&2
    exit 1
fi
mkdir -p build/tests
shopt -s nullglob
sources=(tests/*_tests.cpp)
if ((${#sources[@]} == 0)); then
    echo "No native test sources found." >&2
    exit 1
fi
for source in "${sources[@]}"; do
    executable="build/tests/$(basename "$source" .cpp)"
    "$compiler" -std=c++17 -Wall -Wextra -Werror -pedantic "$source" -o "$executable"
    "$executable"
done
