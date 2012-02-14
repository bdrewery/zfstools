#! /usr/bin/env ruby

require 'getoptlong'
require './lib/zfstools'

opts = GetoptLong.new(
  [ "--utc",       "-u",           GetoptLong::NO_ARGUMENT ],
  [ "--dry-run",   "-n",           GetoptLong::NO_ARGUMENT ]
)

$use_utc = false
$dry_run = false
opts.each do |opt, arg|
  case opt
  when '--utc'
    $use_utc = true
  when '--dry-run'
    $dry_run = true
  end
end


def usage
  puts <<-EOF
Usage: $0 [-un] <INTERVAL> <KEEP>
  EOF
  format = "    %-15s %s"
  puts format % ["-u", "Use UTC for snapshots."]
  puts format % ["-n", "Do a dry-run. Nothing is committed. Only show what would be done."]
  puts format % ["INTERVAL", "The interval to snapshot."]
  puts format % ["KEEP", "How many snapshots to keep."]
  exit
end

usage if ARGV.length < 2

interval=ARGV[0]
keep=ARGV[1].to_i

# Generate new snapshots
do_new_snapshots(interval) if keep > 0

# Delete expired
cleanup_expired_snapshots(interval, keep)
