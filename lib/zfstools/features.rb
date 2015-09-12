module Zfs
  class Features
    @@have_bookmarks = nil
    @@have_multi_snap = nil
    @@have_written = nil

    # https://www.illumos.org/issues/4369
    def self.has_bookmarks
      if @@have_bookmarks.nil?
        pools = Zfs::Pool.list(nil, ["feature@bookmarks"])
        has_bookmarks = pools.find { |pool| pool.properties.include?('feature@bookmarks') }
        @@have_bookmarks = !has_bookmarks.nil?
      end
      @@have_bookmarks
    end

    # https://www.illumos.org/issues/2900
    def self.has_multi_snap
      if @@have_multi_snap.nil?
        # Check for bookmark support, which we'll piggyback on for 'zfs snapshot snap1 snap2 snapN'
        @@have_multi_snap = self.has_bookmarks
      end
      @@have_multi_snap
    end

    # https://www.illumos.org/issues/1645
    def self.has_written
      if @@have_written.nil?
        # Check for bookmark support, which we'll piggyback on for 'written' support
        @@have_written = self.has_bookmarks
      end
      @@have_written
    end
  end
end
