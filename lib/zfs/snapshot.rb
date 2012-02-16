module Zfs
  class Snapshot
    @@stale_snapshot_size = false
    attr_reader :name
    def initialize(name, used=nil)
      @name = name
      @used = used
    end

    def used
      if @used.nil? or @@stale_snapshot_size
        cmd = "zfs get -Hp -o value used #{@name}"
        @used = %x[#{cmd}].to_i
      end
      @used
    end

    ### List all snapshots
    def self.list(dataset=nil, options={})
      snapshots = []
      flags=[]
      flags << "-d 1" if dataset and !options['recursive']
      flags << "-r" if options['recursive']
      cmd = "zfs list #{flags.join(" ")} -H -t snapshot -o name,used -S name"
      cmd += " #{dataset}" if dataset
      puts cmd if $verbose
      IO.popen cmd do |io|
        io.readlines.each do |line|
          line.chomp!
          snapshot_name,used = line.split(' ')
          snapshots << self.new(snapshot_name, used.to_i)
        end
      end
      snapshots
    end

    ### Create a snapshot
    def self.create(snapshot, options = {})
      flags=[]
      flags << "-r" if options['recursive']
      cmd = "zfs snapshot #{flags.join(" ")} #{snapshot}"
      puts cmd if $verbose
      system(cmd) unless $dry_run
    end

    ### Destroy a snapshot
    def destroy(options = {})
      # If destroying a snapshot, need to flag all other snapshot sizes as stale
      # so they will be relooked up.
      @@stale_snapshot_size = true
      # Default to deferred snapshot destroying
      flags=["-d"]
      flags << "-r" if options['recursive']
      cmd = "zfs destroy #{flags.join(" ")} #{@name}"
      puts cmd if $verbose
      system(cmd) unless $dry_run
    end

  end
end
