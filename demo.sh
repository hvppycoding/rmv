#!/bin/bash
# Demonstrate what rmv protects against, by running each failure for real.
#
# Every case builds a throwaway directory under $TMPDIR, deletes files in it
# with a naive wrapper and then with rmv, and reports whether the files that
# actually disappeared are the files that were shown. Nothing outside the
# sandbox is touched.
#
#   ./demo.sh            use ./rmv next to this script
#   ./demo.sh ~/bin/rmv  use rmv from somewhere else

set -u

here=$(cd -- "$(dirname -- "$0")" && pwd)
RMV=${1:-$here/rmv}

if [ ! -x "$RMV" ]; then
    echo "demo: cannot execute $RMV" >&2
    exit 1
fi

root=$(mktemp -d "${TMPDIR:-/tmp}/rmv-demo.XXXXXX") || exit 1
trap 'rm -rf "$root"' EXIT

pass=0
fail=0

# A faithful reproduction of the wrapper everyone writes: join the arguments
# into a string, show it with ls, then delete it with rm. Both go through a
# shell, which is where it goes wrong.
naive() {
    local args="$*"
    /bin/sh -c "ls -d $args" >/dev/null 2>&1
    /bin/sh -c "rm -rf $args" >/dev/null 2>&1
}

# rmv in preview mode. stdin is a pipe, not a terminal, so rmv deletes without
# asking; the y is for the eight-line version in the README, which always asks.
confirm() {
    printf 'y\n' | "$RMV" -rfp "$@" >/dev/null 2>&1
}

listing() {
    ( cd "$1" && ls -A | sort | tr '\n' ' ' )
}

# case <name> <expected surviving files> -- runs the body in a fresh sandbox
check() {
    local label=$1 expected=$2 got=$3
    if [ "$got" = "$expected" ]; then
        printf '    \033[32mok\033[0m    %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '    \033[31mFAIL\033[0m  %s\n' "$label"
        printf '          expected left over: %s\n' "$expected"
        printf '          actually left over: %s\n' "$got"
        fail=$((fail + 1))
    fi
}

newdir() {
    local d=$root/$1
    rm -rf "$d"
    mkdir -p "$d"
    printf '%s' "$d"
}

echo
echo "=============================================================="
echo " 1. A file name containing glob characters"
echo "=============================================================="
echo
echo "  Deleting the single file 'report[1].txt'. A sibling named"
echo "  report1.txt must not be touched."
echo

d=$(newdir glob-naive); ( cd "$d" && touch 'report[1].txt' report1.txt )
( cd "$d" && naive 'report[1].txt' )
echo "  naive:  left over -> $(listing "$d")"
check "naive keeps report1.txt" "report1.txt " "$(listing "$d")"

d=$(newdir glob-rmv); ( cd "$d" && touch 'report[1].txt' report1.txt )
( cd "$d" && confirm 'report[1].txt' )
echo "  rmv:    left over -> $(listing "$d")"
check "rmv keeps report1.txt" "report1.txt " "$(listing "$d")"

echo
echo "=============================================================="
echo " 2. A file name containing a space"
echo "=============================================================="
echo
echo "  Deleting 'my file.txt'. A file named 'my' must survive."
echo

d=$(newdir space-naive); ( cd "$d" && touch 'my file.txt' my )
( cd "$d" && naive 'my file.txt' )
echo "  naive:  left over -> $(listing "$d")"
check "naive keeps my" "my " "$(listing "$d")"

d=$(newdir space-rmv); ( cd "$d" && touch 'my file.txt' my )
( cd "$d" && confirm 'my file.txt' )
echo "  rmv:    left over -> $(listing "$d")"
check "rmv keeps my" "my " "$(listing "$d")"

echo
echo "=============================================================="
echo " 3. A pattern reaching the command string, and a file created"
echo "    while you are reading the listing"
echo "=============================================================="
echo
echo "  This is what happens when the pattern itself is passed along --"
echo "  a quoted argument, or typing 'ls *.log' and then 'rm *.log' by"
echo "  hand. The pattern is expanded twice, once for each command."
echo

d=$(newdir race-naive); ( cd "$d" && touch old1.log old2.log )
(
    cd "$d"
    /bin/sh -c 'ls -d *.log' >/dev/null 2>&1     # you review this
    : > NEW-while-you-read.log                   # a job writes here
    /bin/sh -c 'rm -rf *.log' >/dev/null 2>&1    # expanded a second time
)
echo "  naive:  left over -> $(listing "$d")"
check "naive keeps the new file" "NEW-while-you-read.log " "$(listing "$d")"

d=$(newdir race-rmv); ( cd "$d" && touch old1.log old2.log )
(
    cd "$d"
    set -- *.log                                 # the shell expands once
    : > NEW-while-you-read.log
    confirm "$@"                                 # that same list is deleted
)
echo "  rmv:    left over -> $(listing "$d")"
check "rmv keeps the new file" "NEW-while-you-read.log " "$(listing "$d")"

echo
echo "=============================================================="
echo " 4. A file name containing shell metacharacters"
echo "=============================================================="
echo
echo "  Deleting 'x;touch INJECTED.txt'. No new file may appear."
echo

d=$(newdir inject-naive); ( cd "$d" && touch 'x;touch INJECTED.txt' )
( cd "$d" && naive 'x;touch INJECTED.txt' )
echo "  naive:  left over -> $(listing "$d")"
check "naive runs no extra command" "" "$(listing "$d")"

d=$(newdir inject-rmv); ( cd "$d" && touch 'x;touch INJECTED.txt' )
( cd "$d" && confirm 'x;touch INJECTED.txt' )
echo "  rmv:    left over -> $(listing "$d")"
check "rmv runs no extra command" "" "$(listing "$d")"

echo
echo "=============================================================="
echo " 5. A file whose name starts with a dash"
echo "=============================================================="
echo
echo "  A directory holds a file named -r and a directory mydir."
echo "  Deleting * must not recurse into mydir: nobody asked for -r"
echo "  to mean recursive. argv cannot tell the two apart, so the"
echo "  only safe move is to stop."
echo

naive_dash() {
    local opts=() args=() a
    for a in "$@"; do
        case $a in -*) opts+=("$a") ;; *) args+=("$a") ;; esac
    done
    /bin/ls -d "${args[@]}" >/dev/null 2>&1
    /bin/rm ${opts[@]+"${opts[@]}"} "${args[@]}" >/dev/null 2>&1
}

