#! /usr/bin/env ruby

require 'getoptlong'

opts = GetoptLong.new(
  [ "--utc",   "-u",           GetoptLong::NO_ARGUMENT ]
)

$use_utc = false
opts.each do |opt, arg|
  case opt
  when '--utc'
    $use_utc = true
  end
end


def usage
  puts <<-EOF
Usage: $0 [-u] <INTERVAL> <KEEP>
  EOF
  format = "    %-15s %s"
  puts format % ["-u", "Use UTC for snapshots."]
  puts format % ["INTERVAL", "The interval to snapshot."]
  puts format % ["KEEP", "How many snapshots to keep."]
  exit
end

def snapshot_prefix(interval)
  "zfstools-auto-snap_#{interval}-"
end

def get_snapshot_format
  '%Y-%m-%dT%H:%M'
end

### Get the name of the snapshot to create
def get_snapshot_name(interval)
  if $use_utc
    date = Time.now.utc.strftime(get_snapshot_format)
  else
    date = Time.now.strftime(get_snapshot_format)
  end
  snapshot_prefix(interval) + date
end

### Find eligible datasets
def find_datasets(datasets, property)
  cmd="zfs list -H -t filesystem,volume -o name,#{property} -s name"
  all_datasets = datasets['included'] + datasets['excluded']

  IO.popen cmd do |io|
    io.readlines.each do |line|
      dataset,value = line.split(" ")
      # Skip datasets with no value set
      next if value == "-"
      # If the dataset is already included/excluded, skip it (for override checking)
      next if all_datasets.include? dataset
      if value == "true"
        datasets['included'] << dataset
      elsif value == "false"
        datasets['excluded'] << dataset
      end
    end
  end
end

### Find which datasets can be recursively snapshotted
### single snapshot restrictions apply to datasets that have a child in the excluded list
def find_recursive_datasets(datasets)
  all_datasets = datasets['included'] + datasets['excluded']
  single = []
  recursive = []
  cleaned_recursive = []

  ### Find datasets that must be single, or are eligible for recursive
  datasets['included'].each do |dataset|
    excluded_child = false
    # Find all children_datasets
    children_datasets = all_datasets.select { |child_dataset| child_dataset.start_with? dataset }
    children_datasets.each do |child_dataset|
      if datasets['excluded'].include?(child_dataset)
        excluded_child = true
        single << dataset
        break
      end
    end
    unless excluded_child
      recursive << dataset
    end
  end

  ## Cleanup recursive
  recursive.each do |dataset|
    if dataset.include?('/')
      parts = dataset.rpartition('/')
      parent = parts[0]
    else
      parent = dataset
    end

    # Parent dataset
    if parent == dataset
      cleaned_recursive << dataset
      next
    end

    # Only add this if its parent is not in the recursive list
    cleaned_recursive << dataset unless recursive.include?(parent)
  end


  { 'single' => single, 'recursive' => cleaned_recursive }
end

### Create a snapshot
def create_snapshot(dataset, snapshot_name, recursive=false)
  flags=[]
  flags << "-r" if recursive
  cmd = "zfs snapshot #{flags.join(" ")} #{dataset}@#{snapshot_name}"
  puts cmd
  system(cmd)
end

### Destroy a snapshot
def destroy_snapshot(snapshot, recursive=false)
  # Default to deferred snapshot destroying
  flags=["-d"]
  flags << "-r" if recursive
  cmd = "zfs destroy #{flags.join(" ")} #{snapshot}"
  puts cmd
  system(cmd)
end

### Generate new snapshots
def do_new_snapshots(interval)
  datasets = {
    'included' => [],
    'excluded' => [],
  }

  snapshot_name = get_snapshot_name(interval)

  # Gather the datasets given the override property
  find_datasets datasets, "zfstools:auto-snapshot:#{interval}"
  # Gather all of the datasets without an override
  find_datasets datasets, "zfstools:auto-snapshot"

  ### Determine which datasets can be snapshotted recursively and which not
  datasets = find_recursive_datasets datasets

  # Snapshot single
  datasets['single'].each do |dataset|
    create_snapshot dataset, snapshot_name
  end

  # Snapshot recursive
  datasets['recursive'].each do |dataset|
    create_snapshot dataset, snapshot_name, true
  end
end
usage if ARGV.length < 2

interval=ARGV[0]
keep=ARGV[1].to_i

# Generate new snapshots
do_new_snapshots(interval) if keep > 0

def find_matching_snapshots(interval)
  dataset_snapshots = {}
  cmd = "zfs list -H -t snapshot -o name -S name"
  IO.popen cmd do |io|
    io.readlines.each do |line|
      line.chomp!
      if line.include?(snapshot_prefix(interval))
        dataset = line.split('@')[0]
        unless dataset_snapshots.has_key?(dataset)
          dataset_snapshots[dataset] = []
        end
        dataset_snapshots[dataset] << line
      end
    end
  end
  dataset_snapshots
end

def cleanup_expired_snapshots(interval, keep)
  ### Find all snapshots matching this interval
  dataset_snapshots = find_matching_snapshots(interval)
  dataset_snapshots.each do |dataset, snapshots|
    # Want to keep the first 'keep' entries, so slice them off ...
    dataset_snapshots[dataset].shift(keep)
    # ... Now the list only contains snapshots eligible to be destroyed.
  end
  snapshots_to_destroy = dataset_snapshots.values.flatten
  snapshots_to_destroy.each do |snapshot|
    destroy_snapshot snapshot
  end
end

# Delete expired
cleanup_expired_snapshots(interval, keep)
