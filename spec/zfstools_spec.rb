require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Zfstools", "#group_snapshots_into_datasets" do
  it "Groups snapshots into their datasets" do
    snapshots = {
      'tank' => [
        Zfs::Snapshot.new('tank@1'),
        Zfs::Snapshot.new('tank@2'),
      ],
      'tank/a' => [
        Zfs::Snapshot.new('tank/a@1'),
        Zfs::Snapshot.new('tank/a@2'),
      ],
      'tank/a/1' => [
        Zfs::Snapshot.new('tank/a/1@1'),
      ],
      'tank/a/2' => [
        Zfs::Snapshot.new('tank/a/2@1'),
      ],
      'tank/b' => [
        Zfs::Snapshot.new('tank/b@1'),
      ],
      'tank/c' => [
        Zfs::Snapshot.new('tank/c@1'),
      ],
      'tank/d' => [
        Zfs::Snapshot.new('tank/d@1'),
      ],
      'tank/d/1' => [
        Zfs::Snapshot.new('tank/d/1@2'),
      ]
    }
    datasets = {
      'tank' => Zfs::Dataset.new('tank'),
      'tank/a' => Zfs::Dataset.new('tank/a'),
      'tank/a/1' => Zfs::Dataset.new('tank/a/1'),
      'tank/a/2' => Zfs::Dataset.new('tank/a/2'),
      'tank/b' => Zfs::Dataset.new('tank/b'),
      'tank/c' => Zfs::Dataset.new('tank/c'),
      'tank/d' => Zfs::Dataset.new('tank/d'),
      'tank/d/1' => Zfs::Dataset.new('tank/d/1'),
    }
    dataset_snapshots = group_snapshots_into_datasets(snapshots.values.flatten, datasets.values)
    dataset_snapshots.should eq({
      datasets['tank'] => snapshots['tank'],
      datasets['tank/a'] => snapshots['tank/a'],
      datasets['tank/a/1'] => snapshots['tank/a/1'],
      datasets['tank/a/2'] => snapshots['tank/a/2'],
      datasets['tank/b'] => snapshots['tank/b'],
      datasets['tank/c'] => snapshots['tank/c'],
      datasets['tank/d'] => snapshots['tank/d'],
      datasets['tank/d/1'] => snapshots['tank/d/1'],
    })
  end

end

