class TZFile
  def self.parse(input)
    magic, ttisgmtcnt, ttisstdcnt, leapcnt, timecnt, typecnt, charcnt =
      input.read(44).unpack('a4 x16 NNNNNN');
    p [magic, ttisgmtcnt, ttisstdcnt, leapcnt, timecnt, typecnt, charcnt]
    raise ParseError.new('Magic don\'t found') if magic != 'TZif'

    (1..timecnt).each {
      transition_time = input.read(4).unpack('N')[0]
      p [transition_time]
    }

    (1..timecnt).each {
      localtime_type = input.read(1).unpack('C')[0]
      p [localtime_type]
    }

    (1..typecnt).each {
      gmtoff, isdst, abbrind = input.read(6).unpack('NCC')
      p [gmtoff, isdst, abbrind]
    }

    zone_abbrev = input.read(charcnt)
    p [zone_abbrev]

    (1..leapcnt).each {
      leaptime, secs = input.read(8).unpack('NN')
      p [leaptime, secs]
    }

    (1..ttisstdcnt).each {
      isdst = input.read(1).unpack('C')[0]
      p [:isdst, isdst]
    }

    (1..ttisgmtcnt).each {
      utc_local = input.read(1).unpack('C')[0]
      p [:utc_local, utc_local]
    }
    p input.read
  end

  class ParseError < StandardError
  end
end
