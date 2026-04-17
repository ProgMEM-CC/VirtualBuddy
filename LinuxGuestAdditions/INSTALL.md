# VirtualBuddy Linux Guest Additions

This package provides automatic filesystem resizing and dynamic display resolution for Linux virtual machines running in VirtualBuddy.

## Features

### Disk Resize
- **Automatic partition resize** using `growpart`
- **LVM support** - automatically extends physical volumes and logical volumes
- **LUKS support** - automatically resizes encrypted containers
- **LVM on LUKS** - full support for Fedora Workstation's default layout
- **Multiple filesystems** - supports ext4, XFS, and Btrfs
- **Safe operation** - only runs when free space is detected

### Dynamic Display Resolution
- **Automatic resolution switching** - resize the VM window to change guest resolution
- **spice-vdagent integration** - works with VirtualBuddy's SPICE display protocol
- **Fallback support** - xrandr-based fallback for protocol mismatches
- **Multi-desktop support** - works with GNOME, KDE, and other desktop environments

### User Experience
- **Desktop notifications** - shows notifications for disk operations
- **Colorful terminal output** - easy to follow installation and progress

## Supported Distributions

Any systemd-based Linux distribution, including:

- Fedora Workstation / Server
- Ubuntu
- Debian
- Arch Linux
- openSUSE
- Rocky Linux / AlmaLinux

## Installation

### Quick Install (from inside the VM)

```bash
# Download and extract
curl -L https://github.com/insidegui/VirtualBuddy/releases/latest/download/LinuxGuestAdditions.tar.gz | tar xz

# Install
cd LinuxGuestAdditions
sudo ./install.sh
```

### Manual Install

1. Copy the files to your VM
2. Run the installer:

```bash
sudo ./install.sh
```

The installer will:
- Check for required dependencies (`growpart`, `resize2fs`/`xfs_growfs`)
- Install the `virtualbuddy-growfs` script to `/usr/local/bin/`
- Install the `virtualbuddy-notify` script for desktop notifications
- Install and enable the systemd services
- Optionally run the resize immediately

## Desktop Notifications

On desktop distributions (GNOME, KDE, Xfce, etc.), the guest additions will show a notification when the disk has been resized:

- **Installation notification** - Shown when you run the installer
- **Resize notification** - Shown after login if the disk was resized during boot

The notification shows:
- Previous disk size
- New disk size

This makes it easy to confirm that your disk expansion worked, even though the resize happens early in the boot process.

**Requirements for notifications:**
- X11 or Wayland display server
- `notify-send` command (usually provided by `libnotify`)

## Dependencies

The following packages are required:

| Distribution | Package |
|-------------|---------|
| Fedora/RHEL | `cloud-utils-growpart` |
| Ubuntu/Debian | `cloud-guest-utils` |
| Arch Linux | `cloud-guest-utils` (AUR) |
| openSUSE | `growpart` |

Install with:

```bash
# Fedora
sudo dnf install cloud-utils-growpart

# Ubuntu/Debian
sudo apt install cloud-guest-utils

# Arch (from AUR)
yay -S cloud-guest-utils
```

## Usage

### Automatic (Recommended)

After installation, the service runs automatically on each boot. If VirtualBuddy has expanded the disk, the partition and filesystem will be resized.

### Manual

You can also run the resize manually:

```bash
# Run with verbose output
sudo virtualbuddy-growfs --verbose

# Dry run (show what would happen)
sudo virtualbuddy-growfs --dry-run --verbose
```

### Check Status

```bash
# Service status
systemctl status virtualbuddy-growfs

# View logs
journalctl -u virtualbuddy-growfs
```

## How It Works

1. **Detect storage stack** - Walks from root filesystem back through LVM, LUKS, to the partition
2. **Find free space** - Checks if partition can be grown
3. **Grow partition** - Uses `growpart` to extend the GPT partition
4. **Resize LUKS** - If encrypted, runs `cryptsetup resize`
5. **Resize LVM** - If using LVM:
   - `pvresize` to extend the physical volume
   - `lvextend` to extend the logical volume
6. **Resize filesystem** - Runs the appropriate tool:
   - ext4: `resize2fs`
   - XFS: `xfs_growfs`
   - Btrfs: `btrfs filesystem resize max`

## LVM Support

For distributions using LVM (with or without encryption), the guest additions automatically handle:

1. Extending the physical volume (`pvresize`)
2. Extending the logical volume (`lvextend -l +100%FREE`)
3. Resizing the filesystem

This works for both:
- **LVM on partition** - direct partition → LVM → filesystem
- **LVM on LUKS** - partition → LUKS → LVM → filesystem (Fedora Workstation default)

## LUKS Encrypted Disks

For LUKS-encrypted root partitions (common with Fedora Workstation), the guest additions will:

