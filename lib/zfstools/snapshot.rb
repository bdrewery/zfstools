require 'enumerator'
require 'shellwords'

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
        cmd = "zfs get -Hp -o value used " + @name.shellescape
        puts cmd if $debug
        @used = %x[#{cmd}].to_i
      end
      @used
    end

    def is_zero?
      if @used != 0
        return false
      end
      used
    end

    ### List all snapshots
    def self.list(dataset=nil, options={})
      snapshots = []
      flags=[]
      flags << "-d 1" if dataset and !options['recursive']
      flags << "-r" if options['recursive']
      cmd = "zfs list #{flags.join(" ")} -H -t snapshot -o name,used -S name"
      cmd += " " + dataset.shellescape if dataset
      puts cmd if $debug
      IO.popen cmd do |io|
        io.readlines.each do |line|
          snapshot_name,used = line.chomp.split("\t")
          snapshots << self.new(snapshot_name, used.to_i)
        end
      end
      snapshots
    end

    ### Create a snapshot
    def self.create(snapshot, options = {})
      flags=[]
      flags << "-r" if options['recursive']
      cmd = "zfs snapshot #{flags.join(" ")} "
      if snapshot.kind_of?(Array)
        cmd += snapshot.shelljoin
      else
        cmd += snapshot.shellescape
      end

      if options['db']
        case options['db']
        when 'mysql'
          sql_query=<<-EOF.gsub(/^ {10}/, '')

            FLUSH LOGS;
            FLUSH TABLES WITH READ LOCK;
            SYSTEM #{cmd};
            UNLOCK TABLES;
          EOF
          cmd = %Q[mysql -e "#{sql_query}"]
        when 'postgresql'
          sql_pre_query = "SELECT PG_START_BACKUP('zfs-auto-snapshot');"
          sql_post_query = "SELECT PG_STOP_BACKUP();"
          zfs_cmd = cmd
          cmd = %Q[(psql -c "#{sql_pre_query}" postgres ; #{zfs_cmd} ) ; psql -c "#{sql_post_query}" postgres]
        end
      end

      puts cmd if $debug || $verbose
      system(cmd) unless $dry_run
    end

    def self.create_many(snapshot_name, datasets, options={})
      # If any of the datasets contain a db it needs to be split out
      need_db_split = false
      datasets.each do |dataset|
        if dataset.db
          need_db_split = true
          break
        end
      end

      # XXX: The feature and ARG_MAX checks are not ideal here but there is
      # not yet a reason to generalize them to elsewhere.
      if not need_db_split and not defined?($zfs_feature_multi_snap)
        # Check for bookmark support, which we'll piggyback on for 'zfs snapshot snap1 snap2 snapN' support.
        pools = Zfs::Pool.list(nil, ["feature@bookmarks"])
        has_bookmarks = pools.find { |pool| pool.properties.include?('feature@bookmarks') }
        $zfs_feature_multi_snap = has_bookmarks
      end
      if not need_db_split and $zfs_feature_multi_snap
        snapshots = []
        max_length = 0
        datasets.each do |dataset|
          snapshot = "#{dataset.name}@#{snapshot_name}"
          max_length = [snapshot.length, max_length].max
          snapshots << snapshot
        end
        # Etc::sysconf https://bugs.ruby-lang.org/issues/9842 would be nice.
        if not defined?($arg_max)
          begin
            $arg_max = `getconf ARG_MAX`.chomp.to_i
          rescue Errno::ENOENT
            $arg_max = 4096
          end
          # Env and escaping slack
          $arg_max = $arg_max - 1024
        end
        # Lazy chunking
        chunks = $arg_max / max_length
        snapshots.each_slice(chunks) do |snapshots_chunk|
          self.create(snapshots_chunk, options)
        end
      else
        # Have to brute force.
        threads = []
        datasets.each do |dataset|
          threads << Thread.new do
            self.create("#{dataset.name}@#{snapshot_name}",
                        'recursive' => options['recursive'] || false,
                        'db' => dataset.db)
          end
          threads.last.join unless $use_threads
        end
        threads.each { |th| th.join }
      end
    end

    ### Destroy a snapshot
    def destroy(options = {})
      # If destroying a snapshot, need to flag all other snapshot sizes as stale
      # so they will be relooked up.
      @@stale_snapshot_size = true
      # Default to deferred snapshot destroying
      flags=["-d"]
      flags << "-r" if options['recursive']
      cmd = "zfs destroy #{flags.join(" ")} " + @name.shellescape
      puts cmd if $debug
      system(cmd) unless $dry_run
    end

  end
end
