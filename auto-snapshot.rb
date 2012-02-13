#! /usr/bin/env ruby

def usage
  puts "Usage: $0 <INTERVAL> <KEEP>"
  puts "\tINTERVAL: The interval to snapshot."
  puts "\tKEEP: How many snapshots to keep."
  exit
end

### Get the name of the snapshot to create
def get_snapshot_name(interval)
  date = Time.now.strftime('%Y-%m-%dT%H:%M')
  "zfstools-auto-snap_#{interval}-#{date}"
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
keep=ARGV[1]

# Generate new snapshots
do_new_snapshots(interval)