1. Grow the GPT partition containing LUKS
2. Run `cryptsetup resize` to expand the LUKS container
3. If LVM is on top of LUKS, extend PV and LV
4. Resize the inner filesystem

No manual intervention required!

## Uninstall

```bash
sudo ./uninstall.sh
```

Or manually:

```bash
# Disable services
sudo systemctl disable --now virtualbuddy-growfs.service
sudo systemctl --global disable virtualbuddy-notify.service
sudo systemctl --global disable virtualbuddy-resolution.service

# Remove files
sudo rm /etc/systemd/system/virtualbuddy-growfs.service
sudo rm /etc/systemd/user/virtualbuddy-notify.service
sudo rm /etc/systemd/user/virtualbuddy-resolution.service
sudo rm /usr/local/bin/virtualbuddy-growfs
sudo rm /usr/local/bin/virtualbuddy-notify
sudo rm /usr/local/bin/virtualbuddy-resolution
sudo rm -rf /etc/virtualbuddy

# Reload systemd
sudo systemctl daemon-reload
```

## Dynamic Display Resolution

### How It Works

VirtualBuddy uses the SPICE display protocol to communicate resolution changes to the guest. When you resize the VM window in VirtualBuddy:

1. VirtualBuddy sends the new resolution via the SPICE agent channel
2. The `spice-vdagent` daemon in the guest receives the request
3. The resolution is automatically applied to your display

### Requirements

- **spice-vdagent** - The guest additions installer will attempt to install this automatically
- **VirtualBuddy setting** - Enable "Automatically Configure Display" in VM settings

### Manual Resolution Control

If automatic resolution isn't working, you can use the included helper script:

```bash
# List available resolutions
virtualbuddy-resolution --list

# Set a specific resolution
virtualbuddy-resolution --set 1920x1080

# Auto-detect best resolution (X11 only)
virtualbuddy-resolution --auto
```

### Desktop Environment Support

| Desktop | X11 | Wayland |
|---------|-----|---------|
| GNOME | ✓ spice-vdagent | ✓ Native |
| KDE Plasma | ✓ spice-vdagent | ✓ Native |
| Xfce | ✓ spice-vdagent + fallback | N/A |
| MATE | ✓ spice-vdagent + fallback | N/A |
| Sway/wlroots | N/A | ✓ wlr-randr |

**Note:** GNOME and KDE Plasma on Wayland handle resolution changes natively through their compositors. The fallback script is primarily for X11 sessions and non-GNOME/KDE desktops.

### Known Issues

Some versions of spice-vdagent may have protocol compatibility issues with the Virtualization.framework SPICE implementation. If you see errors like "invalid message size for VDAgentMonitorsConfig" in the journal, the fallback service will automatically apply an xrandr fix.

## Troubleshooting

### "growpart not found"

Install the cloud-utils package for your distribution (see Dependencies section).

### Partition not growing

Check if there's actually free space after the partition:

```bash
sudo parted /dev/vda print free
```

If the "Free Space" at the end is very small (< 1MB), VirtualBuddy may not have resized the disk yet.

### LUKS resize fails

Ensure the LUKS container is unlocked (you should be booted into the system). The resize requires the container to be open.

### Filesystem resize fails

Check the filesystem type and ensure the appropriate tools are installed:

```bash
# Check filesystem type
df -T /

# For ext4
sudo apt install e2fsprogs  # or dnf install e2fsprogs

# For XFS
sudo apt install xfsprogs   # or dnf install xfsprogs

# For Btrfs
sudo apt install btrfs-progs  # or dnf install btrfs-progs
```

### LVM not detected

Ensure LVM tools are installed:

```bash
# Fedora/RHEL
sudo dnf install lvm2

# Ubuntu/Debian
sudo apt install lvm2
```

Check your storage stack:

```bash
# View LVM layout
sudo lsblk
sudo lvs
sudo pvs
sudo vgs
```

### LV not extending

If the logical volume isn't growing, check for free space in the volume group:

```bash
sudo vgs
```

If `VFree` is 0, the physical volume may not have been resized. Try running manually:

```bash
sudo pvresize /dev/mapper/luks-xxx  # or your PV device
sudo lvextend -l +100%FREE /dev/mapper/fedora-root
```

### Resolution not changing

1. Check if spice-vdagent is running:
```bash
systemctl status spice-vdagentd
```

2. Check for protocol errors:
```bash
journalctl -u spice-vdagentd | grep -i error
```

3. Try the manual resolution script:
```bash
virtualbuddy-resolution --auto
# or
virtualbuddy-resolution --set 1920x1080
```

4. For Wayland sessions with GNOME or KDE, resolution should work natively. If not, check your compositor settings.

### Resolution fallback not working

The fallback service only runs on X11 sessions. For Wayland, resolution changes are handled by the compositor.

Check if the fallback service is running:
```bash
systemctl --user status virtualbuddy-resolution
```

## License

MIT License - Same as VirtualBuddy
