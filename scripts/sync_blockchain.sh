#!/usr/bin/env bash

# Function to display usage
show_usage() {
    echo "Usage: $0 -s <source_paths> -d <sync_dir> -p <usb_pattern> [-l <log_file>] [-u <pupID>]"
    echo ""
    echo "Options:"
    echo "  -s, --source      Source paths to sync (comma-separated, required)"
    echo "  -d, --dir         Directory name on USB devices (required)"
    echo "  -p, --pattern     USB device name pattern (required)"
    echo "  -l, --log         Log file path (default: /var/log/blockchain_sync.log)"
    echo "  -u, --pup         PupID for machinectl operations (optional)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s '/path/to/folder1,/path/to/folder2' -d 'blockchain_data' -p 'BLOCKCHAIN'"
    echo "  $0 --source '/opt/app/data' --dir 'backup' --pattern 'BLOCKYPUCK' --log '/tmp/sync.log' --pup 'mypup'"
    exit 1
}

# Default values
LOG_FILE="/var/log/blockchain_sync.log"
LOCK_FILE="/var/run/blockchain_sync.lock"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--source)
            IFS=',' read -ra SOURCE_PATHS <<< "$2"
            shift 2
            ;;
        -d|--dir)
            SYNC_DIR="$2"
            shift 2
            ;;
        -p|--pattern)
            USB_NAME_PATTERN="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -u|--pup)
            PUP_ID="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Validate required arguments
if [ -z "${SOURCE_PATHS[*]}" ] || [ -z "$SYNC_DIR" ] || [ -z "$USB_NAME_PATTERN" ]; then
    echo "Error: Missing required arguments"
    show_usage
fi

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"  # Also print to stdout
}

# Function to send error notifications (optional - configure as needed)
send_notification() {
    # Uncomment and configure if you want email notifications
    # echo "$1" | mail -s "Blockchain Sync Error" admin@example.com
    log_message "NOTIFICATION: $1"
}

# Check if script is already running
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        log_message "Script already running with PID $PID. Exiting."
        exit 0
    else
        log_message "Removing stale lock file"
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Stop PUP if pupID is provided
if [ -n "$PUP_ID" ]; then
    log_message "Stopping PUP: $PUP_ID"
    if ! machinectl stop "$PUP_ID"; then
        log_message "ERROR: Failed to stop PUP $PUP_ID"
        send_notification "Failed to stop PUP $PUP_ID before sync"
        exit 1
    fi
    log_message "Successfully stopped PUP: $PUP_ID"
    PUP_STOPPED="true"
fi

log_message "Starting blockchain sync process"

# Arrays to track mounted disks for cleanup
TEMPORARILY_MOUNTED=()

