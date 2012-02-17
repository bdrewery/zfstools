module Zfs
  class Dataset
    attr_reader :name
    attr_reader :properties
    def initialize(name, properties={}, options={})
      @name = name
      @properties = properties
    end

    def ==(dataset)
      dataset.equal?(self) || (dataset && dataset.name == @name)
    end

    def self.list(properties=[])
      datasets = []
      cmd_properties = ["name"] + properties
      cmd="zfs list -H -t filesystem,volume -o #{cmd_properties.join(",")} -s name"
      puts cmd if $debug
      IO.popen cmd do |io|
        io.readlines.each do |line|
          values = line.split
          name = values.shift
          dataset_properties = {}
          properties.each_with_index do |property_name, i|
            value = values[i]
            next if value == '-'
            dataset_properties[property_name] = value
          end
          datasets << self.new(name, dataset_properties)
        end
      end
      datasets
    end
  end
end
