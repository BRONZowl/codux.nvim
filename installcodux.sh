#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$REPO_DIR/bin/codux"
TARGET_DIR="$HOME/.local/bin"
TARGET="$TARGET_DIR/codux"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
FISH_PATH_LINE='fish_add_path -g "$HOME/.local/bin"'

if [ ! -f "$SOURCE" ]; then
  echo "codux install: expected launcher at $SOURCE" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
cp "$SOURCE" "$TARGET"
chmod +x "$TARGET"

append_once() {
  local file="$1"
  local line="$2"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Fq ".local/bin" "$file"; then
    return 1
  fi

  {
    printf "\n"
    printf "# codux.nvim\n"
    printf "%s\n" "$line"
  } >> "$file"

  return 0
}

updated_files=()

rc_files=(
  "$HOME/.bashrc"
  "$HOME/.zshrc"
  "$HOME/.profile"
  "$HOME/.bash_profile"
)

for rc_file in "${rc_files[@]}"; do
  if append_once "$rc_file" "$PATH_LINE"; then
    updated_files+=("$rc_file")
  fi
done

if [ -d "$HOME/.config/fish" ]; then
  if append_once "$HOME/.config/fish/config.fish" "$FISH_PATH_LINE"; then
    updated_files+=("$HOME/.config/fish/config.fish")
  fi
fi

echo "codux install: installed launcher to $TARGET"

if [ "${#updated_files[@]}" -gt 0 ]; then
  echo "codux install: updated shell startup files:"
  for file in "${updated_files[@]}"; do
    echo "  - $file"
  done
  echo "codux install: restart your shell or source your rc file before running codux."
else
  echo "codux install: no shell startup files needed updates."
fi
