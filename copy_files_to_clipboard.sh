#!/bin/bash

# ==============================================================================
# copy_files_to_clipboard.sh
#
# Copies the text content of all regular files (excluding this script itself)
# found in the directory where the script is run, into the system clipboard.
# Attempts to auto-detect the appropriate clipboard utility.
#
# Usage:
# 1. Place this script in the directory whose files you want to copy.
# 2. Open a terminal (Bash, Zsh, WSL, Git Bash) in that directory.
# 3. Make the script executable: chmod +x copy_files_to_clipboard.sh
# 4. Run the script: ./copy_files_to_clipboard.sh
# 5. Paste the content (Ctrl+V / Cmd+V) elsewhere.
# ==============================================================================

# --- Configuration ---
# The directory to process is the current working directory
SCRIPT_DIR="."

# --- Get the name of this script file to exclude it ---
# Handles cases where the script might be called via a symlink or different path
# by resolving the real path first, then getting the basename.
REAL_SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")
SCRIPT_NAME=$(basename "$REAL_SCRIPT_PATH")


# --- Determine Clipboard Command ---
CLIPBOARD_CMD=""
# Check in order: macOS, Wayland, X11, Windows (WSL/Cygwin/Git Bash)
if command -v pbcopy &> /dev/null; then
    CLIPBOARD_CMD="pbcopy"
    CLIPBOARD_CMD_NAME="pbcopy (macOS)"
elif command -v wl-copy &> /dev/null; then
    CLIPBOARD_CMD="wl-copy"
    CLIPBOARD_CMD_NAME="wl-copy (Wayland)"
elif command -v xclip &> /dev/null; then
    # Check if DISPLAY is set for X11 environments
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then # Check both just in case
        CLIPBOARD_CMD="xclip -selection clipboard -in" # Use -in for piping
        CLIPBOARD_CMD_NAME="xclip (X11)"
    else
        echo "Warning: xclip found, but no active graphical display (\$DISPLAY or \$WAYLAND_DISPLAY) detected." >&2
        # Fall through to check clip.exe or fail
    fi
elif command -v clip.exe &> /dev/null; then
    # Check if we might be in WSL or similar where clip.exe needs Unix line endings converted
    if [[ "$(uname -r)" == *Microsoft* || "$(uname -o)" == "Cygwin" || "$(uname -o)" == "Msys" ]]; then
         CLIPBOARD_CMD="unix2dos | clip.exe" # Convert LF to CRLF for Windows clipboard
         CLIPBOARD_CMD_NAME="clip.exe (Windows/WSL/Git Bash)"
         # Check if unix2dos is available
         if ! command -v unix2dos &> /dev/null; then
             echo "Warning: 'unix2dos' not found. Line endings might be incorrect in Windows clipboard." >&2
             echo "         Consider installing 'dos2unix' package (which includes unix2dos)." >&2
             CLIPBOARD_CMD="clip.exe" # Fallback to direct pipe
         fi
    else
        CLIPBOARD_CMD="clip.exe" # Unlikely, but handle direct availability
        CLIPBOARD_CMD_NAME="clip.exe (Windows?)"
    fi
fi

# --- Check if a clipboard command was found ---
if [ -z "$CLIPBOARD_CMD" ]; then
    echo "--------------------------------------------------------------------" >&2
    echo " Error: No suitable clipboard command found or environment detected." >&2
    echo " Please ensure one of the following is installed and accessible:" >&2
    echo "   - macOS: 'pbcopy' (should be built-in)." >&2
    echo "   - Linux (Wayland): 'wl-clipboard' package (provides wl-copy)." >&2
    echo "   - Linux (X11): 'xclip' package (and ensure \$DISPLAY is set)." >&2
    echo "   - Windows (WSL/Cygwin/Git Bash): 'clip.exe' (should be available)." >&2
    echo "--------------------------------------------------------------------" >&2
    exit 1
fi

echo "--- Clipboard Script Started ---"
echo "Using clipboard command: $CLIPBOARD_CMD_NAME"
echo "Processing files in directory: $(pwd)"
echo "Excluding script file: $SCRIPT_NAME"
echo "--------------------------------"

# --- Find files, concatenate content, and pipe to clipboard ---

# Create a secure temporary file to store concatenated content
TEMP_CONTENT_FILE=$(mktemp)
# Ensure temp file is removed reliably on exit, interrupt (Ctrl+C), or termination
trap 'rm -f "$TEMP_CONTENT_FILE"' EXIT SIGINT SIGTERM

echo "Gathering content from files:"
FILE_COUNT=0
TOTAL_BYTES=0

# Use find to locate files and append their content. Print names as we go.
# -maxdepth 1: Only search in the current directory (SCRIPT_DIR)
# -type f:     Only find regular files (includes .sh, .cs, .js, .txt, etc.)
# ! -name SCRIPT_NAME: Exclude this script file itself
# -print:      Show the filename being processed
# -exec cat {} >> "$TEMP_CONTENT_FILE" \; : Append file content safely to temp file
# Note: Using '; >>' appends output of each 'cat' individually. Safe for various filenames.
while IFS= read -r -d $'\0' file; do
    if [ -r "$file" ]; then # Check if file is readable
        echo " - $(basename "$file")"
        cat "$file" >> "$TEMP_CONTENT_FILE"
        # Check if cat succeeded before counting
        if [ $? -eq 0 ]; then
           ((FILE_COUNT++))
        else
           echo "   Warning: Could not read content from '$file'." >&2
        fi
    else
        echo " - $(basename "$file") (Skipped: Not readable)" >&2
    fi
done < <(find "$SCRIPT_DIR" -maxdepth 1 -type f ! -name "$SCRIPT_NAME" -print0)
# Using -print0 and read -d $'\0' is the safest way to handle filenames with spaces/newlines

echo "--------------------------------"

# Check if any files were found and content was gathered
if [ "$FILE_COUNT" -eq 0 ]; then
  # Check if find *would* have found files, even if empty/unreadable/excluded
  if find "$SCRIPT_DIR" -maxdepth 1 -type f ! -name "$SCRIPT_NAME" -print -quit | grep -q .; then
     echo "Warning: Found potential files, but none were readable or contained content." >&2
  else
     echo "No other regular files found in this directory to copy."
  fi
  echo "--- Clipboard Script Finished (No content copied) ---"
  exit 0 # Exit gracefully, nothing to copy
fi

# Get total size from the temp file
TOTAL_BYTES=$(wc -c < "$TEMP_CONTENT_FILE")

echo "Attempting to copy ${TOTAL_BYTES} bytes from ${FILE_COUNT} file(s) to clipboard..."

# Now copy the content from the temp file to the clipboard
# Use eval carefully ONLY because $CLIPBOARD_CMD might contain pipes/redirections (like for unix2dos)
# We've constructed CLIPBOARD_CMD from trusted components.
# Pipe the content using cat.
cat "$TEMP_CONTENT_FILE" | eval "$CLIPBOARD_CMD"
STATUS=$?

# --- Check Final Status ---
if [ $STATUS -eq 0 ]; then
    echo "Success! Content copied to clipboard."
    echo "--- Clipboard Script Finished ---"
else
    echo "--------------------------------------------------------------------" >&2
    echo "Error: Failed to copy content to clipboard (Exit status: $STATUS)." >&2
    echo "       Check the output/warnings above." >&2
    echo "--------------------------------------------------------------------" >&2
    echo "--- Clipboard Script Finished (with errors) ---"
    exit 1 # Exit with error
fi

exit 0 # Explicitly exit with success