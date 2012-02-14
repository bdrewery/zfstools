module Zfs
  class Snapshot
    def initialize(snapshot_name)
      @snapshot_name = snapshot_name
    end

    ### Find all snapshots in the given interval
    ### @param String match_on The string to match on snapshots
    def self.find(match_on)
      dataset_snapshots = Hash.new {|h,k| h[k] = [] }
      cmd = "zfs list -H -t snapshot -o name -S name"
      IO.popen cmd do |io|
        io.readlines.each do |line|
          line.chomp!
          if line.include?(match_on)
            dataset = line.split('@')[0]
            dataset_snapshots[dataset] << self.new(line)
          end
        end
      end
      dataset_snapshots
    end

    ### Create a snapshot
    def self.create(snapshot, options = {})
      flags=[]
      flags << "-r" if options['recursive']
      cmd = "zfs snapshot #{flags.join(" ")} #{snapshot}"
      puts cmd
      system(cmd) unless $dry_run
    end

    ### Destroy a snapshot
    def destroy(options = {})
      # Default to deferred snapshot destroying
      flags=["-d"]
      flags << "-r" if options['recursive']
      cmd = "zfs destroy #{flags.join(" ")} #{@snapshot_name}"
      puts cmd
      system(cmd) unless $dry_run
    end

  end
end
