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

```sh
ls $pattern          # look at what is about to go
read -p "ok? " ans   # confirm
rm $pattern          # delete
```

It has a hole, and the hole is in the one thing the wrapper exists to guarantee.
**The pattern is expanded twice.** Once by `ls`, once again by `rm`. Anything
created in between is deleted without ever having been on screen:

```
reviewed:  ['old1.log', 'old2.log']
           # a job writes IMPORTANT-result.log while you are reading
deleted:   old1.log, old2.log, IMPORTANT-result.log
```

On a shared box with jobs writing into the same directory, that is not a thought
experiment. `rmv` expands once — the shell hands it a concrete argv, that array
is frozen, displayed, and passed to `rm` unchanged. What you reviewed is what
gets deleted.

The same property removes the other problem with the naive version: no shell is
involved in the delete, so a file named `weird;$(whoami).txt` is just a file
name.

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
| `ls` + `rm` script | yes | yes | **no**, expanded twice |
| trash / `rip` | no | no | n/a, recoverable after the fact |
| `rmv` | yes | yes | yes |

Trash-style tools solve a different failure: deleting something you were right
about matching but wrong about wanting. They are worth having alongside this,
not instead of it — a preview cannot save you from a delete you would have
confirmed anyway, and a trash can cannot tell you that your glob was wrong while
there is still time to fix it.

## Requirements

`bash` 3.2+, `/bin/ls`, `/bin/rm`. Tested on RHEL 8 (GNU coreutils) and macOS
(BSD); the colour flag is detected at runtime, `--color=always` on GNU and `-G`
on BSD.

## License

MIT
