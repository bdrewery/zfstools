#! /bin/sh

# Find all zero-sized snapshots
snapshots=$(zfs list -H -t snapshot|awk '$2 == 0 {print $1}')
for snapshot in $snapshots; do
  # Get the current size of this snapshot as deleting other snapshots
  # may have shifted some of the size to this snapshot
  size=$(zfs get -Hp -o value used $snapshot)
  if [ $size -eq 0 ]; then
    echo "Destroying size:$size snapshot: $snapshot"
    zfs destroy -d $snapshot
  fi
done
