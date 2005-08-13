require 'tzfile'

require 'test/unit'

class TestTZ < Test::Unit::TestCase
  TokyoTime = TZFile.create("Asia/Tokyo")
  EasterTime = TZFile.create("Pacific/Easter")
  BermudaTime = TZFile.create("Atlantic/Bermuda")

  LeapTokyoTime = TZFile.create("right/Asia/Tokyo")

  def test_at_int
    assert_equal([0,0,0,1,1,2000,6,1,false,"JST"], TokyoTime.at(946652400).to_a)
    assert_equal([0,0,0,1,1,2000,6,1,false,"JST"], TokyoTime.at(946652400).to_a)
  end

  def test_at_tztime
    tokyo = TokyoTime.now
    assert_equal(tokyo.tv_sec, EasterTime.at(tokyo).tv_sec)
  end

  def test_at_time
    now = Time.now
    assert_equal(now.utc.to_a, EasterTime.at(now).utc.to_a)
  end

  def test_at_leaptime
    tokyo = TokyoTime.now
    leaptokyo = LeapTokyoTime.at(tokyo)
    assert_equal(tokyo.to_a, leaptokyo.to_a)
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
