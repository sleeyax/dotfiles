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

### When backups run

A backup starts every evening at 19:00, while you're at dinner, and at no other time.
A *timer* starts it, so you don't have to remember to.

- **The machine was off at 19:00:** that day is skipped. It isn't made up for when you turn the machine on, because a backup starting just as you sit down to work is what the schedule is there to avoid.
- **The machine was asleep at 19:00:** the timer goes off as soon as you wake it, but the backup only starts if it is still before 19:10. Later than that, the day is skipped too.
- **panda is on battery at 19:00:** the day is skipped, so a backup never drains the battery.
- **A backup that started in time** runs until it is done, however late that is.

While a backup runs, the machine doesn't go to sleep by itself: when panda's idle suspend comes due after 30 minutes, it is refused, and panda then stays awake until you next touch it and leave it idle for another 30 minutes.
Closing panda's lid still puts it to sleep, because closing the lid means you are leaving.
Suspending falcon by hand is refused too; in a terminal, `systemctl suspend` says the backup is in the way, and `systemctl suspend -i` suspends anyway, after asking for your password.
A backup cut short by sleep or a shutdown isn't wasted: the next one reuses everything it had already uploaded.

When a backup fails, after the retries described below, a desktop notification tells you so.

To see when the next backup is due, and when the last one started:

```bash
systemctl --user list-timers backup.timer
```

To read what the scheduled backups printed, including why one failed:

```bash
journalctl --user -u backup.service
```

To stop the evening backups, and to start them again:

```bash
systemctl --user disable --now backup.timer
./scripts/apply.sh && systemctl --user enable --now backup.timer   # from the dotfiles folder
```

Turning the timer off also removes its file from `~/.config/systemd/user`, which is why turning it back on goes through `./scripts/apply.sh` first.

### Surviving a bad connection

A backup that fails, for instance because the router restarted, is retried three times.
The waits grow from 5 to 10 to 15 minutes, so the last try starts about half an hour after the first failure.

## Running a backup by hand

Run every step of a backup — create an archive, prune, compact, and any check that is due:

```bash
borgmatic --verbosity 1 --progress --stats
```

`--verbosity 1` prints a line as each step starts, `--progress` keeps a live line updated while a step runs (how much has been read, compressed and deduplicated, and the current file), and `--stats` sums up the new archive at the end.

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

Every backup that makes an archive, whether you started it or it ran on its own, records how it went in `~/.local/state/backup/status.json`:

```json
{
  "state": "succeeded",
  "last_success": 1791835000,
  "added_bytes": 52428800,
  "archives": 12
}
```

`state` is `running` while a backup is going, then `succeeded` or `failed`.
The other three describe the last backup that succeeded: when it ended (in seconds since 1970; `date -d @1791835000` turns that into a date), how much it added, and how many archives the repository then held.
A failed backup leaves them as they were, so the file always says when you last had a good one.
Right after a success, `added_bytes` and `archives` read `null` for a minute or so while they are measured, and stay `null` if measuring them failed.
Anything that shows how your backups are doing reads this file, so it never has to contact the Storage Box.

## One-time setup

Each machine is set up once, by running [`scripts/setup-backups.sh`](../scripts/setup-backups.sh) from the dotfiles folder.
It prepares both ends: an account for this machine on the Storage Box, and the key, passphrase and repository on the machine.
Every step first checks whether it is already done and skips itself if so, so if the script stops halfway, fix what it complained about and run it again.

### 1. Before you start

The machine needs the dotfiles applied (`./scripts/apply.sh`), which installs borg and borgmatic and puts the config in place.

The script talks to Hetzner with `hcloud`, Hetzner's command-line tool.
You only need it while setting a machine up, so it isn't installed with everything else:

```bash
sudo pacman -S hcloud
```

### 2. Create an API token

The script needs permission to manage your Storage Box, which it gets from an *API token*: a long password for Hetzner's API.
A token can also delete the box's snapshots, so you create one just for the setup and delete it straight after.

