require 'find'
require 'date'

class TZFile
  def self.zoninfo_directory
    for dir in ['/usr/share/zoneinfo', '/usr/share/lib/zoneinfo']
      if FileTest.directory? dir
        return dir
      end
    end
    raise ZoneInfoNotFound.new
  end
  class ZoneInfoNotFound < StandardError
  end

=begin
--- TZFile.each([directory]) {|name, tzfile| ...}
    Evaluate the block for each timezone file under "directory".
    If the directory is not specified, system dependent directory such as
    /usr/share/zoneinfo is used.
    "name" is a relative path from the directory and
    "tzfile" is a timezone object.
=end
  def self.each(dir=zoninfo_directory)
    Find.find(dir) {|name|
      if FileTest.file? name
	open(name) {|f|
	  begin
	    yield name, new(name, f)
	  rescue ParseError
	  end
	}
      end
    }
  end

  def self.parse(input, visitor)
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

=begin
--- TZFile.create(arg)
    Create timezone object.
    The argument can be:
    * absolute path to timezone file.
    * relative path to timezone file from system dependent timezone directory.
    * opened timezone file.
=end
  def self.create(arg)
    return new('<opend-file>', arg) if IO === arg
    if /^\// =~ arg 
      return open(arg) {|f| new(arg, f)}
    end
    return open(zoninfo_directory + '/' + arg) {|f| new(arg, f)}
  end

  def initialize(name, f)
    @name = name
    @type, @range_min, @range_type, @leapsecond = TZFile.parse(f, InitVisitor.new(self))
    (1...@range_type.length).each {|i|
      @range_min[i] = count_leapseconds(@range_min[i])
    }
  end
  attr_reader :name

=begin
--- each_range {|time1, timetype, time2| ...}
    Evaluate the block for each time range.
    For first time range, time1 will be true.
    For last time range, time2 will be false. 
=end
  def each_range
    (0...@range_type.length).each {|i|
      yield @range_min[i], @range_type[i], @range_min[i+1]
    }
    return nil
  end

=begin
--- each_transition {|timetype1, time, timetype2| ...}
=end
  def each_transition
    (1...@range_type.length).each {|i|
      yield @range_type[i - 1], @range_min[i], @range_type[i]
    }
    return nil
  end

=begin
--- each_closed_range {|time1, timetype, time2| ...}
    Like each_range but first and last time range is not used.
    I.e. time1 and time2 is always integer.
=end
  def each_closed_range
    (1...(@range_type.length - 1)).each {|i|
      yield @range_min[i], @range_type[i], @range_min[i+1]
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

=begin
--- uncount_leapseconds(time[, direction])
=end
  def uncount_leapseconds(t, dir=nil)
    secs = 0
    r = t
    @leapsecond.each {|l|
      return r if t < l.time
      if secs < l.secs # leapsecond insertion
	# (l.secs - secs) must be 1.
        if t == l.time
	  if dir == true
	    return uncount_leapseconds(t - 1, true)
	  elsif dir == false
	    return uncount_leapseconds(t + 1, false) # time2posix behavior
	  else
	    raise LeapSecondHit.new('inserted leapsecond', t)
	  end
	end
      end
      secs = l.secs
      r = t - l.secs
    }
    return r
  end

  class LeapSecondHit < StandardError
    def initialize(msg, time)
      super(msg)
      @time = time
    end
  end

  class InitVisitor
    def initialize(obj)
      @obj = obj
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

      return [timetype, range_min, range_type, leap]
    end
  end

  class DumpVisitor
    def method_missing(m, *args)
      print m
      p args
    end
  end

  class DumpVisitor2
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
      @type.each {|t|
        gmtoff, isdst, abbrind, isstd, isgmt = t
	abbrev = @zone_abbrev[abbrind...@zone_abbrev.index(?\0, abbrind)]
	t << abbrev
	print abbrev, ' ', gmtoff
	print ' dst' if isdst
	print ' std' if isstd
	print ' gmt' if isgmt
	print "\n"
      }
      @time.each {|transition_time, type|
        p [transition_time, type, @type[type][5]]
      }
      p @leap
    end
  end

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
  end

  class LeapSecond
    def initialize(time, secs)
      @time = time
      @secs = secs
    end
    attr_reader :time, :secs
  end

  class ParseError < StandardError
  end

  def tztime(time)
    tt = nil
    each_transition {|tt1, t, tt2|
      if time < t
        tt = tt1
	break
      end
      tt = tt2
    }
    gmtoff = tt.gmtoff
    isdst = tt.isdst
    zone = tt.abbrev

    x, leapsec = begin
		   [uncount_leapseconds(time), 0]
		 rescue LeapSecondHit
		   [uncount_leapseconds(time, true), 1]
		 end
	  
    x += gmtoff
    x, sec = x.divmod(60)
    x, min = x.divmod(60)
    x, hour = x.divmod(24)
    sec += leapsec # assumes sec==59 when leapsec!=0.  i.e. gmtoff%60==0.

    # 2440588 is the Julian day of 1970/01/01.
    date = Date.new1(2440588 + x, true)

    return [sec, min, hour,
            date.mday, date.mon, date.year,
	    date.wday, date.yday,
	    isdst, zone, gmtoff]
  end

  def at(time)
    Time.new(self, time)
  end

  class Time
    DayName = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
    MonthName = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

    def initialize(tz, time)
      @tz = tz
      @time = time
    end

    def inspect
      return to_s
    end

    def to_s
      sec, min, hour, mday, mon, year, wday, yday, isdst, zone, gmtoff = @tz.tztime(@time)
      gmtoff_sign = gmtoff < 0 ? '-' : '+'
      gmtoff = -gmtoff if gmtoff < 0
      x, gmtoff_sec = gmtoff.divmod(60)
      gmtoff_hour, gmtoff_min = x.divmod(60)
      return sprintf("%s %s %02d %02d:%02d:%02d %s %d (%s%02d:%02d:%02d %s)",
        DayName[wday], MonthName[mon - 1],
	mday, hour, min, sec, zone, year,
	gmtoff_sign, gmtoff_hour, gmtoff_min, gmtoff_sec,
	@tz.name
	)
    end
  end
end
