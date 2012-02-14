.PHONY: install

install:
	install -d -m 0700 /usr/local/sbin/zfstools
	install -d -m 0700 /usr/local/sbin/zfstools/lib
	install -m 0700 cleanup_snapshots.sh /usr/local/sbin/zfstools/
	install -m 0700 snapshot_mysql.sh /usr/local/sbin/zfstools/
	install -m 0700 auto-snapshot.rb /usr/local/sbin/zfstools/
	install -m 0700 lib/zfstools.rb /usr/local/sbin/zfstools/lib/
