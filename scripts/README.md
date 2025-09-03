# Scripts

This directory contains utility scripts for the Blockypuck project.

## Available Scripts

### sync_blockchain.sh

Automatically syncs multiple folders and files to USB devices using rsync. Designed primarily for syncing Dogecoin blockchain data to Blockypuck devices for offline storage and backup.

#### Features

- **Multiple source paths**: Sync multiple folders and individual files
- **Auto-detects USB devices**: Filter devices containing specific keyword in name or label
- **PUP management**: Optional integration with pups on Dogebox to gracefully stop and restart containers
- **Auto-mounting**: Automatically mounts unmounted USB devices when run with root privileges
- **Command-line parameters**: Fully configurable via command-line arguments

#### Usage

```bash
./sync_blockchain.sh -s <source_paths> -d <sync_dir> -p <usb_pattern> [-l <log_file>] [-u <pupID>]
```

#### Parameters

- `-s, --source`: Source paths to sync (comma-separated, required)
- `-d, --dir`: Directory name created on USB devices (required)
- `-p, --pattern`: USB device name pattern to match (required)
- `-l, --log`: Log file path (optional, default: `/var/log/blockchain_sync.log`)
- `-u, --pup`: PupID for machinectl operations (optional)
- `-h, --help`: Show help message

PupID can be determined on your dogebox by running `_dbxroot pup list`. If you're running an older version without that command, an alternative is to run `sudo machinectl list` to list out all running pup IDs, then reference folders within `/opt/dogebox/pups/storage/` to find the correct ID for Dogecoin Core - it will contain the `blocks` and `chainstate` folders.

#### Examples

```bash
# Real-world Dogecoin Core sync to Blockypuck devices (actual command in use)
./sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/chainstate/,/opt/dogebox/pups/storage/<pup-id>/blocks/' -d '.' -p 'blockypuck' -u 'pup-<pup-id>'

# Sync single blockchain data folder to USB devices containing "blockypuck"
./sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/chainstate' -d 'blockchain_data' -p 'blockypuck'

# Sync multiple blockchain paths to USB devices containing "BLOCKYPUCK"
./sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/blocks,/opt/dogebox/pups/storage/<pup-id>/chainstate' -d 'backup' -p 'BLOCKYPUCK'

# Sync directly to root of USB device (use . as sync directory)
./sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/blocks' -d '.' -p 'blockypuck'

# Run with sudo to enable automatic disk mounting
sudo ./sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/chainstate' -d 'blockchain_data' -p 'blockypuck'

# Custom log file location with PUP ID
./sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/blocks' -d 'sync' -p 'blockypuck' -l '/tmp/dogecoin_sync.log' -u 'pup-<pup-id>'

# Multiple Dogecoin Core directories with PUP management
./sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/chainstate/,/opt/dogebox/pups/storage/<pup-id>/blocks/' -d 'dogecoin_backup' -p 'blockypuck' -u 'pup-<pup-id>'
```

#### Installation

1. Enable cron if it isn't already. Add the following to `/opt/dogebox/nix/dogebox.nix`:
```nix
services.cron.enable = true;
```
Then run `_dbxroot nix rs`. (These may need to be run as root with `sudo su -`)

2. Copy the script to your device

3. Make script executable:
```bash
chmod +x sync_blockchain.sh
```

4. Create log directory (if using default log location):
```bash
sudo mkdir -p /var/log
sudo touch /var/log/blockchain_sync.log
```

5. Add to crontab with parameters (run every 30 minutes):
```bash
crontab -e
```

Add this line (replace with your actual paths and parameters):
```
*/30 * * * * /opt/blockypuck/scripts/sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/chainstate/,/opt/dogebox/pups/storage/<pup-id>/blocks/' -d '.' -p 'blockypuck' -u 'pup-<pup-id>'
```

Or run hourly with different PUP:
```
0 * * * * /opt/blockypuck/scripts/sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/blocks,/opt/dogebox/pups/storage/<pup-id>/chainstate' -d 'dogecoin_backup' -p 'blockypuck' -u 'pup-<pup-id>'
```

#### USB Device Naming

The script matches USB devices by either:
1. **Mount point name**: The directory name where the device is mounted
2. **Device label**: The filesystem label of the USB device

Name your USB devices to include the pattern word (e.g., "blockypuck"):
- BLOCKYPUCK_BACKUP_1
- DATA_BLOCKYPUCK_01
- blockypuck-storage

