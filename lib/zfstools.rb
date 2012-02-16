$:.unshift File.dirname(__FILE__)

require 'zfs/snapshot'

def snapshot_prefix(interval=nil)
  prefix = "zfs-auto-snap"
  if interval
    prefix += "_#{interval}-"
  end
  prefix
end

def snapshot_format
  '%Y-%m-%d-%Hh%M'
end

### Get the name of the snapshot to create
def snapshot_name(interval)
  if $use_utc
    date = Time.now.utc.strftime(snapshot_format + "U")
  else
    date = Time.now.strftime(snapshot_format)
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

### Generate new snapshots
def do_new_snapshots(interval)
  datasets = {
    'included' => [],
    'excluded' => [],
  }

  snapshot_name = snapshot_name(interval)

  # Gather the datasets given the override property
  find_datasets datasets, "com.sun:auto-snapshot:#{interval}"
  # Gather all of the datasets without an override
  find_datasets datasets, "com.sun:auto-snapshot"

  ### Determine which datasets can be snapshotted recursively and which not
  datasets = find_recursive_datasets datasets

  # Snapshot single
  datasets['single'].each do |dataset|
    Zfs::Snapshot.create("#{dataset}@#{snapshot_name}")
  end

  # Snapshot recursive
  datasets['recursive'].each do |dataset|
    Zfs::Snapshot.create("#{dataset}@#{snapshot_name}", 'recursive' => true)
  end
end

def group_snapshots_into_datasets(snapshots)
  dataset_snapshots = Hash.new {|h,k| h[k] = [] }
  ### Sort into datasets
  snapshots.each do |snapshot|
    dataset = snapshot.name.split('@')[0]
    dataset_snapshots[dataset] << snapshot
  end
  dataset_snapshots
end

### Destroy zero-sized snapshots. Recheck after each as the size may have shifted.
def destroy_zero_sized_snapshots(snapshots)
  ### Shift off the last, so it maintains the changes
  saved_snapshot = snapshots.shift(1)
  remaining_snapshots = [saved_snapshot]
  snapshots.each do |snapshot|
    if snapshot.used == 0
      puts "Destroying zero-sized snapshot: #{snapshot.name}"
      snapshot.destroy
    else
      remaining_snapshots << snapshot
    end
  end
  remaining_snapshots
end

### Find and destroy expired snapshots
def cleanup_expired_snapshots(interval, keep, destroy_zero_sized_snapshots)
  ### Find all snapshots matching this interval
  snapshots = Zfs::Snapshot.list.select { |snapshot| snapshot.name.include?(snapshot_prefix(interval)) }
  dataset_snapshots = group_snapshots_into_datasets(snapshots)

  if destroy_zero_sized_snapshots
    ### Cleanup zero-sized snapshots before purging old snapshots
    ### Keep the most recent one of the zeros and restore it for the later expired purging
    dataset_snapshots.each do |dataset, snapshots|
      ## Delete all of the remaining zero-sized snapshots
      dataset_snapshots[dataset] = destroy_zero_sized_snapshots(snapshots)
    end
  end

  ### Now that zero-sized are removed, remove expired snapshots
  dataset_snapshots.each do |dataset, snapshots|
    # Want to keep the first 'keep' entries, so slice them off ...
    dataset_snapshots[dataset].shift(keep)
    # ... Now the list only contains snapshots eligible to be destroyed.
  end
  dataset_snapshots.values.flatten.each do |snapshot|
    snapshot.destroy
  end
end
