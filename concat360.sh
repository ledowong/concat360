#!/usr/bin/env bash
# concat360.sh
# Usage: ./concat360.sh /path/to/360/files /path/to/output
# macOS-friendly (Bash 3.2)

set -euo pipefail
shopt -s nullglob

FILES_DIR="${1:-}"
OUT_DIR="${2:-}"

if [[ -z "${FILES_DIR}" || -z "${OUT_DIR}" ]]; then
  echo "Usage: $0 /path/to/360/files /path/to/output" >&2
  exit 1
fi

if [[ ! -d "$FILES_DIR" ]]; then
  echo "Error: '$FILES_DIR' is not a directory." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Check ffmpeg early
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg not found in PATH." >&2
  exit 1
fi

# Collect candidate files
files=( "$FILES_DIR"/GS*.360 )
if (( ${#files[@]} == 0 )); then
  echo "No .360 files found in: $FILES_DIR"
  exit 0
fi

# Build list of groups (last 4 digits of GS<index><group>.360)
tmp_groups="$(mktemp)"
trap 'rm -f "$tmp_groups"' EXIT

for path in "${files[@]}"; do
  base="$(basename "$path")"     # GS040426.360
  core="${base%.360}"            # GS040426
  digits="${core#GS}"            # 040426
  if [[ "${#digits}" -ge 6 ]]; then
    group="${digits:2:4}"
    echo "$group" >> "$tmp_groups"
  fi
done

# Unique + sorted groups (portable)
groups=()
while IFS= read -r g; do
  groups+=( "$g" )
done < <(sort -u "$tmp_groups")

if (( ${#groups[@]} == 0 )); then
  echo "No valid groups found."
  exit 1
fi

echo "Found groups:"
i=1
for g in "${groups[@]}"; do
  echo "  [$i] $g"
  i=$((i+1))
done

read -r -p "Enter group code (e.g., ${groups[0]}) or number [1-${#groups[@]}]: " choice

selected=""
if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#groups[@]} )); then
  selected="${groups[$((choice-1))]}"
else
  for g in "${groups[@]}"; do
    if [[ "$choice" == "$g" ]]; then
      selected="$g"
      break
    fi
  done
fi

if [[ -z "$selected" ]]; then
  echo "Invalid selection." >&2
  exit 1
fi

# --- Step 1: Create GS<group>.txt in FILES_DIR ---
listfile="$FILES_DIR/GS${selected}.txt"
: > "$listfile"

matches=( "$FILES_DIR"/GS??"$selected".360 )
if (( ${#matches[@]} == 0 )); then
  echo "No files found for group $selected."
  exit 1
fi

for f in $(printf '%s\n' "${matches[@]}" | sort); do
  echo "file '$(basename "$f")'" >> "$listfile"
done

count=$(wc -l < "$listfile" | tr -d '[:space:]')
echo "Created: $listfile ($count entries)"
head -n 1 "$listfile" || true

# --- Step 2: ffmpeg output as MP4 ---
out_mp4="$OUT_DIR/GS${selected}.mp4"
echo "Running ffmpeg to produce: $out_mp4"
ffmpeg -f concat -safe 0 -i "$listfile" -c copy -map 0:0 -map 0:1 -map 0:3 -map 0:5 "$out_mp4"
echo "ffmpeg complete."

# # --- Step 3: udtacopy using reference GS01<group>.360 ---
# src_ref="$FILES_DIR/GS01${selected}.360"
# if [[ -f "$src_ref" && -x "$HOME/udtacopy" ]]; then
#   echo "Running udtacopy..."
#   "$HOME/udtacopy" "$src_ref" "$out_mp4"
#   echo "udtacopy complete."
# else
#   if [[ ! -f "$src_ref" ]]; then
#     echo "Warning: reference file $src_ref not found. Skipping udtacopy." >&2
#   elif [[ ! -x "$HOME/udtacopy" ]]; then
#     echo "Warning: ~/udtacopy not found or not executable. Skipping udtacopy." >&2
#   fi
# fi

# # --- Step 4: Rename MP4 back to .360 ---
# final_360="$OUT_DIR/GS${selected}.360"
# mv -f "$out_mp4" "$final_360"
# echo "Renamed output to: $final_360"

echo "Done."