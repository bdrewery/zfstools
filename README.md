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

Setup a `/root/.my.cnf` with the relevant informatnion on where to connect to, with the proper username/password that has access to `FLUSH LOGS` and `FLUSH TABLES WITH READ LOCK`.

#### Crontab

    */10 * * * * env - HOME=/root /usr/local/sbin/zfstools/snapshot_mysql.sh
