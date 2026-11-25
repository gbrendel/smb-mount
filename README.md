# smb-mount

`mount.sh` is an interactive Bash utility for mounting SMB/CIFS shares on Linux. It manages the mounted share, an optional symlink in the user's home directory, persistent `/etc/fstab` entries, credentials, and an audit ledger.

The script has built-in generic defaults, so it can mount a share before a configuration file exists. It is suitable for desktop Linux and SteamOS systems, but `/etc/fstab` changes and mount operations require `sudo`.

## Features

- Mount and unmount a CIFS/SMB share
- Create or remove a home-directory symlink to the mount point
- Resolve hostnames with DNS, mDNS/Avahi, or ping
- Try the hostname and resolved IPv4 address, with a configurable number of retries
- Offer a one-time fallback IP address when automatic mounting fails
- Save credentials for unattended mounts
- Add, inspect, update, or remove a systemd-aware `/etc/fstab` automount entry
- Record mount, symlink, directory, and fstab actions in a ledger
- Clean up script-managed mounts, links, directories, and fstab entries
- Run an interactive setup wizard
- Show the current configuration and mount status
- Use terminal status boxes and a SteamOS immutable-system notice

## Requirements

- Bash
- `sudo`
- CIFS utilities providing `mount -t cifs` and `umount`
- `mountpoint`
- Standard Unix utilities used by the script, including `awk`, `grep`, `mkdir`, `ln`, and `df`
- `/etc/fstab` access for boot-mount commands
- A system SMB/CIFS server that accepts SMB 3.0

Optional:

- `nc` or Bash `/dev/tcp` support for SMB port 445 checks
- `getent` for hostname resolution
- `avahi-resolve` for mDNS resolution
- `ping` for IPv4 resolution
- `systemctl` to reload systemd configuration after fstab changes

On Debian/Ubuntu and derivatives, CIFS utilities can usually be installed with:

```bash
sudo apt install cifs-utils
```

## Quick Start

Make the script executable if needed:

```bash
chmod +x mount.sh
```

Run the interactive setup:

```bash
./mount.sh setup
```

The wizard can:

1. Copy an existing configuration file.
2. Configure the host, share, mount point, home link, username, domain, retry count, and ledger path.
3. Optionally save SMB credentials.
4. Optionally add a boot/automount entry to `/etc/fstab`.
5. Optionally mount the share immediately.

Alternatively, mount using the built-in defaults:

```bash
./mount.sh mount
```

## Commands

| Command | Alias | Description |
| --- | --- | --- |
| `mount` | `up` | Mount the share, create the home symlink, and verify access. |
| `umount` | `down` | Remove the home symlink and unmount the share; fall back to a lazy unmount if busy. |
| `fstab` | | Add or update the persistent boot/automount entry in `/etc/fstab`. |
| `check-fstab` | `automount-check` | Inspect the entry for the configured mount point. |
| `remove-fstab` | `unfstab`, `automount-remove` | Remove the managed or matching mount entry from `/etc/fstab`. |
| `ledger` | | Display recorded actions. |
| `cleanup` | `clean`, `purge` | Confirm and remove script-tracked links, mounts, fstab entries, and empty directories. |
| `status` | | Show configuration, mount, symlink, and fstab state. |
| `setup` | `wizard`, `config` | Run the interactive setup and credential wizard. |
| `features [topic]` | `manual [topic]` | Show a feature overview or topic-specific help. |
| `help` | `-h`, `?`, `--help` | Show brief usage or verbose feature information. |

Examples:

```bash
./mount.sh status
./mount.sh mount
./mount.sh fstab
./mount.sh check-fstab
./mount.sh umount
./mount.sh ledger
./mount.sh features all
./mount.sh cleanup
```

## Configuration

The script loads configuration from:

```text
$HOME/.config/smb-mounter/config.env
```

It also looks for `config.env.default` either in that configuration directory or beside `mount.sh`. Missing configuration is handled without preventing `mount`, `status`, or other commands from running.