# Function to find and mount unmounted disks
find_and_mount_unmounted_disks() {
    log_message "Looking for unmounted disks to temporarily mount..."
    
    # Ensure /media directory exists
    if [ ! -d "/media" ]; then
        mkdir -p /media 2>/dev/null || {
            log_message "WARNING: Could not create /media directory"
            return
        }
    fi
    
    # Find unmounted block devices
    local unmounted_devices=()
    
    # Use lsblk to find unmounted devices
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        
        local device=$(echo "$line" | awk '{print $1}')
        local type=$(echo "$line" | awk '{print $2}')
        local mountpoint=$(echo "$line" | awk '{print $3}')
        
        # Skip if already mounted
        [ -n "$mountpoint" ] && continue
        
        # Only process disks and partitions
        if [[ "$type" == "disk" ]] || [[ "$type" == "part" ]]; then
            unmounted_devices+=("/dev/$device")
        fi
    done < <(lsblk -rno NAME,TYPE,MOUNTPOINT 2>/dev/null)
    
    # Try to mount each unmounted device
    for device in "${unmounted_devices[@]}"; do
        local device_name=$(basename "$device")
        local mount_point="/media/${device_name}"
        
        # Create mount point
        if mkdir -p "$mount_point" 2>/dev/null; then
            # Try to mount the device (read-only first for safety)
            if mount -r "$device" "$mount_point" 2>/dev/null; then
                log_message "Temporarily mounted $device to $mount_point (read-only)"
                TEMPORARILY_MOUNTED+=("$mount_point")
                
                # Check if it contains our pattern
                local device_label=$(basename "$mount_point")
                if echo "$device_label" | grep -qi "$USB_NAME_PATTERN"; then
                    # Remount as read-write if it matches our pattern
                    if mount -o remount,rw "$mount_point" 2>/dev/null; then
                        log_message "Remounted $mount_point as read-write"
                    fi
                fi
            else
                # Clean up failed mount point
                rmdir "$mount_point" 2>/dev/null
            fi
        fi
    done
    
    if [ ${#TEMPORARILY_MOUNTED[@]} -gt 0 ]; then
        log_message "Mounted ${#TEMPORARILY_MOUNTED[@]} unmounted disk(s)"
    fi
}

# Function to unmount temporarily mounted disks
cleanup_temporary_mounts() {
    if [ ${#TEMPORARILY_MOUNTED[@]} -gt 0 ]; then
        log_message "Cleaning up temporarily mounted disks..."
        for mount_point in "${TEMPORARILY_MOUNTED[@]}"; do
            if umount "$mount_point" 2>/dev/null; then
                log_message "Unmounted $mount_point"
                rmdir "$mount_point" 2>/dev/null
            else
                log_message "WARNING: Failed to unmount $mount_point"
            fi
        done
    fi
}

# Set up cleanup trap for both lock file and temporary mounts
cleanup_all() {
    cleanup_temporary_mounts
    
    # Start PUP if it was stopped and pupID is provided
    if [ -n "$PUP_ID" ] && [ -n "$PUP_STOPPED" ]; then
        log_message "Script terminated - restarting PUP: $PUP_ID"
        if ! _dbxroot nix rs; then
            log_message "ERROR: Failed to restart PUP $PUP_ID during cleanup"
        else
            log_message "Successfully restarted PUP: $PUP_ID during cleanup"
        fi
    fi
    
    rm -f "$LOCK_FILE"
}
trap cleanup_all EXIT

# Check if running as root (recommended for mounting)
if [ "$EUID" -eq 0 ]; then
    find_and_mount_unmounted_disks
else
    log_message "Not running as root - skipping automatic disk mounting"
    log_message "For automatic disk mounting, run with sudo"
fi

log_message "Starting blockchain sync process"

# Validate all source paths exist
MISSING_PATHS=()
for SOURCE_PATH in "${SOURCE_PATHS[@]}"; do
    if [ ! -e "$SOURCE_PATH" ]; then
        MISSING_PATHS+=("$SOURCE_PATH")
        log_message "ERROR: Source path $SOURCE_PATH does not exist"
    fi
done

if [ ${#MISSING_PATHS[@]} -gt 0 ]; then
    log_message "ERROR: Some source paths do not exist: ${MISSING_PATHS[*]}"
    send_notification "Blockchain sync failed: Source paths not found: ${MISSING_PATHS[*]}"
    exit 1
fi

# Calculate total size of all source paths
calculate_total_size() {
    local total=0
    for path in "${SOURCE_PATHS[@]}"; do
        if [ -e "$path" ]; then
            size=$(du -s "$path" 2>/dev/null | awk '{print $1}')
            total=$((total + size))
        fi
    done
    echo $total
}

# Find all mounted USB devices
DEVICES_SYNCED=0
DEVICES_FAILED=0

# Look for USB devices in common mount points
for MOUNT_POINT in /media/* /mnt/* /run/media/*/* ; do
    if [ ! -d "$MOUNT_POINT" ]; then
        continue
    fi
    
    # Get device info
    DEVICE_NAME=$(basename "$MOUNT_POINT")
    
    # Check if device name contains the pattern (case insensitive)
    log_message "DEBUG: Checking device '$DEVICE_NAME' against pattern '$USB_NAME_PATTERN'"
    if echo "$DEVICE_NAME" | grep -qi "$USB_NAME_PATTERN"; then
        log_message "DEBUG: Device '$DEVICE_NAME' matches pattern '$USB_NAME_PATTERN'"
        # Check if mount point is actually mounted
        if mountpoint -q "$MOUNT_POINT"; then
            log_message "Found matching USB device: $DEVICE_NAME at $MOUNT_POINT"
            
            # Create destination directory if it doesn't exist
            DEST_PATH="$MOUNT_POINT/$SYNC_DIR"
            
            if ! mkdir -p "$DEST_PATH" 2>/dev/null; then
                log_message "ERROR: Cannot create directory on $DEVICE_NAME"
                DEVICES_FAILED=$((DEVICES_FAILED + 1))
                continue
            fi
            
            # Check available space on device
            AVAILABLE_SPACE=$(df "$MOUNT_POINT" | awk 'NR==2 {print $4}')
            TOTAL_SOURCE_SIZE=$(calculate_total_size)
            
            if [ "$AVAILABLE_SPACE" -lt "$TOTAL_SOURCE_SIZE" ]; then
                log_message "WARNING: Insufficient space on $DEVICE_NAME (Available: ${AVAILABLE_SPACE}K, Required: ${TOTAL_SOURCE_SIZE}K)"
                send_notification "Insufficient space on USB device $DEVICE_NAME"
                DEVICES_FAILED=$((DEVICES_FAILED + 1))
                continue
            fi
            
            # Perform rsync for each source path
            log_message "Starting sync to $DEVICE_NAME"
            SYNC_SUCCESS=true
            
            for SOURCE_PATH in "${SOURCE_PATHS[@]}"; do
                # Get the basename of the source path
                BASENAME=$(basename "$SOURCE_PATH")
                
                # Determine if source is a file or directory
                if [ -f "$SOURCE_PATH" ]; then
                    # For files, sync directly to the destination directory
                    TARGET_PATH="$DEST_PATH/"
                    log_message "Syncing file: $SOURCE_PATH to $TARGET_PATH"
                    
                    if ! rsync -rlptDv \
                             --update \
                             --no-owner --no-group \
                             --exclude=".*" \
                             --exclude="*.tmp" \
                             --exclude="*.lock" \
                             --log-file="${LOG_FILE}.rsync" \
                             "$SOURCE_PATH" "$TARGET_PATH" 2>&1 | tee -a "$LOG_FILE"; then
                        log_message "ERROR: Failed to sync file $SOURCE_PATH"
                        SYNC_SUCCESS=false
                    fi
                    
                elif [ -d "$SOURCE_PATH" ]; then
                    # For directories, create subdirectory in destination
                    TARGET_PATH="$DEST_PATH/$BASENAME"
                    mkdir -p "$TARGET_PATH"
                    log_message "Syncing directory: $SOURCE_PATH to $TARGET_PATH"
                    
                    if ! rsync -rlptDv \
                             --update \
                             --no-owner --no-group \
                             --exclude=".*" \
                             --exclude="*.tmp" \
                             --exclude="*.lock" \
                             --log-file="${LOG_FILE}.rsync" \
                             "$SOURCE_PATH/" "$TARGET_PATH/" 2>&1 | tee -a "$LOG_FILE"; then
                        log_message "ERROR: Failed to sync directory $SOURCE_PATH"
                        SYNC_SUCCESS=false
                    fi
                else
                    log_message "WARNING: $SOURCE_PATH is neither a file nor a directory, skipping"
                fi
            done
            
            if [ "$SYNC_SUCCESS" = true ]; then
                log_message "Successfully synced all paths to $DEVICE_NAME"
                
                # Sync filesystem to ensure data is written
                sync
                
                # Create a timestamp file with list of synced paths
                {
                    echo "Last sync: $(date)"
                    echo "Synced paths:"
                    for path in "${SOURCE_PATHS[@]}"; do
                        echo "  - $path"
                    done
                } > "$DEST_PATH/.last_sync"
                
                DEVICES_SYNCED=$((DEVICES_SYNCED + 1))
            else
                log_message "ERROR: Some syncs failed for $DEVICE_NAME"
                send_notification "Partial sync failure for USB device $DEVICE_NAME"
                DEVICES_FAILED=$((DEVICES_FAILED + 1))
            fi
        else
            log_message "Device $DEVICE_NAME found but not mounted"
        fi
    else
        log_message "DEBUG: Device '$DEVICE_NAME' does not match pattern '$USB_NAME_PATTERN'"
    fi
done

# Also check for devices by label (useful for consistently labeled USBs)
for LABEL_PATH in /dev/disk/by-label/*; do
    if [ ! -e "$LABEL_PATH" ]; then
        continue
    fi
    
    LABEL_NAME=$(basename "$LABEL_PATH")
    
    log_message "DEBUG: Checking label '$LABEL_NAME' against pattern '$USB_NAME_PATTERN'"
    if echo "$LABEL_NAME" | grep -qi "$USB_NAME_PATTERN"; then
        log_message "DEBUG: Label '$LABEL_NAME' matches pattern '$USB_NAME_PATTERN'"
        # Get the actual device
        DEVICE=$(readlink -f "$LABEL_PATH")
        log_message "DEBUG: Label '$LABEL_NAME' resolves to device '$DEVICE'"
        
        # Check if it's mounted
        MOUNT_POINT=$(lsblk -no MOUNTPOINT "$DEVICE" 2>/dev/null | head -n1)
        log_message "DEBUG: Device '$DEVICE' mount point: '$MOUNT_POINT'"
        
        # If not mounted, try to mount it
        if [ -z "$MOUNT_POINT" ] || [ "$MOUNT_POINT" = "" ]; then
            log_message "Device $DEVICE (label: $LABEL_NAME) is not mounted, attempting to mount..."
            
            # Create a mount point based on the label
            SAFE_LABEL=$(echo "$LABEL_NAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')
            MOUNT_POINT="/media/${SAFE_LABEL}"
            
            if mkdir -p "$MOUNT_POINT" 2>/dev/null; then
                if mount "$DEVICE" "$MOUNT_POINT" 2>/dev/null; then
                    log_message "Successfully mounted $DEVICE to $MOUNT_POINT"
                    TEMPORARILY_MOUNTED+=("$MOUNT_POINT")
                else
                    log_message "ERROR: Failed to mount $DEVICE to $MOUNT_POINT"
                    rmdir "$MOUNT_POINT" 2>/dev/null
                    continue
                fi
            else
                log_message "ERROR: Failed to create mount point $MOUNT_POINT"
                continue
            fi
        fi
        
        if [ -n "$MOUNT_POINT" ] && [ "$MOUNT_POINT" != "" ]; then
            log_message "Found labeled device: $LABEL_NAME at $MOUNT_POINT"
            
            # Check if mounted read-only and remount as read-write
            if mount | grep -q "$MOUNT_POINT.*[(,]ro[,)]"; then
                log_message "Device is mounted read-only, remounting as read-write..."
                if mount -o remount,rw "$MOUNT_POINT" 2>/dev/null; then
                    log_message "Successfully remounted $MOUNT_POINT as read-write"
                else
                    log_message "ERROR: Failed to remount $MOUNT_POINT as read-write"
                    DEVICES_FAILED=$((DEVICES_FAILED + 1))
                    continue
                fi
            fi
            
            DEST_PATH="$MOUNT_POINT/$SYNC_DIR"
            
            if ! mkdir -p "$DEST_PATH" 2>/dev/null; then
                log_message "ERROR: Cannot create directory on $LABEL_NAME"
                DEVICES_FAILED=$((DEVICES_FAILED + 1))
                continue
            fi
            
            log_message "Starting sync to labeled device $LABEL_NAME"
            
            SYNC_SUCCESS=true
            
            for SOURCE_PATH in "${SOURCE_PATHS[@]}"; do
                    BASENAME=$(basename "$SOURCE_PATH")
                    
                    if [ -f "$SOURCE_PATH" ]; then
                        TARGET_PATH="$DEST_PATH/"
                        log_message "Syncing file: $SOURCE_PATH to $TARGET_PATH"
                        
                        if ! rsync -rlptDv \
                                 --update \
                                 --no-owner --no-group \
                                 --exclude=".*" \
                                 --exclude="*.tmp" \
                                 --exclude="*.lock" \
                                 --log-file="${LOG_FILE}.rsync" \
                                 "$SOURCE_PATH" "$TARGET_PATH" 2>&1 | tee -a "$LOG_FILE"; then
                            log_message "ERROR: Failed to sync file $SOURCE_PATH"
                            SYNC_SUCCESS=false
                        fi
                        
                    elif [ -d "$SOURCE_PATH" ]; then
                        TARGET_PATH="$DEST_PATH/$BASENAME"
                        mkdir -p "$TARGET_PATH"
                        log_message "Syncing directory: $SOURCE_PATH to $TARGET_PATH"
                        
                        if ! rsync -rlptDv \
                                 --update \
                                 --no-owner --no-group \
                                 --exclude=".*" \
                                 --exclude="*.tmp" \
                                 --exclude="*.lock" \
                                 --log-file="${LOG_FILE}.rsync" \
                                 "$SOURCE_PATH/" "$TARGET_PATH/" 2>&1 | tee -a "$LOG_FILE"; then
                            log_message "ERROR: Failed to sync directory $SOURCE_PATH"
                            SYNC_SUCCESS=false
                        fi
                    else
                        log_message "WARNING: $SOURCE_PATH is neither a file nor a directory, skipping"
                    fi
                done
                
                if [ "$SYNC_SUCCESS" = true ]; then
                    log_message "Successfully synced all paths to $LABEL_NAME"
                    sync
                    {
                        echo "Last sync: $(date)"
                        echo "Synced paths:"
                        for path in "${SOURCE_PATHS[@]}"; do
                            echo "  - $path"
                        done
                    } > "$DEST_PATH/.last_sync"
                    DEVICES_SYNCED=$((DEVICES_SYNCED + 1))
                else
                    log_message "ERROR: Some syncs failed for $LABEL_NAME"
                    send_notification "Partial sync failure for USB device $LABEL_NAME"
                    DEVICES_FAILED=$((DEVICES_FAILED + 1))
                fi
        fi  # Close the mount point check
    else
        log_message "DEBUG: Label '$LABEL_NAME' does not match pattern '$USB_NAME_PATTERN'"
    fi
done

# Summary
if [ "$DEVICES_SYNCED" -eq 0 ] && [ "$DEVICES_FAILED" -eq 0 ]; then
    log_message "No matching USB devices found"
else
    log_message "Sync complete. Devices synced: $DEVICES_SYNCED, Failed: $DEVICES_FAILED"
    
    if [ "$DEVICES_FAILED" -gt 0 ]; then
        send_notification "Blockchain sync completed with errors. Synced: $DEVICES_SYNCED, Failed: $DEVICES_FAILED"
    fi
fi

# Start PUP if pupID is provided
if [ -n "$PUP_ID" ]; then
    log_message "Starting PUP: $PUP_ID"
    if ! _dbxroot nix rs; then
        log_message "ERROR: Failed to start PUP $PUP_ID with _dbxroot nix rs"
        send_notification "Failed to start PUP $PUP_ID after sync"
        exit 1
    fi
    log_message "Successfully started PUP: $PUP_ID"
    PUP_STOPPED=""
fi

log_message "Blockchain sync process completed"