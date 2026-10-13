# Backups

falcon and panda each back up their home directory to a Hetzner Storage Box with [borgmatic](https://torsion.org/borgmatic/), which drives [borg](https://www.borgbackup.org/).
This guide explains what that setup does, how to look after it, and how to get files back.
Words in *italics* the first time they appear are explained in the [glossary](#glossary) at the end.

- [What the setup does, and why](#what-the-setup-does-and-why)
- [Running a backup by hand](#running-a-backup-by-hand)
- [One-time setup](#one-time-setup)
- [Reading the waybar icon](#reading-the-waybar-icon)
- [Restoring](#restoring)
- [Using a snapshot](#using-a-snapshot)
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

falcon's MEGAsync folder is backed up, apart from MEGA's own trash (`MEGAsync/.debris`).
MEGA syncs a deletion or a corrupted file to every device, so it is not a backup by itself; a borg archive from before the accident is.
The leave-out list applies inside it like anywhere else, so a synced folder called `build` or `Downloads` is skipped too.

panda leaves its MEGA folder out altogether.
It syncs the same files as falcon's, and each machine's backups are stored apart, so backing it up on both would store everything in it twice for nothing.
That exclusion is in [`~/.config/borgmatic/patterns.device`](../devices/laptop/.config/borgmatic/patterns.device), the list for things only one machine leaves out.

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
When backups stop without failing, because the machine was never on at 19:00 or the timer was turned off, a notification tells you once the last good backup is more than a week old (see [When backups fail or go stale](#when-backups-fail-or-go-stale)).

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

### Snapshots, in case a machine is compromised

Each machine's key can delete that machine's archives: it has to, because every run prunes the old ones.
So malware on a machine could wipe that machine's backups through borg, and nothing on the machine could stop it.

*Snapshots* are what it can't reach.
Every Sunday at 00:00 UTC (01:00 or 02:00 in Brussels), Hetzner takes a read-only snapshot of the whole Storage Box, and keeps the last 10: about ten weeks, enough time to notice damage that crept in slowly.
Snapshots are made and deleted only through Hetzner's API, which needs the token you delete straight after setup, so nothing on either machine can create, change or remove one.

That is six or seven hours after Saturday's 19:00 backup started, so a snapshot normally catches both repositories at rest.
Should a long backup still be running then, the snapshot is no worse for it: borg's repository survives being frozen mid-write the way it survives a power cut.

A snapshot covers the whole box, including the main account's own files.
It takes up space only for data deleted after it was taken, so a week in which little was pruned costs little of the 1 TB.
[Using a snapshot](#using-a-snapshot) below explains how to look inside one and how to roll the box back to it.

### The main account

The Storage Box's main account can reach every folder on the box, both machines' repositories included.
So the setup turns off its Samba and WebDAV access and changes its password to a random one that it throws away.
After that, no file on either machine is a way into the whole box.

To use the main account, reset its password in the Hetzner Console when you need it.
Running the setup script again afterwards throws the password away again.

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
  "last_run": 1791835000,
  "last_success": 1791835000,
  "added_bytes": 52428800,
  "archives": 12
}
```

`state` is `running` while a backup is going, then `succeeded` or `failed`.
`last_run` is when the last backup ended, whichever way it went.
The other three describe the last backup that succeeded: when it ended (in seconds since 1970; `date -d @1791835000` turns that into a date), how much it added, and how many archives the repository then held.
A failed backup leaves them as they were, so the file always says when you last had a good one.
Right after a success, `added_bytes` and `archives` read `null` for a minute or so while they are measured, and stay `null` if measuring them failed.
Anything that shows how your backups are doing reads this file, so it never has to contact the Storage Box.

## One-time setup

Each machine is set up once, by running [`scripts/setup-backups.sh`](../scripts/setup-backups.sh) from the dotfiles folder.
It prepares both ends: an account for this machine on the Storage Box, and the key, passphrase and repository on the machine.
Every step first checks whether it is already done and skips itself if so, so if the script stops halfway, fix what it complained about and run it again.

This is for a machine whose backups start from nothing.
A machine that replaces one whose disk died, and should take over its backups, is set up in restore mode instead (see [Restoring a whole machine](#restoring-a-whole-machine)); run without it, the script stops when it finds the existing repository, and leaves it untouched.

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
10. **Sets the snapshot plan**: every Sunday at 00:00 UTC, keeping 10 (see [Snapshots, in case a machine is compromised](#snapshots-in-case-a-machine-is-compromised)). The plan is the same for the whole box, so on the second machine this step finds it already set.
11. **Locks the main account down** (see [The main account](#the-main-account)): turns off its Samba and WebDAV access, and resets its password to a random one that it throws away. There is no way to check whether anyone still knows the password, so the reset happens on every run.
12. **Turns on the evening backups** (see [When backups run](#when-backups-run)). This is the very last step, so a machine whose setup stopped halfway doesn't fail a backup every evening.

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

A cloud icon in the bar, just right of the updates counter, shows how your backups are doing.
It changes the moment a backup starts or ends, whether the timer started it or you did.
It reads the status file described in [Running a backup by hand](#running-a-backup-by-hand), and asks the timer when the next backup is due, so looking at it never contacts the Storage Box.

| Icon | Means | What to do |
| ---- | ----- | ---------- |
| Plain cloud with a tick | The last backup succeeded, less than 3 days ago. | Nothing. |
| Cloud with an upward arrow | A backup is running now. | Nothing. A scheduled one keeps the machine from going to sleep by itself until it is done. |
| Amber cloud with an exclamation mark | Stale: the last backup that succeeded was 3 or more days ago. | See [When backups fail or go stale](#when-backups-fail-or-go-stale). |
| Red cloud with an exclamation mark, red border | The last backup failed, after all its retries. | See [When backups fail or go stale](#when-backups-fail-or-go-stale). |
| Grey cloud, crossed out | Never backed up: no backup has succeeded on this machine yet. | If the tooltip says no backup is scheduled, set the machine up (see [One-time setup](#one-time-setup)). Otherwise the first one runs at 19:00. |

Hover over the icon for the details:

- **Last backup**: when the last successful backup ended, and how long ago that was.
- **Added**: how much new data that backup stored, after deduplication. It reads `unknown` for a minute or so after a backup ends, while it is being measured.
- **Archives**: how many archives the repository holds.
- **Next backup**: when the timer will next start one. **No backup is scheduled** means the timer is off.

Clicking the icon opens the backup log, the same as `journalctl --user -u backup.service`, at its end, where the latest backup is.
Press `q` to close it.
A backup you run by hand prints to your terminal instead, so it isn't in that log.

The icon can be stuck on the upward arrow if a backup was cut off by a power cut, or killed without a chance to clean up.
If `systemctl --user status backup.service` says `inactive` and no `borgmatic` is running, that is what happened; the next backup puts the icon right.

## Restoring

Restoring only ever reads from the repository: nothing below changes or deletes an archive.
What it does change is files on your machine, so each walkthrough says where the files land before you run it.

### Finding the archive you need

Each archive is named after the machine and the moment its backup started, such as `falcon-2026-10-12T19:00:04.512889`.
To list them, oldest first:

```bash
borgmatic repo-list
```

Wherever a command below asks for an archive, `latest` stands for the newest one.

Inside an archive, every path starts with `home/` and your user name, and has no leading `/`: your `~/Documents/cv.odt` is `home/quinten/Documents/cv.odt`.
The commands below write `$USER`, which the shell fills in with your user name.

To find which archives hold a file, give part of its name or path:

```bash
borgmatic list --find cv.odt
```

That reads through every archive's list of files, so it takes a while.

### Restoring a single file

The easiest way is to *mount* an archive: it then shows up as a read-only folder you can browse in Nautilus, and you copy out what you need.

1. Mount the newest archive on an empty folder:
   ```bash
   mkdir -p ~/restore
   borgmatic mount --archive latest --mount-point ~/restore
   ```
2. Open `~/restore` in Nautilus and go into `home`, then your user name. The first folder you open can take a minute while borg fetches the archive's list of files.
3. Copy the file to where it belongs, like any other copy. In a terminal, `cp -a` keeps the file's original dates and permissions too:
   ```bash
   cp -a ~/restore/home/$USER/Documents/cv.odt ~/Documents/
   ```
4. Unmount it when you're done:
   ```bash
   borgmatic umount --mount-point ~/restore
   ```

While an archive is mounted, the repository is locked, and a backup that starts meanwhile can't get at it: it fails after its retries, with a notification.
So unmount before 19:00, and before running a backup by hand.

To find an older version of a file, leave `--archive latest` out: `~/restore` then holds a folder for every archive, named as in `borgmatic repo-list`, and you can open the same file in each.

### Restoring a whole folder

A folder can come back the same way as a single file: mount the archive and copy the folder out in Nautilus.
That suits a folder you want to look through first, or of which you only need part.

For a big folder, *extracting* is faster: borg writes the files out itself, instead of Nautilus copying them across one by one.
To extract `~/Documents/thesis` from the newest archive into `~/restore`, beside the current folder rather than over it:

```bash
borgmatic extract --archive latest --path home/$USER/Documents/thesis --destination ~/restore --progress
```

The folder lands at `~/restore/home/<your user name>/Documents/thesis`, with its original dates and permissions.
Compare it with the current one, move it into place, and delete `~/restore` afterwards.

`--path` has to match the path in the archive exactly: capitals count, and there is no `/` at the end.
`borgmatic list --archive latest --path home/$USER/Documents` shows what the archive holds under a folder.

To extract straight back into place instead:

```bash
borgmatic extract --archive latest --path home/$USER/Documents/thesis --destination ~ --strip-components 2 --progress
```

`--strip-components 2` drops the `home/<your user name>` from the front of every path, so the folder lands back at `~/Documents/thesis`.
A file that is in both the folder and the archive is replaced by the archive's copy without asking; a file only in the folder is left alone.

### Restoring a whole machine

When a machine's disk dies, or the machine is lost or stolen, a new machine takes over its backups and gets every file back.
The whole home directory comes down over your internet connection, so set aside an evening.

You need the passphrase, from KeePassXC, and an API token, created as in [step 2 of the setup](#2-create-an-api-token).

1. **Install Arch with the lost machine's hostname and user name.** The hostname is how the setup script finds the machine's sub-account, and borgmatic only lists archives named after this machine's hostname. The user name is in every path in the archive. Use the same login password as before, too: the restore brings back your old keyring, and it unlocks at login only with the password it had.
2. **Apply the dotfiles.** Clone them to `~/dotfiles` and run `./scripts/apply.sh`, as on any new machine, then log in to Hyprland: the next step needs the keyring unlocked.
3. **Run the setup script in restore mode**, with `hcloud` installed as in [step 1 of the setup](#1-before-you-start):
   ```bash
   read -rs HCLOUD_TOKEN && export HCLOUD_TOKEN   # paste the token, press Enter
   ./scripts/setup-backups.sh --restore
   ```
   It works through the same steps as the setup, with these differences:
   - It finds the machine's sub-account rather than creating one. If there is none, it stops: the hostname is usually the reason.
   - The key it installs on the Storage Box replaces the lost machine's key, so the old disk can't get in any more, whoever has it now.
   - It asks for the passphrase from KeePassXC, checks it opens the repository, and only then stores it in the keyring. If it doesn't open the repository, it asks again.
   - It never creates a repository. If the Storage Box holds none for this hostname, it says so and stops.
   - It doesn't show the passphrase and key export, which you already have.
   - It leaves the evening backups off. A backup now would store the near-empty home directory as the newest archive, and prune a real archive to make room for it.

   Then delete the token, as in [step 5 of the setup](#5-delete-the-api-token).
4. **Check you can read the backups**: `borgmatic repo-list` lists the archives. Note the newest one's name, at the bottom.
5. **Extract the whole home directory** from that archive, over the new one:
   ```bash
   cd ~
   borgmatic borg extract --progress --strip-components 2 \
     --exclude "home/$USER/.ssh/storagebox*" \
     --exclude "home/$USER/.config/systemd/user/timers.target.wants/backup.timer" \
     ::<archive> home/$USER
   ```
   `borgmatic borg` hands the command to borg itself, for the one thing `borgmatic extract` can't do: leave files out.
   The first is the SSH key from step 3; the archive's copy is the lost machine's key, which the Storage Box no longer accepts.
   The second is what turned the evening backups on for the lost machine; restored, it would turn them on here at the next login, before the files are all back.
   borg writes into the folder you're in, which is why `cd ~` comes first, and it needs the archive's full name, since `latest` doesn't work here.
   A file that is in both the archive and the new home directory is replaced by the archive's copy; anything else on the new machine is left alone.
   Leave the machine alone until it is done, since open applications have their files replaced under them.
   If it is interrupted, run it again; it starts over.
6. **Reboot**, and log in with your old password.
7. **Reinstall your software.** The archive brought back the list of packages you had installed by hand:
   ```bash
   yay -S --needed $(< ~/.local/state/backup/packages.txt)
   ```
   If a package has been renamed or dropped since, yay stops; delete its line from the file and run it again.
8. **Turn the evening backups back on**, from the dotfiles folder:
   ```bash
   ./scripts/apply.sh && systemctl --user enable --now backup.timer
   ```
   The archive brought back `~/dotfiles` as it was, and `./scripts/apply.sh` puts its configuration in place again.
   Do this only once the extract has finished: a backup over a half-restored home directory would store it as the newest archive.

The first backup reads every file again, because borg's record of the files it has already seen is in `~/.cache`, which isn't backed up.
It uploads little, though, since the data is already in the repository.
Until it has run, the waybar icon shows a backup running: the status file came back from the archive, which was taken while a backup was running.

If borg says the repository's key is missing or damaged, type the key back in from the paper:

```bash
borgmatic key import --paper
```

## Using a snapshot

What snapshots are for is explained under [Snapshots, in case a machine is compromised](#snapshots-in-case-a-machine-is-compromised).
Everything here needs an API token again, created as in [step 2 of the setup](#2-create-an-api-token) and deleted again when you are done.
A **Read** token is enough to list snapshots; changing settings or rolling back needs **Read & Write**.

```bash
read -rs HCLOUD_TOKEN && export HCLOUD_TOKEN   # paste the token, press Enter
hcloud storage-box list                        # the box's name, username and server
hcloud storage-box snapshot list <box>         # every snapshot, with its name and age
```

The Hetzner Console shows the same list, in the Storage Box's **Snapshots** tab.

### Looking inside a snapshot

Only the main account can see snapshots, in a hidden `.zfs/snapshot` folder at the top of the box, and only once that folder is switched on.
Switch it on, give the main account a password you choose, and connect with SFTP, using the username and server from `hcloud storage-box list`:

```bash
hcloud storage-box update-access-settings <box> --enable-zfs=true --enable-ssh=true
read -rs password && hcloud storage-box reset-password <box> --password "$password"
sftp -P 23 <username>@<server>
```

Inside SFTP, each snapshot is a folder holding the whole box as it was:

```
sftp> ls .zfs/snapshot
sftp> ls .zfs/snapshot/<snapshot>/backups/falcon/borg
sftp> get .zfs/snapshot/<snapshot>/<some file>
```

`get` copies a file from the snapshot to your machine, which is how to get back one of the main account's files from before it was deleted.
A machine's `backups/<machine>/borg` folder in there is a whole repository, though, not your files: it shows borg's data files, and the only way to restore from it is to roll the box back (below).

When you are done, lock the main account again by running `./scripts/setup-backups.sh` once more, which throws the password away.
The snapshot folder can stay switched on: it is read-only, and only the main account sees it.

### Rolling the box back

A rollback replaces **everything** on the box with the snapshot: both machines' repositories and the main account's files.
Whatever either machine backed up since the snapshot was taken is gone, and so, assume, are the snapshots newer than the one you roll back to.
It is the last resort, for when a repository itself is gone or broken, for instance because malware deleted its archives.
To get back a file you lost, restore it from an archive instead (see [Restoring](#restoring)).

1. Do it well away from 19:00, and check on both machines that no backup is running: `systemctl --user status backup.service` must say `inactive`.
2. Pick the snapshot from the list above and roll back to it:
   ```bash
   hcloud storage-box rollback-snapshot <box> --snapshot <snapshot>
   ```
3. Delete the token, as in [step 5 of the setup](#5-delete-the-api-token).

Afterwards, borg on **each** machine refuses its own repository:

```
Cache, or information obtained from the security directory is newer than repository - this is either an attack or unsafe (multiple repos with same ID)
```

That is borg noticing that its repository went back in time, which is exactly what you just did.
Tell borg it is expected by deleting what it remembers about the newer repository, on each machine.
borg keeps that in a folder per repository, named after the repository's ID; find the one for the Storage Box:

```bash
grep -lx 'ssh://storagebox/./borg' ~/.config/borg/security/*/location | xargs stat -c '%y  %n' | sort
```

Each line is a time and a path, `~/.config/borg/security/<id>/location`, and there is normally just one.
There are more if the repository was ever created again from scratch; the current one is then the last line, the one borg used most recently.
Put that line's `<id>` in the commands below:

```bash
id=<id>
rm ~/.config/borg/security/$id/manifest-timestamp
rm -r ~/.cache/borg/$id
borgmatic repo-list   # lists the archives the snapshot held
```

Leave the rest of that security folder alone: its `nonce` file is what stops borg from ever reusing an encryption counter the newer repository already used.
Only do this after a rollback you did yourself.
If the message appears without one, someone else replaced your repository with an older copy: delete nothing, and find out how.

The next evening's backup carries on from the rolled-back repository; the first one after the rollback takes a little longer, while borg rebuilds the cache you deleted.

## When backups fail or go stale

When the [waybar icon](#reading-the-waybar-icon) is amber, a backup hasn't run in a while, or each one has been skipped:

1. Hover over the icon. If it says **No backup is scheduled**, turn the evening backups back on (see [When backups run](#when-backups-run)).
2. Otherwise the machine was probably off, asleep or on battery at 19:00 for a few evenings, and each of those days was skipped. Backups also only run while you are logged in, so a machine left at the login screen skips them too. Run a backup by hand: `borgmatic --verbosity 1 --progress --stats`.

When the icon is red, the last backup failed.
If it was a scheduled one, click the icon and read the last lines of the log; if you ran it by hand, its error is in the terminal you ran it in.
Most failures are the network: the Storage Box couldn't be reached through all the retries.
Run a backup by hand once you're back online; when it succeeds, the icon turns back to a tick.

### What a failed backup's error means

These are the errors you are most likely to find at the end of the log, and what to do about each.

**`Command 'secret-tool lookup service borgmatic repository storagebox' returned non-zero exit status 1.`**

borgmatic couldn't get the passphrase out of the keyring.
Usually the keyring was locked, which happens when you didn't log in with your password; logging in normally unlocks it.
If `secret-tool lookup service borgmatic repository storagebox` prints nothing even then, the passphrase is gone from the keyring: put it back from KeePassXC with the command below, which asks for it.

```bash
secret-tool store --label 'borgmatic passphrase for storagebox' service borgmatic repository storagebox
```

**`Passphrase supplied in BORG_PASSPHRASE, by BORG_PASSCOMMAND, or via BORG_PASSPHRASE_FD is incorrect.`**

The keyring holds a passphrase, but not the one that opens the repository.
Replace it with the one from KeePassXC, using the same `secret-tool store` command as above, then check that `borgmatic repo-list` lists the archives.

**`Failed to create/acquire the lock … (timeout).`**

Something else on this machine is using the repository: an archive that is still mounted (see [Restoring a single file](#restoring-a-single-file)), or a backup you started by hand.
No other machine can be, since each has its own repository.
Run the backup again once that is done.
If neither is the case, a backup was killed while it held the lock; check that `systemctl --user status backup.service` says `inactive` and no `borgmatic` is running, then remove the lock with `borgmatic borg break-lock`.

**`Connection closed by remote host.`**

SSH couldn't reach or log in to the Storage Box; the lines just before it say why.
A name that doesn't resolve, or a timeout, is the network: run the backup again once you're online.
`Permission denied (publickey)` means the Storage Box no longer accepts this machine's key, because restore mode ran on another machine with this hostname, or `~/.ssh/storagebox` was replaced.
Running `./scripts/setup-backups.sh` again, with a token, installs this machine's key again.

**`Cache, or information obtained from the security directory is newer than repository`**

The repository went back in time; see [Rolling the box back](#rolling-the-box-back).

### The "No backup in N days" notification

A minute after you log in, and every day at 12:00, the machine checks when a backup last succeeded.
If that was more than 7 days ago, a notification says so, and it keeps saying so at every login and every noon until a backup succeeds.
Like the waybar icon, it reads the status file and asks whether the timer is on, so the check never contacts the Storage Box.

Where the icon turns amber after 3 days, the notification waits a week: a long weekend away is no reason to interrupt you, but a week without a backup is.
A failed backup has a notification of its own the evening it fails; this one is for backups that stopped happening without anything failing.

The notification comes in three kinds:

- **No backup in N days**: the last backup that succeeded was N days ago. Work through the steps for an amber icon above.
- **Never backed up**: this machine was set up, but no backup has succeeded on it yet. Right after setup, that is expected until the first one runs at 19:00; run one by hand to settle it now (see [step 6 of the setup](#6-make-the-first-backup)). Later, work through the steps for an amber icon above.
- **Backup status unreadable**: `~/.local/state/backup/status.json` is damaged, so there is no telling when the last backup succeeded. Run a backup by hand; when it succeeds, it writes the file afresh.

A machine that was never set up never gets the notification.

To see when the check last ran and when it runs next:

```bash
systemctl --user list-timers backup-stale.timer
```

To silence it until the next `./scripts/apply.sh`, which turns it back on:

```bash
systemctl --user disable --now backup-stale.timer
```

## Glossary

**Repository (repo)**
: The place borg stores your backups: one folder on the Storage Box per machine.
It holds every archive, deduplicated and encrypted, plus the encryption key, locked with your passphrase.

**Archive**
: One backup: what your home directory looked like at the moment a run started.
You restore from an archive, either by copying files out of it or by mounting it and browsing it like a folder.

**Mount**
: Making an archive show up as a read-only folder, so you can browse it and copy files out (see [Restoring a single file](#restoring-a-single-file)).
The repository is locked until you unmount it again.

**Extract**
: Having borg write files out of an archive onto your disk, which is faster than copying them out of a mounted archive (see [Restoring a whole folder](#restoring-a-whole-folder)).

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
A snapshot holds a repository, not your files directly: to use one, you roll the box back to it and then restore files from the repository (see [Using a snapshot](#using-a-snapshot)).

**Source**
: What gets backed up: your home directory, minus what the patterns, `CACHEDIR.TAG` and `.nobackup` leave out.

**Timer**
: systemd's way of starting something on a schedule, like cron.
`backup.timer` starts `backup.service`, which runs borgmatic, every evening at 19:00.
