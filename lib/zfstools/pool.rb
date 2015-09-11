module Zfs
  class Pool
    attr_reader :name
    attr_reader :properties

    def initialize(name, properties={})
      @name = name
      @properties = properties
    end

    def ==(pool)
      pool.equal?(self) || (pool && pool.name == @name)
    end

    def to_s()
      res = ""
      @properties.each do |property, value|
        res += "[#{@name}] #{property}: #{value}\n"
      end
      res
    end

    def self.list(name=nil, cmd_properties=[])
      pools = []
      cmd_properties << "all" if cmd_properties.empty?
      # -H,-p and -o are Illumos improvements. Failure means it won't support
      # new features.
      cmd="zpool get -H -p -o name,property,value #{cmd_properties.join(",")}"
      cmd += " #{name}" if name
      cmd += " 2>/dev/null"
      puts cmd if $debug
      pool_properties = Hash.new{|pool, properties| pool[properties] = {}}
      IO.popen cmd do |io|
        io.readlines.each do |line|
          values = line.chomp.split("\t")
          name = values.shift
          property = values.shift
          value = values.shift
          pool_properties[name][property] = value
        end
      end
      pool_properties.each do |name, properties|
        pools << self.new(name, properties)
      end
      pools
    end
  end
end
