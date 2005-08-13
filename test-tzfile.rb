require 'tzfile'

require 'test/unit'

class TestTZ < Test::Unit::TestCase
  TokyoTime = TZFile.create("Asia/Tokyo")
  EasterTime = TZFile.create("Pacific/Easter")
  BermudaTime = TZFile.create("Atlantic/Bermuda")

  def test_at
    assert_equal([0,0,0,1,1,2000,6,1,false,"JST"], TokyoTime.at(946652400).to_a)
    assert_equal([0,0,0,1,1,2000,6,1,false,"JST"], TokyoTime.at(946652400).to_a)
  end

  def test_getutc
    now = TokyoTime.now
    assert(!now.utc?)
    assert(now.getutc.utc?)
    assert(now.getgm.utc?)
    assert(!now.getlocal.utc?)
    now.utc
    assert(now.utc?)
    assert(now.getutc.utc?)
    assert(now.getgm.utc?)
    assert(!now.getlocal.utc?)
  end
end
