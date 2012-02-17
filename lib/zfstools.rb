$:.unshift File.dirname(__FILE__)

require 'zfs/snapshot'
require 'zfs/dataset'

def snapshot_property
  "com.sun:auto-snapshot"
end

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
    children_datasets = all_datasets.select { |child_dataset| child_dataset.name.start_with? dataset.name }
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
    if dataset.name.include?('/')
      parts = dataset.name.rpartition('/')
      parent = all_datasets.find { |dataset| dataset.name == parts[0] }
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

  # If any children have a DB, need to set it in the recursive parent
  cleaned_recursive.each do |parent|
    all_datasets.each do |dataset|
      # Is this dataset a child of the parent?
      next if !dataset.name.include?(parent.name)
      # If this dataset has a DB, set the parent to contain it as well.
      if dataset.db
        parent.contains_db!(dataset.db)
      end
    end
  end


  {
    'single' => single,
    'recursive' => cleaned_recursive,
    'included' => datasets['included'],
    'excluded' => datasets['excluded'],
  }
end


### Find eligible datasets
def filter_datasets(datasets, included_excluded_datasets, property)
  all_datasets = included_excluded_datasets['included'] + included_excluded_datasets['excluded']

  datasets.each do |dataset|
    # If the dataset is already included/excluded, skip it (for override checking)
    next if all_datasets.include? dataset
    value = dataset.properties[property]
    if value == "true" || value == "mysql"
      included_excluded_datasets['included'] << dataset
    elsif value
      included_excluded_datasets['excluded'] << dataset
    end
  end
end

def find_eligible_datasets(interval)
  properties = [
    "#{snapshot_property}:#{interval}",
    snapshot_property,
  ]
  datasets = Zfs::Dataset.list(properties)

  ### Group datasets into included/excluded for snapshotting
  included_excluded_datasets = {
    'included' => [],
    'excluded' => [],
  }

  # Gather the datasets given the override property
  filter_datasets datasets, included_excluded_datasets, "#{snapshot_property}:#{interval}"
  # Gather all of the datasets without an override
  filter_datasets datasets, included_excluded_datasets, snapshot_property

  ### Determine which datasets can be snapshotted recursively and which not
  datasets = find_recursive_datasets included_excluded_datasets
end

### Generate new snapshots
def do_new_snapshots(datasets, interval)
  snapshot_name = snapshot_name(interval)

  threads = []
  # Snapshot single
  datasets['single'].each do |dataset|
    threads << Thread.new do
      Zfs::Snapshot.create("#{dataset.name}@#{snapshot_name}")
    end
    threads.last.join unless $use_threads
  end

  # Snapshot recursive
  datasets['recursive'].each do |dataset|
    threads << Thread.new do
      Zfs::Snapshot.create("#{dataset.name}@#{snapshot_name}", 'recursive' => true)
    end
    threads.last.join unless $use_threads
  end

  threads.each { |th| th.join }
end

def group_snapshots_into_datasets(snapshots, datasets)
  dataset_snapshots = Hash.new {|h,k| h[k] = [] }
  ### Sort into datasets
  snapshots.each do |snapshot|
    snapshot_name = snapshot.name.split('@')[0]
    dataset = datasets.find { |dataset| dataset.name == snapshot_name }
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
    if snapshot.is_zero?
      puts "Destroying zero-sized snapshot: #{snapshot.name}" if $verbose
      snapshot.destroy
    else
      remaining_snapshots << snapshot
    end
  end
  remaining_snapshots
end

def datasets_destroy_zero_sized_snapshots(dataset_snapshots)
  ### Cleanup zero-sized snapshots before purging old snapshots
  ### Keep the most recent one of the zeros and restore it for the later expired purging
  threads = []
  dataset_snapshots.each do |dataset, snapshots|
    ## Safe to run this in a thread as each dataset's snapshots shift on themselves, but not outside.
    threads << Thread.new do
      ## Delete all of the remaining zero-sized snapshots
      dataset_snapshots[dataset] = destroy_zero_sized_snapshots(snapshots)
    end
    threads.last.join unless $use_threads
  end
  threads.each { |th| th.join }
  dataset_snapshots
end

### Find and destroy expired snapshots
def cleanup_expired_snapshots(datasets, interval, keep, should_destroy_zero_sized_snapshots)
  ### Find all snapshots matching this interval
  snapshots = Zfs::Snapshot.list.select { |snapshot| snapshot.name.include?(snapshot_prefix(interval)) }
  dataset_snapshots = group_snapshots_into_datasets(snapshots, datasets['included'] + datasets['excluded'])
  ### Filter out datasets not included
  dataset_snapshots.select! { |dataset, snapshots| datasets['included'].include?(dataset) }

  if should_destroy_zero_sized_snapshots
    dataset_snapshots = datasets_destroy_zero_sized_snapshots(dataset_snapshots)
  end

  ### Now that zero-sized are removed, remove expired snapshots
  dataset_snapshots.each do |dataset, snapshots|
    # Want to keep the first 'keep' entries, so slice them off ...
    dataset_snapshots[dataset].shift(keep)
    # ... Now the list only contains snapshots eligible to be destroyed.
  end
  threads = []
  dataset_snapshots.values.flatten.each do |snapshot|
    threads << Thread.new do
      snapshot.destroy
    end
    threads.last.join unless $use_threads
  end
  threads.each { |th| th.join }
end
