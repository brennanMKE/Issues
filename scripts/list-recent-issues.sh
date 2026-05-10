#!/usr/bin/env zsh
# List recently updated issues sorted by file mtime, newest first.
#
# Each line is: number, status, title — three columns separated by two
# spaces, suitable for piping into grep/awk.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0##*/}"
REPO_ROOT="${SCRIPT_DIR:h}"
ISSUES_DIR="$REPO_ROOT/project-issues"

LIMIT=20

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-n LIMIT] [-h]

List recently updated issues from $ISSUES_DIR, sorted by mtime (newest first).
Columns: number  status  title.

Options:
  -n LIMIT  Show at most LIMIT issues (default: 20). Use 0 for no limit.
  -h        Show this help.
EOF
}

while getopts "n:h" opt; do
    case "$opt" in
        n) LIMIT="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

if [[ ! -d "$ISSUES_DIR" ]]; then
    print -u2 "error: $ISSUES_DIR not found"
    exit 1
fi

# zsh glob qualifiers:
#   N   null-glob (don't error if no match)
#   .   regular files only
#   om  order by mtime, newest first
typeset -a files
files=("$ISSUES_DIR"/[0-9][0-9][0-9][0-9].md(N.om))

if (( ${#files} == 0 )); then
    print -u2 "no issue files in $ISSUES_DIR"
    exit 0
fi

if (( LIMIT > 0 )) && (( ${#files} > LIMIT )); then
    files=("${files[@]:0:$LIMIT}")
fi

for f in $files; do
    id="${${f:t}:r}"

    # `status` is a read-only built-in in zsh ($? alias), so use `state`.
    state=$(awk -F'\\|' '
        /^\| \*\*Status\*\* \|/ {
            gsub(/^[ \t]+|[ \t]+$/, "", $3)
            print $3
            exit
        }
    ' "$f")
    [[ -z "$state" ]] && state="?"

    # Title line: "# NNNN — Title". Strip the prefix (em-dash is U+2014).
    title=$(awk 'NR==1 {
        sub(/^# +[0-9]+ +— +/, "")
        print
        exit
    }' "$f")
    [[ -z "$title" ]] && title="(no title)"

    printf "%s  %-12s  %s\n" "$id" "$state" "$title"
done