The match is case-insensitive. You can set the device label using:
- Linux: `sudo e2label /dev/sdX1 "blockypuck-backup"`
- FAT32: `sudo mlabel -i /dev/sdX1 ::BLOCKYPUCK`
- exFAT: `sudo exfatlabel /dev/sdX1 "blockypuck-backup"`

#### Monitoring

Check sync status:
```bash
tail -f /var/log/blockchain_sync.log
```

#### How Files Are Synced

The script syncs each source path to the USB device based on the `-d` parameter:

- **Directories**: Synced to `USB:/<sync_dir>/[directory_name]/`
  - Performs incremental sync (only copies new/changed files)
  - Example with `-d blockchain_data`: `/opt/app/test/folder1` → `USB:/blockchain_data/folder1/`
  - Example with `-d .`: `/opt/app/test/folder1` → `USB:/folder1/`
  
- **Files**: Copied directly to `USB:/<sync_dir>/`
  - Example with `-d blockchain_data`: `/opt/app/test/file1` → `USB:/blockchain_data/file1`
  - Example with `-d .`: `/opt/app/test/file1` → `USB:/file1`

#### Rsync Options Used

- `-r`: Recursive (copies directories)
- `-l`: Copy symlinks as symlinks
- `-p`: Preserve permissions
- `-t`: Preserve modification times
- `-D`: Preserve device and special files
- `-v`: Verbose output
- `--update`: Skip files that are newer on the destination
- `--no-owner`: Don't preserve file ownership (avoids chown errors)
- `--no-group`: Don't preserve group ownership
- `--exclude`: Excludes hidden files, temporary files and locks (.*. *.tmp, *.lock)
- `--log-file`: Creates detailed rsync log for debugging

#### Auto-mounting Feature

When run with root privileges (using `sudo`), the script will:
1. Detect unmounted USB devices using `lsblk` and `/dev/disk/by-label/`
2. Temporarily mount them to `/media/<device_name>` (read-only first for safety)
3. Check if they match the USB pattern
4. If matching, remount as read-write and perform the sync operation
5. Automatically unmount temporarily mounted devices when complete

This is useful for devices that are plugged in but not automatically mounted by the system. The script also handles devices identified by filesystem labels for more consistent device identification.

#### PUP Management Feature

When the `-u` or `--pup` parameter is provided with a PupID, the script will:

1. **Before syncing**: Execute `machinectl stop <pupID>` to stop the systemd-nspawn container
2. **Perform all sync operations** as normal
3. **After syncing**: Execute `_dbxroot nix rs` to restart the container

This feature is useful for:
- Ensuring data consistency by stopping containers before backup
- Automatically restarting services after sync completion
- Integration with systemd-nspawn container management workflows

**Example with PUP management**:
```bash
# Stop Dogecoin Core PUP, sync blockchain data, then restart
./sync_blockchain.sh -s '/opt/dogebox/pups/storage/<pup-id>/chainstate/,/opt/dogebox/pups/storage/<pup-id>/blocks/' -d '.' -p 'blockypuck' -u 'pup-<pup-id>'
```

**Error handling**: If either the stop or start command fails, the script will log the error and exit with status 1.

#### Troubleshooting

1. **No devices found**: 
   - Check USB device names or labels contain the pattern
   - Verify devices are properly formatted and readable
   - Try running with `sudo` for auto-mounting
   - Check debug messages in the log file for pattern matching details

2. **Permission denied**: 
   - Run with appropriate permissions or adjust paths
   - Ensure write permissions on USB device

3. **Insufficient space**: 
   - Script checks space before syncing and will skip devices without enough space
   - Check log for space requirements

4. **Already running**: 
   - Script uses lock file (`/var/run/blockchain_sync.lock`) to prevent multiple instances
   - Check for stale lock files if script isn't actually running

5. **Unmounted devices not detected**: 
   - Run with `sudo` to enable auto-mounting
   - Verify device is recognized by system (`lsblk` or `fdisk -l`)

6. **PUP won't stop/start**: 
   - Ensure correct PupID is provided
   - Verify `machinectl` and `_dbxroot` commands are available
   - Check system logs for container-related errors

#### Security Notes

- Script creates lock file in `/var/run/` to prevent concurrent executions
- Logs stored in `/var/log/` with detailed sync information
- Additional rsync logs created with `.rsync` suffix for debugging
- Consider encrypting USB devices for sensitive blockchain data
- Adjust rsync excludes based on your blockchain type and security requirements
- Script temporarily mounts devices read-only first for safety
- Automatic cleanup ensures temporary mounts are removed on exit