ZFS Tools
====================

Various scripts for administrating ZFS

Scripts
---------------------

### cleanup_snapshots.sh

Cleans up zero-sized snapshots.

### Usage

Add to crontab:

    */20 * * * * /usr/local/bin/zfs-tools/cleanup_snapshots.sh

