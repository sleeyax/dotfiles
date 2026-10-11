# Backups

falcon and panda each back up their home directory to a Hetzner Storage Box with [borgmatic](https://torsion.org/borgmatic/), which drives [borg](https://www.borgbackup.org/).
This guide explains what that setup does, how to look after it, and how to get files back.
Words in *italics* the first time they appear are explained in the [glossary](#glossary) at the end.

- [What the setup does, and why](#what-the-setup-does-and-why)
- [Running a backup by hand](#running-a-backup-by-hand)
- [One-time setup](#one-time-setup)
- [Reading the waybar icon](#reading-the-waybar-icon)
- [Restoring](#restoring)
- [When backups fail or go stale](#when-backups-fail-or-go-stale)
- [Glossary](#glossary)

## What the setup does, and why

### One repository per machine

Each machine writes to its own *repository* on the Storage Box.
A problem with one machine's backups, or a stolen key on one machine, never touches the other's.

The configuration is the same file on both machines, [`~/.config/borgmatic/config.yaml`](../home/.config/borgmatic/config.yaml).
It doesn't name a server or a user: it points at `storagebox`, an SSH host alias that each machine's own, untracked `~/.ssh/config` fills in with that machine's Storage Box account.
So `ssh storagebox` and a manual `borg` command reach the same place borgmatic does.

### Encrypted before it leaves the machine

Everything is encrypted on your machine before it is uploaded, so Hetzner only ever stores data it can't read.
The repository uses borg's `repokey` mode: the encryption key lives inside the repository, locked with a passphrase.

The passphrase is kept in your GNOME keyring, which unlocks when you log in.
That lets a backup run without asking you anything, while the passphrase never sits in a plain file on disk.
The keyring is the everyday copy; KeePassXC and a printed key export are the ones you restore from when the machine is gone.

### What goes in, and what stays out

The *source* is your home directory, and only the part on the same filesystem: anything mounted inside it, such as a USB drive or a network share, is skipped.

Left out is everything you could get back by reinstalling or re-downloading: caches, toolchains, `node_modules` and other build output, games, virtual machines, browser profiles and model weights.
The full list is [`~/.config/borgmatic/patterns`](../home/.config/borgmatic/patterns), with a comment above each group.
Two more rules leave folders out without editing that list:

- A folder containing a file called `CACHEDIR.TAG` is skipped. Many tools mark their cache folders this way on their own.
- A folder containing a file called `.nobackup` is skipped. Create one to leave a folder out on the spot: `touch ~/some/folder/.nobackup`.

A file your user can't read is skipped with a warning rather than failing the backup.
That mostly means database folders a Docker container created inside one of your projects, which only the container's own user can open.

Your MEGAsync folder is backed up, apart from MEGA's own trash (`MEGAsync/.debris`).
MEGA syncs a deletion or a corrupted file to every device, so it is not a backup by itself; a borg archive from before the accident is.
The leave-out list applies inside it like anywhere else, so a synced folder called `build` or `Downloads` is skipped too.

Before every backup, the list of packages you installed explicitly (`pacman -Qqe`) is written to `~/.local/state/backup/packages.txt`, so it is in the archive too.
On a rebuilt machine, that file is what tells you what to reinstall.

### How much history is kept

Every run makes a new *archive*, then *prunes* the old ones and *compacts* the repository to free their space.
What is left after a prune:

| Kept | How many | Reaches back |
| ---- | -------- | ------------ |
| The last archive of each day | 7 | a week |
| The last archive of each week | 4 | a month |
| The last archive of each month | 6 | half a year |

Archives are deduplicated: a file that didn't change is stored once, however many archives contain it.
That is why keeping seventeen archives costs little more than keeping one.

### Checking the backups are readable

borgmatic checks the repository after a run, but not every time:

- Every 2 weeks, it checks the repository's structure and every archive's list of files.
- Once a month, it runs a *spot check*: it picks 1% of the files in your home directory at random and compares them with the newest archive. It fails if the archive's file count is more than 10% off, or if more than half the sampled files differ.

A full check, which reads back every byte, would download the whole repository, so it is never run on a schedule.

### Surviving a bad connection

A backup that fails, for instance because the router restarted, is retried three times.
The waits grow from 5 to 10 to 15 minutes, so the last try starts about half an hour after the first failure.

## Running a backup by hand

Run every step of a backup — create an archive, prune, compact, and any check that is due:

```bash
borgmatic --verbosity 1 --stats
```

Or only make an archive, listing each file as it goes in:

```bash
borgmatic create --list --stats
```

To see what is in the repository:

```bash
borgmatic repo-list                     # every archive
borgmatic list --archive latest         # every file in the newest archive
```

To see what a backup *would* include, without making an archive:

```bash
borgmatic create --dry-run --list
```

## One-time setup

Not written yet.
Setting a machine up against the Storage Box comes with the setup script.

## Reading the waybar icon

Not written yet.

## Restoring

Not written yet.

## When backups fail or go stale

Not written yet.

## Glossary

**Repository (repo)**
: The place borg stores your backups: one folder on the Storage Box per machine.
It holds every archive, deduplicated and encrypted, plus the encryption key, locked with your passphrase.

**Archive**
: One backup: what your home directory looked like at the moment a run started.
You restore from an archive, either by copying files out of it or by mounting it and browsing it like a folder.

**Prune**
: Deleting the archives the retention rules no longer keep (see [How much history is kept](#how-much-history-is-kept)).
A prune only forgets archives; the space they used is freed by the compact that follows it.

**Compact**
: Freeing the space in the repository that pruned archives were using.

**Spot check**
: A cheap test that a backup is restorable: compare a small random sample of your files with the newest archive.

**Snapshot**
: A frozen, read-only copy of the whole Storage Box, taken by Hetzner rather than by borg.
No machine can create or delete one, so even malware that wipes a repository can't reach the snapshots of it.
A snapshot holds a repository, not your files directly: to use one, you restore the repository from it and then restore files from the repository.

**Source**
: What gets backed up: your home directory, minus what the patterns, `CACHEDIR.TAG` and `.nobackup` leave out.