d=$(newdir dash-naive); ( cd "$d" && mkdir mydir && touch -- -r mydir/keep1 mydir/keep2 )
( cd "$d" && naive_dash * )
echo "  naive:  left over -> $(listing "$d")"
check "naive does not recurse into mydir" "-r mydir " "$(listing "$d")"

d=$(newdir dash-rmv); ( cd "$d" && mkdir mydir && touch -- -r mydir/keep1 mydir/keep2 )
( cd "$d" && confirm * )
echo "  rmv:    left over -> $(listing "$d")"
check "rmv does not recurse into mydir" "-r mydir " "$(listing "$d")"

echo
echo "=============================================================="
echo " 6. The ordinary case: argv already expanded, plain names"
echo "=============================================================="
echo
echo "  Both are correct here. This is most deletes, and it is why the"
echo "  naive wrapper feels fine for a long time."
echo

d=$(newdir plain-naive); ( cd "$d" && touch a.log b.log keep.txt )
( cd "$d" && naive a.log b.log )
echo "  naive:  left over -> $(listing "$d")"
check "naive deletes exactly the logs" "keep.txt " "$(listing "$d")"

d=$(newdir plain-rmv); ( cd "$d" && touch a.log b.log keep.txt )
( cd "$d" && confirm a.log b.log )
echo "  rmv:    left over -> $(listing "$d")"
check "rmv deletes exactly the logs" "keep.txt " "$(listing "$d")"

echo
echo "--------------------------------------------------------------"
printf ' %d ok, %d failed\n' "$pass" "$fail"
echo
echo " The failures above are the naive wrapper doing what it does."
echo " Every rmv line should read ok."
echo "--------------------------------------------------------------"
echo