The included [config.env.default](config.env.default) contains these settings:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONFIG_DIR` | `$HOME/.config/smb-mounter` | Script configuration directory |
| `CONFIG_FILE` | `$CONFIG_DIR/config.env` | Runtime configuration file |
| `CREDS_FILE` | `$CONFIG_DIR/credentials` | Optional SMB credentials file |
| `LEDGER_FILE` | `$CONFIG_DIR/ledger.log` | Audit ledger |
| `FSTAB_BACKUP` | `/etc/fstab.smb-mounter.bak` | Backup of `/etc/fstab`, when created |
| `FSTAB_MARKER` | `# smb-mounter-managed` | Marker for managed fstab entries |
| `HOST` | `nas.local` | SMB server hostname or IP address |
| `SHARE_PATH` | `share/folder` | Share path without the leading `/` |
| `MOUNT_POINT` | `/mnt/smb-share` | Local CIFS mount point |
| `HOME_LINK` | `$HOME/Documents/SMB-Share` | Optional symlink to the mount point |
| `SMB_USER` | `smbuser` | SMB username |
| `SMB_DOMAIN` | `WORKGROUP` | SMB workgroup or domain |
| `MOUNT_UID` | Current user UID | Ownership UID used by the CIFS mount |
| `MOUNT_GID` | Current user GID | Ownership GID used by the CIFS mount |
| `MAX_RETRIES` | `3` | Mount attempts per target |

The configuration and credentials directories are intended to have restricted permissions. The script creates `~/.config/smb-mounter` with mode `700` and writes `config.env`, `credentials`, and `ledger.log` with mode `600` when it manages those files.

## Credentials

The setup wizard can save credentials in the following path:

```text
$HOME/.config/smb-mounter/credentials
```

The credentials file is an SMB/CIFS credentials file containing the username, password, and domain. It is not stored in the normal configuration file and is created with mode `600`.

At mount time, the script uses:

- Saved credentials first when the credentials file exists
- Interactive username/domain parameters if saved credentials fail or no credentials file exists

If mounting with saved credentials fails on the first attempt, the script retries interactively and then honors `MAX_RETRIES`.

## Mount Behavior

The mount command:

1. Loads configuration or uses built-in defaults.
2. Creates the mount directory if it does not exist.
3. Resolves `HOST` and, when possible, tries both the hostname and its resolved IPv4 address.
4. Mounts with `uid`, `gid`, UTF-8 I/O charset, and SMB protocol version `3.0`.
5. Creates `HOME_LINK` as a symlink to `MOUNT_POINT`.
6. Records successful mount and symlink actions in the ledger.

The share UNC name is constructed as:

```text
//HOST/SHARE_PATH
```

For example:

```text
//nas.local/share/folder -> /mnt/smb-share
```

If the mount still fails, the script offers setup, a one-time fallback IP address, or exit.

## Boot Mounts and `/etc/fstab`

The `fstab` command writes a line managed by the script marker:

```text
//HOST/SHARE_PATH MOUNT_POINT cifs ... 0 0 # smb-mounter-managed
```

The entry includes `_netdev`, `nofail`, and `x-systemd.automount`. If a credentials file exists, it is referenced with `credentials=`.

The script creates `/etc/fstab.smb-mounter.bak` if that backup does not already exist. It reloads systemd when `systemctl` is available.

### SteamOS and immutable systems

SteamOS can reset or remove system files and fstab entries across OS updates. After an update, re-run:

```bash
./mount.sh fstab
```

or:

```bash
./mount.sh mount
```

## Ledger

The default ledger is:

```text
$HOME/.config/smb-mounter/ledger.log
```

It uses pipe-separated entries with a UTC timestamp:

```text
timestamp|action|target|detail
```

Run `./mount.sh ledger` to display entries. Ledger creation is automatic for mount and cleanup operations and can be requested interactively from setup and ledger commands.

## Cleanup

`cleanup` asks for confirmation before removing:

- Script-tracked and configured home symlinks
- Managed `/etc/fstab` entries
- Active mounts
- Empty mount directories

The cleanup command uses ledger entries to identify additional symlinks, mounts, and directories previously recorded by the script. It keeps non-empty or in-use directories and logs cleanup actions when possible.

## Troubleshooting

Check overall state:

```bash
./mount.sh status
```

Check the boot entry:

```bash
./mount.sh check-fstab
```

Common checks:

- Confirm TCP port 445 is reachable on the SMB server.
- Verify `HOST` and `SHARE_PATH` in `~/.config/smb-mounter/config.env`.
- Confirm the SMB username, domain, and credentials are valid.
- Ensure the mount point is not in use before unmounting or cleanup.
- Ensure `mount.cifs` is installed and `sudo` is configured.
- Re-run the setup wizard after changing connection details.

## Help

Run:

```bash
./mount.sh help
./mount.sh features all
./mount.sh features mount
```
