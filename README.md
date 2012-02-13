# ZFS Tools

Various scripts for administrating ZFS. Modeled after OpenSolaris time-slider

## Scripts

### cleanup_snapshots.sh

Cleans up zero-sized snapshots.

#### Usage

#### Crontab

    */20 * * * * /usr/local/sbin/zfstools/cleanup_snapshots.sh

### snapshot_mysql.sh

Snapshots a mysql server's databases.

#### Usage

Setup a `/root/.my.cnf` with the relevant information on where to connect to, with the proper username/password that has access to `FLUSH LOGS` and `FLUSH TABLES WITH READ LOCK`.

#### Crontab

    */10 * * * * env - HOME=/root /usr/local/sbin/zfstools/snapshot_mysql.sh DATASET

* DATASET - The dataset (filesystem/volume) that contains your mysql data

### auto-snapshot.rb

This will handle automatically snapshotting datasets similar to timeslider from opensolaris. Setup allows you to define your own intervals, snapshot names, and how many to keep for each interval.

### Usage

    /usr/local/sbin/zfstools/auto-snapshot.rb SNAPSHOT_NAME KEEP

* SNAPSHOT_NAME - what to name the snapshots. This is something such as `frequent`, `hourly`, `daily`, `weekly`, `monthly`, etc.
* KEEP - How many to keep for this SNAPSHOT_NAME. Older ones will be destroyed.

#### Crontab

    15,30,45 * * * * /usr/local/sbin/zfstools/auto-snapshot.rb frequent    3
    0 * * * *        /usr/local/sbin/zfstools/auto-snapshot.rb hourly     23
    7 0 * * *        /usr/local/sbin/zfstools/auto-snapshot.rb daily       6
    14 0 * * 7       /usr/local/sbin/zfstools/auto-snapshot.rb weekly      4
    28 0 1 * *       /usr/local/sbin/zfstools/auto-snapshot.rb monthly    12

#### Dataset setup

Only datasets with the `zfstools:auto-snapshot` property set to `true` will be snapshotted.

    zfs set zfstools:auto-snapshot=true DATASET

##### Overrides

You can override a child dataset to use, or not use auto snapshotting by settings its flag with the given interval.

    zfs set zfstools:auto-snapshot:weekly=false DATASET
