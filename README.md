# rmv

`rm` that shows you the list first — and deletes **exactly** the list it showed.

```
$ rm *.log
app.log
debug.log
error.log

rmv: about to delete 3 items. Type the count to proceed (Enter cancels) >
```

## Why not just script `ls` then `rm`?

Everyone eventually writes some version of this:

```python
arg = " ".join(sys.argv[1:])
os.system(f"ls {arg}")       # look at what is about to go
input("ok? ")                # confirm
os.system(f"rm {arg}")       # delete
```

Most of the time this is fine. Your shell already expanded `*.log` into argv
before the script started, so joining argv back together and handing it to `ls`
and then `rm` names the same files both times.

The problem is that the joined string is handed to **a shell**, twice, and a
shell re-parses whatever it is given. The listing and the delete can then
disagree — which is the one thing the wrapper exists to prevent.

**A file name containing a glob character is expanded again:**

```
argv:     ['report[1].txt']          # the file you asked to delete
shell:    rm report[1].txt           # [1] is a character class, not a name
deleted:  report1.txt                # a file that was never on screen
left:     report[1].txt              # the file you did ask for
```

**A file name containing a space is split into two:**

```
argv:     ['my file.txt']
shell:    rm my file.txt             # two operands now
deleted:  my  and  file.txt          # if a file named `my` exists, it is gone
```

**And if a pattern rather than argv reaches the string** — a quoted argument, or
a tool that takes the pattern itself — it really is expanded twice, so anything
created between the review and the confirmation is deleted unseen:

```
reviewed: old1.log, old2.log
          # a job writes IMPORTANT-result.log while you are reading
deleted:  old1.log, old2.log, IMPORTANT-result.log
```

`rmv` never builds a command string. The shell expands once into argv, that
array is frozen, displayed, and passed to `rm` as the same array. No shell sees
it, so `weird;$(whoami).txt` is just a file name, and what you reviewed is what
gets deleted.

## Why a count instead of `y/n`?

Because `y/n` stops being read. `rm -i` was the original answer to this and it is
now the single most aliased-away flag in Unix, for exactly that reason — a prompt
you answer reflexively is not a prompt.

Typing the number of targets cannot be answered without looking at the list.

## Install

```sh
mkdir -p ~/bin && cp rmv ~/bin/ && chmod +x ~/bin/rmv
```

Then alias `rm` to it:

```csh
# tcsh — ~/.cshrc
alias rm '~/bin/rmv'
```

```sh
# bash / zsh — ~/.bashrc or ~/.zshrc
alias rm='~/bin/rmv'
```

Aliases do not apply inside scripts, so existing scripts keep getting the real
`/bin/rm`. If you land on a machine without your dotfiles you get a plain `rm` —
you lose the net, nothing breaks.

## Usage

```
Usage: rmv [OPTION]... FILE...

Options:
  -r, -R, --recursive   remove directories and their contents
  -f, --force           ignore nonexistent files, never report an error
  -h, --help            show this help
  --                    treat every later argument as a file name

  Any other option is passed through to /bin/rm unchanged.
```

Listing is done by `/bin/ls -dF --color`, so it looks like the `ls` you already
read. `-d` keeps directories from being expanded into their contents.

`ls -d` prints a directory as one line, which badly understates what
`rm -rf build` is about to do, so recursive targets are sized separately:

```
$ rm -rf build dist config.link
build/
config.link@
dist/
  build holds 4 entries
  dist holds 3 entries

rmv: about to delete 3 items. Type the count to proceed (Enter cancels) > 3
```

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `RMV_QUIET_THRESHOLD` | `0` | Let deletes of this many plain files through without a prompt. `0` always confirms. |

With `RMV_QUIET_THRESHOLD=3`, `rm a b c` goes straight through, while globs,
directories and anything recursive still confirm. Useful if the prompt starts to
feel like noise — lowering how often it fires keeps it sharp, whereas weakening
the prompt itself does not.

## Compared to

| | shows the list | one prompt | list == what is deleted |
|---|---|---|---|
| `rm -i` | no | no, one per file | n/a |
| `rm -I` | no, count only | yes | n/a |
| `ls` + `rm` script | yes | yes | **not always** — the string is re-parsed by a shell twice |
| trash / `rip` | no | no | n/a, recoverable after the fact |
| `rmv` | yes | yes | yes |

Trash-style tools solve a different failure: deleting something you were right
about matching but wrong about wanting. They are worth having alongside this,
not instead of it — a preview cannot save you from a delete you would have
confirmed anyway, and a trash can cannot tell you that your glob was wrong while
there is still time to fix it.

## See it for yourself

`demo.sh` builds a throwaway directory under `$TMPDIR` and runs each of the
failures above for real, first with a naive wrapper and then with `rmv`, then
reports what actually survived. Nothing outside the sandbox is touched.

```
$ ./demo.sh
...
 1. A file name containing glob characters
  naive:  left over -> report[1].txt
    FAIL  naive keeps report1.txt
  rmv:    left over -> report1.txt
    ok    rmv keeps report1.txt
...
 5. The ordinary case: argv already expanded, plain names
    ok    naive deletes exactly the logs
    ok    rmv deletes exactly the logs

 6 ok, 4 failed
```

Case 5 is there on purpose: with argv already expanded and plain file names,
the naive wrapper is correct, which is why it feels fine for a long time.

## The eight-line version

Being correct here is not the expensive part. The whole difference is passing
the targets as an array rather than joining them into a string for a shell, and
the array is the shorter spelling:

```bash
#!/bin/bash
opts=(); while [[ ${1-} == -?* ]]; do opts+=("$1"); shift; done
[ $# -eq 0 ] && exit 1
/bin/ls -dF --color=always -- "$@"
printf 'delete %d items? type the count > ' "$#"
read -r a
[ "$a" = "$#" ] || { echo cancelled >&2; exit 1; }
exec /bin/rm "${opts[@]}" -- "$@"
```

That passes every case in `demo.sh`, exactly like the full script:

```
$ ./demo.sh /tmp/rmv-min
    ok    rmv keeps report1.txt
    ok    rmv keeps my
    ok    rmv keeps the new file
    ok    rmv runs no extra command
    ok    rmv deletes exactly the logs
```

Everything `rmv` has beyond those eight lines is comfort, not safety: option
parsing that keeps `-r` and `-f` behaving like they do in `rm`, entry counts so
`rm -rf build` shows its size, `--help`, `RMV_QUIET_THRESHOLD`, and a colour
flag that works on both GNU and BSD. Take the eight lines if you would rather
not carry the rest.

## Requirements

`bash` 3.2+, `/bin/ls`, `/bin/rm`. Tested on RHEL 8 (GNU coreutils) and macOS
(BSD); the colour flag is detected at runtime, `--color=always` on GNU and `-G`
on BSD.

## License

MIT