1. Open the [Hetzner Console](https://console.hetzner.com/) and open the project your Storage Box is in.
2. Go to **Security** in the left-hand menu, then the **API tokens** tab.
3. Click **Generate API token**, describe it as something like `backup setup falcon`, choose **Read & Write**, and generate it.
4. Copy the token. The Console shows it only this once, which is fine: you only need it for the next few minutes.

### 3. Run the script

Hand the token to the script through an environment variable, typed in without echoing.
That keeps it out of your shell history and off the disk:

```bash
read -rs HCLOUD_TOKEN && export HCLOUD_TOKEN   # paste the token, press Enter
./scripts/setup-backups.sh
```

Here is what it does, in order:

1. **Finds the Storage Box** in the token's project.
2. **Creates a sub-account** named after the machine (`falcon`, `panda`), whose home is the folder `backups/<machine>` on the box. A sub-account is a separate login that can only see its own folder, so this machine can't reach the other machine's backups or anything else on the box. It can be reached over SSH from outside Hetzner, and nothing else: Samba and WebDAV are off.
3. **Generates an SSH key** at `~/.ssh/storagebox`. It has no passphrase, because backups run unattended.
4. **Adds a `storagebox` host to `~/.ssh/config`**, pointing at the sub-account. This is the name borgmatic's config uses. It also makes SSH notice a dead connection within about three minutes, instead of a backup hanging all night.
5. **Installs the key on the Storage Box**, restricted so that all it can do is run borg 1.4 on this machine's repository: no browsing files, no other folders. To upload it, the script gives the sub-account a random password, uses it once, then changes it to another random password that it throws away. From then on, the key is the only way in.
6. **Stores a new passphrase in your GNOME keyring**, where borgmatic finds it on every run.
7. **Creates the repository**, encrypted with that passphrase.
8. **Checks the restriction works**: the Storage Box must answer with borg 1.4 for this key, and must refuse to open a file browsing (SFTP) session with it.
9. **Shows you the passphrase and the key export.** See the next step.
10. **Turns on the evening backups** (see [When backups run](#when-backups-run)). This is the very last step, so a machine whose setup stopped halfway doesn't fail a backup every evening.

### 4. Store the passphrase and the key

Near the end, the script prints two things and waits for you:

- **The passphrase.** Save it in KeePassXC.
- **The key export**, a block of text starting `BORG PAPER KEY v1`. Print it, and keep the paper somewhere safe.

The repository can only be opened with both: the key is locked with the passphrase.
The copies on this machine (the keyring, and the key stored inside the repository) are the everyday ones.
KeePassXC and the paper are the ones you restore from when this machine is gone, or the repository's key is damaged.

Press Enter once both are stored.
The script won't show them again on a rerun, but you can always get them back while this machine works:

```bash
secret-tool lookup service borgmatic repository storagebox   # the passphrase
borgmatic key export --paper                                 # the key export
```

### 5. Delete the API token

Back in the Hetzner Console, under **Security** → **API tokens**, delete the token you created.
Nothing on the machine needs it again, and a leftover token could delete the box's snapshots.
Then forget it in the terminal too:

```bash
unset HCLOUD_TOKEN
```

### 6. Make the first backup

The first backup happens on its own at 19:00 that evening.
To see it work end to end straight away, run it by hand instead:

```bash
borgmatic create --progress --stats
borgmatic repo-list
```

The first one uploads everything, so expect it to take hours: about 12 GB an hour on a 28 Mbps upload.
For the first few minutes it prints nothing, while borgmatic checks which files the backup will include; the progress line appears once the upload starts.
It can be interrupted: the next run reuses whatever was already uploaded.
If it is still running at 19:00, that evening's backup can't get at the repository until it finishes; should it still be running after the last retry, the evening's backup fails with a notification, which is harmless.

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

**Timer**
: systemd's way of starting something on a schedule, like cron.
`backup.timer` starts `backup.service`, which runs borgmatic, every evening at 19:00.
