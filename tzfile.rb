require 'find'
require 'date'

=begin
= TZFile

Timezone dependent time library using tzfile.

= Portability
Since this library uses tzfile format, it doesn't work on platforms which
doesn't provide timezone information by tzfile format.
The format is primarily supported by tzcode/tzdata package
((<URL:ftp://elsie.nci.nih.gov/pub/>)) and the Theory file in tzcode says:

  This package is already part of many POSIX-compliant hosts,
  including BSD, HP, Linux, Network Appliance, SCO, SGI, and Sun.

= Restriction
Since 32bit signed integer is used to specify a number of seconds from
1970/1/1 in the format, tzfile can provide timezone information only between
December 1901 and January 2038.
Thanks to Ruby's Bignum and object oriented polymorphism,
this library doesn't cause overflow exception even if a time is out of the range.
This library uses first timezone information for before 1901 and
last timezone information for after 2038.
But this doesn't mean results are correct.
For example, if January 2038 is in DST (daylight saving time)
- remember that January is summer in the south half of the globe -,
DST is applied forever after 2038.
So, don't use this library under such condition.
=end

module TZFile
=begin
== module methods:
--- TZFile.create(path)
    Creates a timezone class by timezone file specified by "path".
    If "path" is relative, it is interpreted as a relative path
    from platform dependent timezone directory.

    The generated class behaves like Time class.
=end
  def TZFile.create(path)
    return open(File.expand_path(path, zoneinfo_directory)) {|f|
             TZFile.parse(f, InitVisitor.new(path))
	   }
  end

=begin
--- TZFile.zoneinfo_directory
    Returns platform dependent zoneinfo directory such as "/usr/share/zoneinfo".
=end
  @@zoneinfo_directory = nil
  def TZFile.zoneinfo_directory
    return @@zoneinfo_directory if @@zoneinfo_directory
    for dir in ['/usr/share/zoneinfo', '/usr/share/lib/zoneinfo']
      if FileTest.directory? dir
	@@zoneinfo_directory = dir
        return @@zoneinfo_directory
      end
    end
    raise ZoneInfoNotFound.new
  end
  class ZoneInfoNotFound < StandardError
  end

=begin
--- TZFile.each([directory]) {|name, tzfile| ...}
    Evaluate the block for each timezone file under "directory".
    If the directory is not specified, platform dependent directory such as
    /usr/share/zoneinfo is used.
    "name" is a relative path from the directory and
    "tzfile" is a timezone object.
=end
  def TZFile.each(dir=zoneinfo_directory)
    if dir == zoneinfo_directory
      prefixlen = zoneinfo_directory.length + 1
    else
      prefixlen = 0
    end
    Find.find(dir) {|name|
      if FileTest.file? name
        n = name[prefixlen..-1]
	begin
	  yield n, TZFile.create(n)
	rescue ParseError
	end
      end
    }
  end

  def TZFile.parse(input, visitor)
    magic, ttisgmtcnt, ttisstdcnt, leapcnt, timecnt, typecnt, charcnt =
      input.read(44).unpack('a4 x16 NNNNNN');
    raise ParseError.new('Magic don\'t found') if magic != 'TZif'

    visitor.ttisgmtcnt(ttisgmtcnt)
    visitor.ttisstdcnt(ttisstdcnt)
    visitor.leapcnt(leapcnt)
    visitor.timecnt(timecnt)
    visitor.typecnt(typecnt)
    visitor.charcnt(typecnt)

    (0...timecnt).each {|i|
      transition_time = input.read(4).unpack('N')[0]
      transition_time -= 0x100000000 if 0x80000000 <= transition_time
      visitor.time_transition(i, transition_time)
    }

    (0...timecnt).each {|i|
      localtime_type = input.read(1).unpack('C')[0]
      visitor.time_type(i, localtime_type)
    }

    (0...typecnt).each {|i|
      gmtoff, isdst, abbrind = input.read(6).unpack('NCC')
      gmtoff -= 0x100000000 if 0x80000000 <= gmtoff
      visitor.ttype(i, gmtoff, isdst, abbrind)
    }

    zone_abbrev = input.read(charcnt)
    visitor.zone_abbrev(zone_abbrev)

    (0...leapcnt).each {|i|
      leaptime, secs = input.read(8).unpack('NN')
      leaptime -= 0x100000000 if 0x80000000 <= leaptime
      secs -= 0x100000000 if 0x80000000 <= secs
      visitor.leap(i, leaptime, secs)
    }

    (0...ttisstdcnt).each {|i|
      isstd = input.read(1).unpack('C')[0]
      visitor.ttype_isstd(i, isstd)
    }

    (0...ttisgmtcnt).each {|i|
      isgmt = input.read(1).unpack('C')[0]
      visitor.ttype_isgmt(i, isgmt)
    }

    return visitor.finished
  end
  class ParseError < StandardError
  end

  class InitVisitor
    def initialize(name)
      @name = name
    end

    def method_missing(m, *args)
    end

    def timecnt(cnt)
      @time = Array.new(cnt)
    end

    def time_transition(i, t)
      @time[i] = [t, nil]
    end

    def time_type(i, t)
      @time[i][1] = t
    end

    def typecnt(cnt)
      @type = Array.new(cnt)
    end

    def ttype(i, gmtoff, isdst, abbrind)
      @type[i] = [gmtoff, isdst != 0, abbrind, false, false]
    end

    def ttype_isstd(i, isstd)
      @type[i][3] = isstd != 0
    end

    def ttype_isgmt(i, isgmt)
      @type[i][4] = isgmt != 0
    end

    def leapcnt(cnt)
      @leap = Array.new(cnt)
    end

    def leap(i, leaptime, secs)
      @leap[i] = [leaptime, secs]
    end

    def zone_abbrev(z)
      @zone_abbrev = z
    end

    def finished
      timetype = []
      @type.each {|t|
        gmtoff, isdst, abbrind, isstd, isgmt = t
	abbrev = @zone_abbrev[abbrind...@zone_abbrev.index(?\0, abbrind)]
	timetype << TimeType.new(gmtoff, isdst, abbrind, isstd, isgmt, abbrev)
      }

      firsttype = nil
      timetype.each {|t|
	unless t.isdst
	  firsttype = t
	  break
	end
      }

      range_min = [true]
      range_type = [firsttype]
      (0...@time.length).each {|i|
	range_min << @time[i][0]
	range_type << timetype[@time[i][1]]
      }
      range_min << false

      leap = []
      @leap.each {|t, s|
        leap << LeapSecond.new(t, s)
      }

      klass = Class.new(TZFile::Time)
      name = @name
      klass.class_eval {
        extend TZFile
	@name = name
	@timetype = timetype
	@firsttype = firsttype
	@range_min = range_min
	@range_min_time = Array.new(@range_min.size)
	@range_type = range_type
	@leapsecond = leap
      }
      return klass
    end
  end

=begin
== methods:
Following methods can be used as class methods of the classes
since TZFile extends classes generated by TZFile.create,

--- at(time)
=end
  def at(time)
    self.new(time)
  end

  JDEpoch = 2440588 # Julian day number of 1970/01/01.

=begin
--- utc(year[, mon[, mday[, hour[, min[, sec]]]]])
--- utc(sec, min, hour, mday, mon, year, wday, yday, isdst, zone)
--- gm(year[, mon[, mday[, hour[, min[, sec]]]]])
--- gm(sec, min, hour, mday, mon, year, wday, yday, isdst, zone)
=end
  def utc(*args)
    if args.length == 10
      sec, min, hour, mday, mon, year, wday, yday, isdst, zone = args
    else
      year = args[0]
      mon = args[1] || 1
      mday = args[2] || 1
      hour = args[3] || 0
      min = args[4] || 0
      sec = args[5] || 0
    end
    leap = sec == 60 ? 1 : 0
    sec -= leap

    time_nonleap = (Date.new(year, mon, mday).jd - JDEpoch) * 24 * 60 * 60 +
                   hour * 60 * 60 + min * 60 + sec
    return self.new(count_leapseconds(time_nonleap) + leap).utc
  end
  alias gm utc

=begin
--- local(year[, mon[, mday[, hour[, min[, sec]]]]])
--- local(sec, min, hour, mday, mon, year, wday, yday, isdst, zone)
--- mktime(year[, mon[, mday[, hour[, min[, sec]]]]])
--- mktime(sec, min, hour, mday, mon, year, wday, yday, isdst, zone)
=end
  def local(*args)
    if args.length == 10
      sec, min, hour, mday, mon, year, wday, yday, isdst, zone = args
    else
      year = args[0]
      mon = args[1] || 1
      mday = args[2] || 1
      hour = args[3] || 0
      min = args[4] || 0
      sec = args[5] || 0
    end
    leap = sec == 60 ? 1 : 0
    sec -= leap

    ymdhms = [year, mon, mday, hour, min, sec]
    tt = @firsttype
    each_transition {|tt1, t, tt2|
      if (ymdhms <=> t.local_data.ymdhms) < 0
        tt = tt1
	break
      end
      tt = tt2
    }

    time_nonleap = (Date.new(year, mon, mday).jd - JDEpoch) * 24 * 60 * 60 +
                   hour * 60 * 60 + min * 60 + sec - tt.gmtoff
    return self.new(count_leapseconds(time_nonleap) + leap).localtime
  end
  alias mktime local

=begin
--- now
    Creates a new object corresponding to a current time.
    The current time is taken from Time.now.gmtime.to_a.
=end
  def now
    return self.utc(*::Time.now.gmtime.to_a).localtime
  end

  def name
    return @name
  end

  def timetype_nonleap(time)
    tt = @firsttype
    (1...@range_type.length).each {|i|
      return @range_type[i - 1] if time < @range_min[i]
    }
    return @range_type[-1]
  end

  def range_min_time(i)
    return @range_min_time[i] if @range_min_time[i] != nil
    t = @range_min[i]
    return @range_min_time[i] = t if t == true || t == false
    return @range_min_time[i] = at(count_leapseconds(@range_min[i]))
  end

=begin
--- each_range {|time1, timetype, time2| ...}
    Evaluate the block for each time range.
    "time1" is a beginning of the time range.
    "time2" is a beginning of the next time range.
    "typetype" is a time type applied between "time1" and "time2".

    For first time range, time1 is true.
    For last time range, time2 is false. 
=end
  def each_range
    (0...@range_type.length).each {|i|
      yield range_min_time(i), @range_type[i], range_min_time(i+1)
    }
    return nil
  end

=begin
--- each_transition {|timetype1, time, timetype2| ...}
    Evaluate the block for each trantision time.
    "timetype1" is a time type before "time" exclusive.
    "timetype2" is a time type after "time" inclusive.
=end
  def each_transition
    (1...@range_type.length).each {|i|
      yield @range_type[i - 1], range_min_time(i), @range_type[i]
    }
    return nil
  end

=begin
--- each_closed_range {|time1, timetype, time2| ...}
    Like each_range but first and last time range is not yielded.
    So "time1" and "time2" is always TZTime::Time.
=end
  def each_closed_range
    (1...(@range_type.length - 1)).each {|i|
      yield range_min_time(i), @range_type[i], range_min_time(i+1)
    }
    return nil
  end

=begin
--- count_leapseconds(time[, direction])
=end
  def count_leapseconds(t, dir=nil)
    secs = 0
    r = t
    @leapsecond.each {|l|
      if secs < l.secs # leapsecond insertion
	return r if t <= l.time - l.secs
      elsif l.secs < secs # leapsecond deletion
	return r if t < l.time - l.secs - (secs - l.secs)
        if t < l.time - l.secs
	  if dir == true
	    return count_leapseconds(t - 1, true)
	  elsif dir == false
	    return count_leapseconds(t + 1, false)
	  else
	    raise LeapSecondHit.new('deleted leapsecond', t)
	  end
	end
      end
      secs = l.secs
      r = t + l.secs
    }
    return r
  end

  class LeapSecondHit < StandardError
    def initialize(msg, time)
      super(msg)
      @time = time
    end
  end

=begin
--- uncount_leapseconds(time)
    Convert an integer "time" to an array which has three elements: [t, s, d].
    "t" corresponds to "time" but leapseconds are not counted.
    "s" specifies the type of the previous leapsecond:
    -1, 1, 0 for deletion, insertion, not exists.
    "d" is a number of seconds from the previous leapsecond.
    If the previous leapsecond is not exists, "d" is -1.

    If "time" points an inserted leapsecond, "t" corresponds to "time-1",
    "s" is 1 and "d" is 0.

    If "time" is just after a deleted leapsecond, "d" is 1.
=end
  def uncount_leapseconds(time)
    ltype = 0
    lprev = nil
    lsecs = 0
    time_nonleap = time
    @leapsecond.each {|l|
      if time < l.time
	return [time_nonleap, ltype, (lprev ? time - lprev : -1)]
      end
      lprev = l.time
      if lsecs < l.secs # leapsecond insertion
	# (l.secs - lsecs) must be 1.
	ltype = 1
        if time == l.time # hit to the leapsecond
	  return [time - l.secs, ltype, 0]
	end
	lprev = l.time
      elsif lsecs > l.secs # leapsecond deletion
	lprev = l.time - 1
	ltype = -1
      end
      time_nonleap = time - l.secs
      lsecs = l.secs
    }
    return [time_nonleap, ltype, (lprev ? time - lprev : -1)]
  end

  class DumpVisitor
    def method_missing(m, *args)
      print m
      p args
    end
  end

=begin
= TZFile::Time
The superclass of a class generated by TZFile.create.
=end
  class Time
=begin
== included modules:
* Comparable
=end
    include Comparable

    def initialize(time=self.class.now.to_i)
      @time = time
      @utc = false

      @utc_data = nil
      @local_data = nil
    end

=begin
--- self + other
=end
    def +(other)
      return self.class.new(@time + other)
    end

=begin
--- self - other
=end
    def -(other)
      if self.class === other
        return @time - other.to_i
      else
	return self.class.new(@time - other)
      end
    end

    def asctime
      # xxx
    end
    alias ctime asctime

=begin
--- self <=> other
=end
    def <=>(other)
      return @time <=> other.to_i
    end

=begin
--- utc?
--- gmt?
=end
    def utc?
      return @utc
    end
    alias gmt? utc?

=begin
--- utc
--- gmtime
=end
    def utc
      @utc = true
      return self
    end
    alias gmtime utc

=begin
--- localtime
=end
    def localtime
      @utc = false
      return self
    end

=begin
--- to_i
=end
    def to_i
      return @time
    end
    alias tv_sec to_i

    def current_data
      if @utc
        return utc_data
      else
	return local_data
      end
    end

    def utc_data
      update_data(true)
    end

    def local_data
      update_data(false)
    end

    def update_data(utc)
      if utc
	return @utc_data if @utc_data
      else
	return @localutc_data if @localutc_data
      end
      time_nonleap, leaptype, leapoffset = self.class.uncount_leapseconds(@time)
      tt = self.class.timetype_nonleap(time_nonleap)
      if utc
	gmtoff = 0
	zone_abbrev = 'UTC'
	zone_gmtoff = '+00:00:00'
      else
	gmtoff = tt.gmtoff
	zone_abbrev = tt.abbrev
	zone_gmtoff = tt.gmtoff_str
      end
      x = time_nonleap + gmtoff
      x, sec = x.divmod(60)
      x, min = x.divmod(60)
      x, hour = x.divmod(24)
      date = Date.new1(JDEpoch + x)
      sec += leaptype if leapoffset <= sec
      ymdhms = [date.year, date.mon, date.mday, hour, min, sec]
      data = TM.new(time_nonleap, tt, zone_abbrev, zone_gmtoff, gmtoff, date, ymdhms, *ymdhms)
      if utc
        return @utc_data = data
      else
        return @local_data = data
      end
    end

    TM = Struct.new("TM", :time_nonleap, :tt, :zone_abbrev, :zone_gmtoff, :gmtoff, :date, :ymdhms, :year, :mon, :mday, :hour, :min, :sec)

    DayName = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
    MonthName = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

=begin
--- to_s
=end
    def to_s
      tm = current_data
      return sprintf("%s %s %02d %02d:%02d:%02d %s %d (%d%+d %s %s%s)",
	DayName[tm.date.wday], MonthName[tm.mon - 1],
	tm.mday, tm.hour, tm.min, tm.sec, tm.zone_abbrev, tm.year,
	tm.time_nonleap, @time - tm.time_nonleap, 
	tm.zone_gmtoff, self.class.name, tm.tt.isdst ? ' DST' : '')
    end

    def inspect
      return to_s
    end
  end

=begin
= TZFile::TimeType
=end
  class TimeType
    def initialize(gmtoff, isdst, abbrind, isstd, isgmt, abbrev)
      @gmtoff = gmtoff
      @isdst = isdst
      @abbrind = abbrind
      @isstd = isstd
      @isgmt = isgmt
      @abbrev = abbrev
    end
    attr_reader :gmtoff, :isdst, :abbrind, :isstd, :isgmt, :abbrev

    def gmtoff_str
      t = @gmtoff
      sign = t < 0 ? '-' : '+'
      t = t.abs
      t, sec = t.divmod(60)
      hour, min = t.divmod(60)
      return sprintf("%s%02d:%02d:%02d", sign, hour, min, sec)
    end

    def to_s
      return sprintf("#<%s %s(%d) %s%s%s%s>",
		     self.class, @abbrev, @abbrind, gmtoff_str,
		     @isstd ? ' STD' : '',
		     @isgmt ? ' GMT' : '',
		     @isdst ? ' DST' : '')
    end

    def inspect
      return to_s
    end
  end

  class LeapSecond
    def initialize(time, secs)
      @time = time
      @secs = secs
    end
    attr_reader :time, :secs
  end
end
