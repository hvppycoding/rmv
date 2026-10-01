# rmv

`rm` that shows you the list first — and deletes **exactly** the list it showed.

```
$ rm *.log
app.log
debug.log
error.log

rmv: delete 3 items? [y/N] >
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

It is tempting to think this cannot reach outside the arguments you passed —
argv is already a list of real files, so how could anything else be involved?
It can, because joining that list turns a name back into a live pattern, and a
live pattern picks up whatever is in the directory, including files that arrive
while you are reading:

```
argv:     ['tmp*']                   # one file, whose name contains a star
shell:    ls -d tmp*                 # shown: tmp*  tmpA.log  tmpB.log
          # a job writes tmpC.log while you are reading
shell:    rm -f tmp*                 # deleted: all four
```

One file was named, four were deleted, and one of those four had never been on
screen.

**A file name starting with a dash is read as a flag.** This one does not need
a shell at all — it catches any wrapper that sorts argv into options and targets,
which is every wrapper:

```
directory:  -r  mydir/          # mydir holds files you want to keep
argv:       ['-r', 'mydir']     # from rm *
sorted as:  options ['-r'], targets ['mydir']
shown:      mydir               # the file -r is not in the listing
deleted:    mydir and everything under it
```

Nobody asked for recursion. A file that happens to be named `-r` turned it on,
and removed itself from the listing on the way past. Without that file, `rm
mydir` would have failed with "is a directory" and you would have noticed.

`rmv` stops when an argument that looks like an option is also a file that
exists, rather than guessing:

```
$ rmv *
rmv: '-r' is both an option and a file that exists here
rmv: refusing to guess. To delete them:  rmv -- <file>...
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

### How likely is any of this?

Not very. Ordinary file names with no spaces and no glob characters go through
the naive wrapper correctly, which is most deletes and why it survives in
everyone's dotfiles for years. Spaces show up often enough, but they usually
fail loudly — `rm my file.txt` reports two missing files and deletes nothing,
unless a file named `my` happens to exist. The silent, destructive versions need
a file name that contains a glob character, which is rare.

The reason to care anyway is that avoiding all of it is free. Passing an array
is not more code than joining a string — it is one line less. Whatever you think
of the odds, there is nothing to trade away:

```python
subprocess.run(["ls", "-dF", "--color=always", *targets])   # instead of
subprocess.run(["rm", "-rf", *targets])                     # shell=True on an f-string
```

Escaping the arguments for the second shell works too, and is the right fix if
you want to keep building a command string — `shlex.quote` in Python, `printf
%q` in bash. Note that escaping for the first shell does not do it: typing
`del 'tmp*'` protects the name from the shell you typed into, not from the one
the wrapper starts afterwards.

```python
arg = " ".join(shlex.quote(t) for t in targets)   # correct, has to be remembered
subprocess.run(f"rm -rf {arg}", shell=True)
```

Both are fine. The array is one line shorter and there is nothing to forget.

## Why a flag?

Without `-p` this is `rm`. The preview and the prompt only appear when the flag
is there, which keeps the same file usable from scripts and safe to put on
`PATH`.

You are not meant to type it. Put it in the alias, so interactive deletes always
preview and nothing else changes:

```csh
alias rm '~/bin/rmv -p'
```

## Install

```sh
mkdir -p ~/bin && cp rmv ~/bin/ && chmod +x ~/bin/rmv
```

Then alias `rm` to it:

```csh
# tcsh — ~/.cshrc
alias rm '~/bin/rmv -p'
```

```sh
# bash / zsh — ~/.bashrc or ~/.zshrc
alias rm='~/bin/rmv -p'
```

Aliases do not apply inside scripts, so existing scripts keep getting the real
`/bin/rm`. If you land on a machine without your dotfiles you get a plain `rm` —
you lose the net, nothing breaks.

### Agents and pipes

Coding agents (Claude Code, Codex, Farad, ...) usually source the same rc file, so
they get the alias too, but nobody is there to answer the prompt. A stdin that
never closes would hang the command, and an agent running on a pty would stall
on `/dev/tty`. So `-p` only asks when stdin is a terminal and none of
`CLAUDECODE`, `AI_AGENT`, `FARAD_AGENT` or `CODEX_SANDBOX` is set. Otherwise it
deletes the same frozen list without asking, like `rm`.

## Usage

```
Usage: rmv [OPTION]... FILE...

Options:
  -p, --preview         show the targets and confirm before deleting
  -r, -R, --recursive   remove directories and their contents
  -f, --force           ignore nonexistent files, never report an error
  -h, --help            show this help
  --                    treat every later argument as a file name

  Any other option is passed through to /bin/rm unchanged.
```

`-p` clusters like any other short flag, so `rmv -rfp build` works and only
`-rf` reaches `/bin/rm`.

Listing is done by `/bin/ls -dF --color`, so it looks like the `ls` you already
read. `-d` keeps directories from being expanded into their contents.

`-F` marks what each target is, so a directory and a symlink are visible as
such without opening either:

```
$ rm -rf build dist config.link
build/
config.link@
dist/

rmv: delete 3 items? [y/N] > y
```

A directory is one line, which does understate what `rm -rf build` is about to
do. Counting what is underneath would mean walking the tree on every prompt,
which over NFS is a round trip per directory, so the listing stays at what the
targets are rather than how big they are.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `RMV_QUIET_THRESHOLD` | `0` | In preview mode, let deletes of this many plain files through without a prompt. `0` always confirms. |

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
 6. The ordinary case: argv already expanded, plain names
    ok    naive deletes exactly the logs
    ok    rmv deletes exactly the logs

 7 ok, 5 failed
```

The last case is there on purpose: with argv already expanded and plain file names,
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
printf 'delete %d items? [y/N] > ' "$#"
read -r a
[ "$a" = y ] || { echo cancelled >&2; exit 1; }
exec /bin/rm "${opts[@]}" -- "$@"
```

That passes every case in `demo.sh`, exactly like the full script:

```
$ ./demo.sh /tmp/rmv-min
    ok    rmv keeps report1.txt
    ok    rmv keeps my
    ok    rmv keeps the new file
    ok    rmv runs no extra command
    ok    rmv does not recurse into mydir
    ok    rmv deletes exactly the logs
```

Everything `rmv` has beyond those eight lines is comfort, not safety: option
parsing that keeps `-r` and `-f` behaving like they do in `rm`, the `-p` gate,
the guard for a file named like an option, `--help`, `RMV_QUIET_THRESHOLD`, and
a colour flag that works on both GNU and BSD. Take the eight lines if you would rather
not carry the rest.

## Requirements

`bash` 3.2+, `/bin/ls`, `/bin/rm`. Tested on RHEL 8 (GNU coreutils) and macOS
(BSD); the colour flag is detected at runtime, `--color=always` on GNU and `-G`
on BSD.

## License

MIT
