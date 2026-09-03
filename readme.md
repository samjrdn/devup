# devup

Set up a development machine: shell, git, editor, and the command line tools
that go with them. Clone, run one script, done.

Works on macOS and Debian-based Linux, on a laptop or a remote server.

## Get started

On a brand new machine, with nothing installed — not even git:

```shell
curl -fsSL https://raw.githubusercontent.com/samjrdn/devup/main/bootstrap.sh | sh
```

That installs git if it is missing, fetches this repo to
`~/src/github.com/samjrdn/devup`, and runs `setup.sh`. To add GUI applications
as well, pass options through after `--`:

```shell
curl -fsSL https://raw.githubusercontent.com/samjrdn/devup/main/bootstrap.sh | sh -s -- --full
```

Running `./bootstrap.sh` from a checkout you already have uses *that*
checkout, wherever it lives, and does not fetch a second copy or pull over
your local changes. Set `DEVUP_DIR` to clone somewhere else. If you would rather read the script
before running it — a reasonable habit for anything piped into a shell — or
you already have git:

```shell
git clone https://github.com/samjrdn/devup.git ~/src/github.com/samjrdn/devup
~/src/github.com/samjrdn/devup/setup.sh
```

The repo is public so cloning needs no credentials, which is the point: a
brand new machine can bootstrap itself before it has any keys. Nothing secret
is stored here — see [Secrets](#secrets).

## Running it again

`setup.sh` is idempotent. Every step checks the current state first and
changes only what is not already correct, so re-running after adding a package
or a config file applies just that change. Run it as often as you like.

```shell
./setup.sh                 # command line tools and preferences
./setup.sh --full          # the above, plus GUI applications
./setup.sh --ssh           # add an SSH key for private repos
./setup.sh --dry-run       # show what would change, change nothing
./setup.sh --no-packages   # only link config files
./setup.sh --only-packages # only install packages
./setup.sh --help
```

The default run installs nothing graphical, so it is safe on a headless box.
GUI applications are opt-in via `--full`.

## What it does

**Works without git.** [`bootstrap.sh`](bootstrap.sh) installs git via apt
where it can. Where it cannot — macOS, where git means the Xcode command line
tools and a GUI prompt — it downloads a source tarball instead, then converts
the directory into a real git checkout once `setup.sh` has installed git, so
it stays updatable.

**Installs packages.** On macOS from [`packages/Brewfile`](packages/Brewfile)
via `brew bundle`, installing Homebrew first if it is missing. On Debian from
[`packages/apt.txt`](packages/apt.txt), installing only what is actually
missing. `--full` additionally installs
[`Brewfile.full`](packages/Brewfile.full) / [`apt.full.txt`](packages/apt.full.txt),
which is where GUI applications go.

On macOS a `Brewfile.<arch>` is layered on top, so an Intel Mac and an Apple
Silicon Mac can install different sets. See [Intel Macs](#intel-macs).

**Installs mise.** [mise](https://mise.jdx.dev) manages ruby, python and node.
Which versions is deliberately left to you, in `~/.config/mise/config.toml` —
that file is per-machine and this repo does not overwrite it. `setup.sh` runs
`mise install` so whatever it names gets built.

**Links config files.** Every file named `*.sym*` is symlinked into `$HOME`
with the `.sym` removed, so `shell/zsh/.zprofile.sym` becomes `~/.zprofile`.
Anything already at one of those paths is moved into
`~/.devup-backup/<timestamp>/` first.

**Keeps what the machine already had.** An existing `~/.zshrc` or
`~/.bash_profile` is carried into `~/.shellrc.local`, and an existing git
identity into `~/.gitconfig.local`, so running this over a working machine
does not break it.

The checkout can live anywhere and under any name — the shell config finds the
repo by following its own symlink.

## Machine-specific configuration

These live outside the repo and are never committed. `setup.sh` creates them
on first run and leaves them alone afterwards.

| File | For |
| --- | --- |
| `~/.gitconfig.local` | Git identity and signing key |
| `~/.shellrc.local` | Shell config for this machine only |
| `~/.config/devup/env.d/*.env` | Environment variables and credentials |

## Secrets

API keys and tokens go in `~/.config/devup/env.d/`, as `KEY=value` lines in
one or more `.env` files. They load at shell startup in filename order, and the
directory is kept at mode `700`.

For anything valuable, store a 1Password reference instead of the literal:

```shell
GITHUB_TOKEN=op://Private/GitHub/token
```

A value starting with `op://` is deliberately **not** exported. An exported
environment variable is readable by every process the shell starts, which is a
poor home for a live credential. Resolve them only where they are needed:

```shell
withsecrets ./deploy.sh    # run one command with references resolved
secret GITHUB_TOKEN        # print one secret
```

Both need the [1Password CLI](https://developer.1password.com/docs/cli/), which
is in the Brewfile.

## Private repositories on a remote server

```shell
./setup.sh --ssh
```

Generates an ed25519 key **on that machine**, configures `~/.ssh/config` for
github.com, and offers to add the public key to your GitHub account (via `gh`
if it is authenticated, otherwise it prints the key to paste). Re-running
reuses the existing key rather than replacing it.

A key generated this way never leaves the machine it was made on, and can be
revoked on its own from
[GitHub's SSH keys page](https://github.com/settings/keys) if that machine is
lost. Copying your laptop's private key to a server is deliberately not
supported: it turns one compromised box into a compromise of everything that
key can reach.

For a server you only use interactively, better still is to forward your agent
and put nothing on the server at all. On your **laptop**, in `~/.ssh/config`:

```
Host myserver
  HostName server.example.com
  ForwardAgent yes
```

Scope `ForwardAgent` to hosts you trust, never `Host *` — anyone with root on
the far end can use your agent while you are connected. The
[1Password SSH agent](https://developer.1password.com/docs/ssh/agent/) works
with this and asks for approval on each use.

## Intel Macs

Homebrew dropped support for macOS on Intel in September 2026. There are no
x86_64 bottles any more, so anything not already installed is compiled from
source, which is slow.

`setup.sh` reports the architecture, warns on Intel, and layers a
`Brewfile.<arch>` on top of the shared one:

| file | installed on |
| --- | --- |
| [`Brewfile`](packages/Brewfile) | every Mac — keep this to things that are cheap everywhere |
| [`Brewfile.arm64`](packages/Brewfile.arm64) | Apple Silicon only |
| [`Brewfile.x86_64`](packages/Brewfile.x86_64) | Intel only |

`curl` and `wget` sit in `Brewfile.arm64` because they pull in `openssl@3`,
whose Intel build takes far longer than it is worth. macOS ships its own
`curl`, so Intel machines use that instead.

**MacPorts is not a way around this**, despite Homebrew suggesting it.
MacPorts does support macOS Tahoe, but it has the same gap: it publishes
x86_64 binaries up to darwin_24 and, for darwin_25, arm64 only. Switching
would trade Homebrew's source builds for MacPorts' source builds and cost you
a second set of manifests and package names.

## Layout

```
setup.sh            entry point
setup/              the steps it runs
packages/           Brewfile and apt.txt, plus the .full variants
shell/              shared shell config, plus os/ for per-platform bits
git/ editor/ ruby/  config files, linked into $HOME
```

## Commit signing

Commits are signed with an **SSH key**, not GPG. It behaves identically on
macOS and Linux, needs no gpg install, and works with
[1Password's SSH agent](https://www.1password.dev/ssh/git-commit-signing).

Signing is set up only by `./setup.sh --full`, because a remote server has no
business holding a signing key. The tracked config sets just `gpg.format`;
whether to sign and which key to use are written to `~/.gitconfig.local`, so a
server is never left with signing switched on and no key — its commits simply
go unsigned instead of failing.

`setup.sh` picks the key in this order, which matters more than it looks:

1. a local private key file (`~/.ssh/id_ed25519`) — referenced **by path**
2. an already-configured SSH key
3. whatever the SSH agent is holding

A path signs straight from the file. A literal public key requires the private
half to be in an agent, so using one for a key that is only on disk fails with
`Couldn't find key in agent?` on every commit.

If 1Password's SSH agent is running, `gpg.ssh.program` is pointed at
`op-ssh-sign` automatically. If 1Password is installed but its agent is off,
signing falls back to `ssh-keygen` rather than being configured into a state
that cannot sign.

After setup, a throwaway repo is used to make a real signed commit and verify
it, so a broken configuration is reported rather than discovered later.

**On GitHub**, register the key *twice*: once as an authentication key and
again as a signing key. They are separate, and an auth key alone will not mark
your commits verified. `./setup.sh --ssh` offers to do both.

---

Started as a fork of [adamhollett/dotfiles](https://github.com/adamhollett/dotfiles).
