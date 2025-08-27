# Scripts

This directory contains utility scripts for the Blockypuck project.

## Available Scripts

### sync_blockchain.sh

Automatically syncs multiple folders and files to USB devices using rsync.

#### Features

- **Multiple source paths**: Sync multiple folders and individual files
- Auto-detects USB devices containing specific keyword in name
- **Automatic disk mounting**: Finds and mounts unmounted disks when run as root
- Handles devices being plugged/unplugged dynamically  
- Comprehensive logging and error handling
- Prevents multiple simultaneous runs
- Checks available space before syncing
- Supports both mount point and label-based detection
- **PUP management**: Optional integration with systemd-nspawn containers via machinectl
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

PupID can be determined on your dogebox by running `_dbxroot pup list`. If that hasn't been added yet, an alternative is to run `sudo machinectl list` to list out all running pup IDs, then referencing folders within `/opt/dogebox/pups/storage/` to find the correct ID for Dogecoin Core - It will have the `blocks` and `chainstate` folders.

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

1. Enable cron if it isn't already. Add the following to `/opt/dogebox/nix/dogebox.nix`
```
    services.cron.enable = true;
```
Then run `_dbxroot nix rs`. (These may nede to be run as root with `sudo su -`)

2. Make script executable:
```bash
chmod +x sync_blockchain.sh
```

3. Create log directory (if using default log location):
```bash
sudo mkdir -p /var/log
sudo touch /var/log/blockchain_sync.log
```

4. Add to crontab with parameters (run every 30 minutes):
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

Name your USB devices to include the pattern word (default: "BLOCKYPUCK"):
- BLOCKYPUCK_BACKUP_1
- DATA_BLOCKYPUCK_01
- blockypuck-storage

The match is case-insensitive.

#### Monitoring

Check sync status:
```bash
tail -f /var/log/blockchain_sync.log
```

#### How Files Are Synced

The script syncs each source path to the USB device:

- **Directories**: Synced to `USB:/blockchain_data/[directory_name]/`
  - Performs incremental sync (only copies new/changed files)
  - Example: `/opt/app/test/folder1` → `USB:/blockchain_data/folder1/`
  
- **Files**: Copied directly to `USB:/blockchain_data/`
  - Example: `/opt/app/test/file1` → `USB:/blockchain_data/file1`

#### Rsync Options Used

- `-r`: Recursive (copies directories)
- `-l`: Copy symlinks as symlinks
- `-p`: Preserve permissions
- `-t`: Preserve modification times
- `-D`: Preserve device and special files
- `-v`: Verbose output
- `--no-owner`: Don't preserve file ownership (avoids chown errors)
- `--no-group`: Don't preserve group ownership
- `--exclude`: Excludes temporary files and locks

#### Auto-mounting Feature

When run with root privileges (using `sudo`), the script will:
1. Detect unmounted USB devices
2. Temporarily mount them to `/media/<device_name>`
3. Check if they match the USB pattern
4. Perform the sync operation
5. Automatically unmount temporarily mounted devices when complete

This is useful for devices that are plugged in but not automatically mounted by the system.

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

1. **No devices found**: Check USB device names contain the pattern
2. **Permission denied**: Run with appropriate permissions or adjust paths
3. **Insufficient space**: Script checks space before syncing
4. **Already running**: Script uses lock file to prevent multiple instances
5. **Unmounted devices not detected**: Run with `sudo` to enable auto-mounting

#### Security Notes

- Script creates lock file in `/var/run/`
- Logs stored in `/var/log/`
- Consider encrypting USB devices for sensitive blockchain data
- Adjust rsync excludes based on your blockchain type