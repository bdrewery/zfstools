#! /usr/bin/env ruby

def usage
  puts "Usage: $0 <INTERVAL> <KEEP>"
  puts "\tINTERVAL: The interval to snapshot."
  puts "\tKEEP: How many snapshots to keep."
  exit
end

usage if ARGV.length < 2

interval=ARGV[0]
keep=ARGV[1]

datasets = {
  'included' => [],
  'excluded' => [],
}

def find_datasets(datasets, property)
  cmd="zfs list -H -t filesystem,volume -o name,#{property} -s name"
  all_datasets = datasets['included'].concat(datasets['excluded'])

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

# Gather the datasets given the override property
find_datasets datasets, "zfstools:auto-snapshot:#{interval}"
# Gather all of the datasets without an override
find_datasets datasets, "zfstools:auto-snapshot"
