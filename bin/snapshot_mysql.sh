#! /bin/sh

snapshot_format_default="%Y-%m-%dT%H:%M:%S"
snapshot_format=$snapshot_format_default

usage() {
  echo "Usage: $0 [-f format] dataset" >&2
  echo "\t-f format - Format for the snapshot." >&2
  echo "\t          - Default: $snapshot_format_default" >&2
}

while getopts f: opt; do
  case "$opt" in
    f)
      snapshot_format="$OPTARG" ;;
    *) ;;
  esac
done

shift $(($OPTIND - 1))

if [ $# -ne 1 ]; then
  usage
  exit 1
fi

dataset=$1

snapshot=$(date "+${snapshot_format}")

QUERY=$(cat <<_SQL_
  FLUSH LOGS;
  FLUSH TABLES WITH READ LOCK;
  SYSTEM zfs snapshot -r ${dataset}@${snapshot};
  UNLOCK TABLES;
_SQL_
)

mysql -e "$QUERY"
