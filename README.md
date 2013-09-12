# ZFS Tools

Various scripts for administrating ZFS. Modeled after [time-sliderd](http://mail.opensolaris.org/pipermail/zfs-discuss/2009-November/033882.html) and [ZFS Automatic Snapshots](https://blogs.oracle.com/timf/entry/zfs_automatic_snapshots_0_12) from OpenSolaris

## Setup

Install the gem.

## Production version

    gem install zfstools

### Development version

    rake install

Setup crontab entries for scripts wanted. See below.

## Scripts

### zfs-auto-snapshot

This will handle automatically snapshotting datasets similar to time-sliderd from OpenSolaris. Setup allows you to define your own intervals, snapshot names, and how many to keep for each interval. Zero-sized snapshots will automatically be cleaned up.

### Usage

    /usr/local/bin/zfs-auto-snapshot INTERVAL KEEP

* INTERVAL - The interval for the snapshot. This is something such as `frequent`, `hourly`, `daily`, `weekly`, `monthly`, etc.
* KEEP - How many to keep for this INTERVAL. Older ones will be destroyed.

#### Crontab

    15,30,45 * * * * root /usr/local/bin/zfs-auto-snapshot frequent  4
    0        * * * * root /usr/local/bin/zfs-auto-snapshot hourly   24
    7        0 * * * root /usr/local/bin/zfs-auto-snapshot daily     7
    14       0 * * 7 root /usr/local/bin/zfs-auto-snapshot weekly    4
    28       0 1 * * root /usr/local/bin/zfs-auto-snapshot monthly  12

#### Dataset setup

Only datasets with the `com.sun:auto-snapshot` property set to `true` will be snapshotted.

    zfs set com.sun:auto-snapshot=true DATASET

##### MySQL Support

Setting a MySQL dataset's property to `mysql` will hook it into the `zfs-snapshot-mysql` script. See its section for setup instructions.

    zfs set com.sun:auto-snapshot=mysql DATASET

##### PostgreSQL Support

Setting a PostgreSQL dataset's property to `postgresql` will cause zfs-auto-snapshot to put postgresql in online backup mode for the snapshot.

    zfs set com.sun:auto-snapshot=postgresql DATASET

The user executing `zfs-auto-snapshot` will require passwordless login to the `postgres` database and will require either REPLICATION or SUPERUSER privileges. The easiest approach is to set up a trust or ident record in your pg_hba.conf. The `zfs-auto-snapshot` script will execute pg_start_backup() prior to saving the snapshot and execute pg_stop_backup() afterwards. 

##### Overrides

You can override a child dataset to use, or not use auto snapshotting by settings its flag with the given interval.

    zfs set com.sun:auto-snapshot:weekly=false DATASET

### zfs-snapshot-mysql

Snapshots a mysql server's databases. This requires that mysql's `datadir`/`innodb_data_home_dir`/`innodb_log_group_home_dir` be a ZFS dataset.

#### Example MySQL+ZFS Setup

##### Datasets

    tank/db/mysql
    tank/db/mysql/bin-log
    tank/db/mysql/data
    tank/db/mysql/innodb
    tank/db/mysql/innodb/data
    tank/db/mysql/innodb/log

##### ZFS Settings

These settings should be set before importing any data.

    zfs set primarycache=metadata tank/db/mysql/innodb
    zfs set recordsize=16K tank/db/mysql/innodb/data
    zfs set recordsize=8K tank/db/mysql/data
    zfs set compression=lzjb tank/db/mysql/data

##### MySQL Settings

    innodb_data_home_dir = /tank/db/mysql/innodb/data
    innodb_log_group_home_dir = /tank/db/mysql/innodb/log
    datadir = /tank/db/mysql/data
    log-bin = /tank/db/mysql/bin-log/mysql-bin

#### Script Usage

Setup a `/root/.my.cnf` with the relevant information on where to connect to, with the proper username/password that has access to `FLUSH LOGS` and `FLUSH TABLES WITH READ LOCK`.
The `zfs-auto-snapshot` script will automatically flush the tables before saving the snapshots.

### zfs-cleanup-snapshots

Cleans up zero-sized snapshots. This ignores snapshots created by `zfs-auto-snapshot` as it handles zero-sized in its own special way.

#### Usage

#### Crontab

    */20 * * * * /usr/local/bin/zfs-cleanup-snapshots
