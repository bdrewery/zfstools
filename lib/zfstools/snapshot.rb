require 'enumerator'
require 'shellwords'
require 'zfstools/features'

module Zfs
  class Snapshot
    @@stale_snapshot_size = false
    attr_reader :name
    def initialize(name, used=nil, destroy_after=nil)
      @name = name
      @used = used
      @destroy_after = destroy_after
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

    def destroy_after?(timestamp)
      return false if @destroy_after.nil? || @destroy_after > timestamp
      true
    end

    ### List all snapshots
    def self.list(dataset=nil, options={})
      snapshots = []
      flags=[]
      flags << "-d 1" if dataset and !options['recursive']
      flags << "-r" if options['recursive']
      cmd = "zfs list #{flags.join(" ")} -H -t snapshot -o name,used,#{destroy_after_property} -S name"
      cmd += " " + dataset.shellescape if dataset
      puts cmd if $debug
      IO.popen cmd do |io|
        io.readlines.each do |line|
          snapshot_name,used,destroy_after = line.chomp.split("\t")
          destroy_after = Integer(destroy_after) rescue nil
          snapshots << self.new(snapshot_name, used.to_i, destroy_after)
        end
      end
      snapshots
    end

    ### Create a snapshot
    def self.create(snapshot, options = {})
      flags=[]
      flags << "-r" if options['recursive']
      flags << "-o #{destroy_after_property}=" + options['destroy_after'].to_s if options['destroy_after']
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
      if not options['single']
        # If any of the datasets contain a db it needs to be split out
        db_datasets = []
        datasets.reject! do |dataset|
          if dataset.db
            db_datasets << dataset
            true
          end
        end
        # Create db snapshots individually
        self.create_many(snapshot_name, db_datasets, options.merge({'single' => true}))
      end

      return if datasets.empty?

      if not options['single'] and Zfs::Features.has_multi_snap
        snapshots = []
        max_length = 0
        datasets.each do |dataset|
          snapshot = "#{dataset.name}@#{snapshot_name}"
          max_length = [snapshot.length, max_length].max
          snapshots << snapshot
        end
        # XXX: The ARG_MAX checks are not ideal here but there is
        # not yet a reason to generalize it to elsewhere.
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
        # Group by pool
        pooled_snapshots = snapshots.group_by { |snapshot| snapshot.split('@')[0].split('/')[0] }
        pooled_snapshots.each do |pool, snapshots|
          snapshots.each_slice(chunks) do |snapshots_chunk|
            self.create(snapshots_chunk, options)
          end
        end
      else
        # Have to brute force.
        threads = []
        datasets.each do |dataset|
          threads << Thread.new do
            self.create("#{dataset.name}@#{snapshot_name}", {
                        'recursive' => options['recursive'] || false,
                        'db' => dataset.db,
                        'destroy_after' => options['destroy_after'] || false,
                        })
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