describe "Zfstools", "#find_recursive_datasets" do
  it "considers all included as recursive" do
    tank = Zfs::Dataset.new("tank")
    datasets = {
      'included' => [
        Zfs::Dataset.new("tank"),
        Zfs::Dataset.new("tank/a"),
        Zfs::Dataset.new("tank/a/1"),
        Zfs::Dataset.new("tank/b"),
      ],
      'excluded' => [],
    }
    recursive_datasets = find_recursive_datasets(datasets)
    recursive_datasets['recursive'].should eq([Zfs::Dataset.new("tank")])
    recursive_datasets['single'].should eq([])
  end

  it "considers all multiple parent datasets as recursive" do
    tank = Zfs::Dataset.new("tank")
    datasets = {
      'included' => [
        Zfs::Dataset.new("tank"),
        Zfs::Dataset.new("tank/a"),
        Zfs::Dataset.new("tank/a/1"),
        Zfs::Dataset.new("tank/b"),
        Zfs::Dataset.new("rpool"),
        Zfs::Dataset.new("rpool/a"),
        Zfs::Dataset.new("rpool/b"),
        Zfs::Dataset.new("zpool"),
        Zfs::Dataset.new("zpool/a"),
        Zfs::Dataset.new("zpool/b"),
      ],
      'excluded' => [],
    }
    recursive_datasets = find_recursive_datasets(datasets)
    recursive_datasets['recursive'].should eq([
      Zfs::Dataset.new("tank"),
      Zfs::Dataset.new("rpool"),
      Zfs::Dataset.new("zpool"),
    ])
    recursive_datasets['single'].should eq([])
  end

  it "considers all excluded as empty" do
    tank = Zfs::Dataset.new("tank")
    datasets = [
      Zfs::Dataset.new("tank"),
      Zfs::Dataset.new("tank/a"),
      Zfs::Dataset.new("tank/a/1"),
      Zfs::Dataset.new("tank/b"),
    ]
    included_excluded_datasets = {
      'included' => [],
      'excluded' => datasets,
    }
    recursive_datasets = find_recursive_datasets(included_excluded_datasets)
    recursive_datasets['recursive'].should eq([])
    recursive_datasets['single'].should eq([])
  end

  it "considers first level excluded" do
    included_excluded_datasets = {
      'included' => [
        Zfs::Dataset.new("tank"),
        Zfs::Dataset.new("tank/a"),
        Zfs::Dataset.new("tank/a/1"),
      ],
      'excluded' => [
        Zfs::Dataset.new("rpool"),
        Zfs::Dataset.new("rpool/a"),
      ]
    }
    recursive_datasets = find_recursive_datasets(included_excluded_datasets)
    recursive_datasets['recursive'].should eq([
      Zfs::Dataset.new("tank"),
    ])
    recursive_datasets['single'].should eq([])
  end

  it "considers second level excluded" do
    included_excluded_datasets = {
      'included' => [
        Zfs::Dataset.new("tank"),
        Zfs::Dataset.new("tank/a"),
        Zfs::Dataset.new("tank/a/1"),
      ],
      'excluded' => [
        Zfs::Dataset.new("tank/b"),
      ]
    }
    recursive_datasets = find_recursive_datasets(included_excluded_datasets)
    recursive_datasets['recursive'].should eq([
      Zfs::Dataset.new("tank/a"),
    ])
    recursive_datasets['single'].should eq([
      Zfs::Dataset.new("tank"),
    ])
  end

  it "considers third level excluded" do
    included_excluded_datasets = {
      'included' => [
        Zfs::Dataset.new("tank"),
        Zfs::Dataset.new("tank/a"),
        Zfs::Dataset.new("tank/a/1"),
        Zfs::Dataset.new("tank/a/2"),
        Zfs::Dataset.new("tank/b"),
        Zfs::Dataset.new("tank/b/1"),
        Zfs::Dataset.new("tank/b/2"),
      ],
      'excluded' => [
        Zfs::Dataset.new("tank/c"),
      ]
    }
    recursive_datasets = find_recursive_datasets(included_excluded_datasets)
    recursive_datasets['recursive'].should eq([
      Zfs::Dataset.new("tank/a"),
      Zfs::Dataset.new("tank/b"),
    ])
    recursive_datasets['single'].should eq([
      Zfs::Dataset.new("tank"),
    ])
  end

  it "considers child with mysql db in parent recursive" do
    included_excluded_datasets = {
      'included' => [
        Zfs::Dataset.new("tank"),
        Zfs::Dataset.new("tank/a"),
        Zfs::Dataset.new("tank/a/1"),
        Zfs::Dataset.new("tank/a/2"),
        Zfs::Dataset.new("tank/b"),
        Zfs::Dataset.new("tank/b/1").contains_db!("mysql"),
        Zfs::Dataset.new("tank/b/2"),
      ],
      'excluded' => []
    }
    recursive_datasets = find_recursive_datasets(included_excluded_datasets)
    recursive_datasets['recursive'].should eq([
      Zfs::Dataset.new("tank").contains_db!("mysql"),
    ])
    recursive_datasets['single'].should eq([])
  end

  it "considers child with mysql db in recursive with singles and exclusions" do
    included_excluded_datasets = {
      'included' => [
        Zfs::Dataset.new("tank"),
        Zfs::Dataset.new("tank/a"),
        Zfs::Dataset.new("tank/a/1"),
        Zfs::Dataset.new("tank/a/2").contains_db!("mysql"),
        Zfs::Dataset.new("tank/b"),
        Zfs::Dataset.new("tank/b/1"),
      ],
      'excluded' => [
        Zfs::Dataset.new("tank/b/2"),
      ]
    }
    recursive_datasets = find_recursive_datasets(included_excluded_datasets)
    recursive_datasets['recursive'].should eq([
      Zfs::Dataset.new("tank/a").contains_db!("mysql"),
      Zfs::Dataset.new("tank/b/1"),
    ])
    recursive_datasets['single'].should eq([
      Zfs::Dataset.new("tank"),
      Zfs::Dataset.new("tank/b"),
    ])
  end

  it "considers child with mysql db in single with recursives and exclusions" do
    included_excluded_datasets = {
      'included' => [
        Zfs::Dataset.new("tank"),
        Zfs::Dataset.new("tank/a"),
        Zfs::Dataset.new("tank/a/1"),
        Zfs::Dataset.new("tank/a/2"),
        Zfs::Dataset.new("tank/b"),
        Zfs::Dataset.new("tank/b/1").contains_db!("mysql"),
      ],
      'excluded' => [
        Zfs::Dataset.new("tank/b/2"),
      ]
    }
    recursive_datasets = find_recursive_datasets(included_excluded_datasets)
    recursive_datasets['recursive'].should eq([
      Zfs::Dataset.new("tank/a"),
      Zfs::Dataset.new("tank/b/1").contains_db!("mysql"),
    ])
    recursive_datasets['single'].should eq([
      Zfs::Dataset.new("tank"),
      Zfs::Dataset.new("tank/b"),
    ])
  end
end
