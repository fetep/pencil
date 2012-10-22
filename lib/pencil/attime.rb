# partial re-implementation of graphite's AT-Style syntax parsing
# in particular, time reference is always 'now' and therefore only time offsets
# need be parsed
require 'time'
require 'date'

# months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec']
# weekdays = ['sun','mon','tue','wed','thu','fri','sat']

class DateTime
  def replace (hsh)
    h = {
      'year' => year,
      'month' => month,
      'day' => day,
      'hour' => hour,
      'minute' => minute,
      'second' => second
    }.merge(hsh)
    DateTime.new(h['year'], h['month'], h['day'], h['hour'], h['minute'])
  end
  unless DateTime.new.respond_to? :to_time
    def to_time
      Time.parse(self.to_s)
    end
  end

end

module ATTime
  class << self
    def parseATTime(s)
      s = s.strip.downcase.gsub('_', '').gsub(',', '').gsub(' ', '')
      if s =~ /^\d+$/
        if s.length == 8 && s[0..3].to_i > 1900 && s[3..5].to_i < 13 && s[5..-1].to_i < 32
          #Fall back because its not a timestamp, its YYYYMMDD form
        else
          return Time.at(s.to_i)
        end
      end
      if s.include?('+')
        ref, offset = s.split('+', 2)
        offset = '+' + offset
      elsif s.include?('-')
        ref, offset = s.split('-', 2)
        offset = '-' + offset
      else
        ref, offset = s, ''
      end
      return parseTimeReference(ref).to_time + parseTimeOffset(offset)
    end

    def parseTimeReference (ref)
      return DateTime.now if ref.empty? || ref == 'now'
      raise 'not implemented'

      # #Time-of-day reference
      # i = ref.index(':')
      # hour, min = 0, 0
      # if i
      #   hour = ref[0...i].to_i
      #   min = ref[i..i+2].to_i
      #   ref = ref[i+2..-1]
      #   if ref[0..1] == 'am'
      #     ref = ref[2..-1]
      #   elsif ref[0...2] == 'pm'
      #     hour = (hour + 12) % 24
      #     ref = ref[2..-1]
      #   end
      # end
      # if ref =~ /^noon/
      #   hour, min = 12, 0
      #   ref = ref[4..-1]
      # elsif ref =~ /^midnight/
      #   hour, min = 0,0
      #   ref = ref[8..-1]
      # elsif ref =~ /^teatime/
      #   hour, min = 16, 0
      #   ref = ref[7..-1]
      # end
      # refDate = DateTime.now.replace('hour' => hour, 'min' => min)

      # #Day reference
      # if ['yesterday', 'today', 'tomorrow'].include? ref #yesterday, today, tomorrow
      #   if ref == 'yesterday'
      #     refDate = (refDate.to_time - timedelta('days' => 1)).to_datetime
      #   end
      #   if ref == 'tomorrow'
      #     refDate = (refDate.to_time + timedelta('days' => 1)).to_datetime
      #   end
      # elsif ref.count('/') == 2 #MM/DD/YY[YY]
      #   m, d, y = ref.split('/').map(&:to_i)
      #   y += 1900 if y < 1900
      #   y += 100  if y < 1970
      #   refDate = refDate.replace('year' => y)

      #   begin # Fix for Bug #551771
      #     refDate = refDate.replace('month' => m)
      #     refDate = refDate.replace('day' => d)
      #   rescue
      #     refDate = refDate.replace('day' => d)
      #     refDate = refDate.replace('month' => m)
      #   end
      # elsif ref.length == 8 && ref =~ /^\d+$/ #YYYYMMDD
      #   refDate = refDate.replace('year' => ref[0...4].to_i)

      #   begin # Fix for Bug #551771
      #     refDate = refDate.replace('month' => ref[4...6].to_i)
      #     refDate = refDate.replace('day' => ref[6...8].to_i)
      #   rescue
      #     refDate = refDate.replace('day' => ref[6...8].to_i)
      #     refDate = refDate.replace('month' => ref[4...6].to_i)
      #   end
      # elsif months.include? ref[0...3] #MonthName DayOfMonth
      #   refDate = refDate.replace('month' => months.index(ref[0...3]) + 1)
      #   if ref[-2..-1] =~ /^\d+$/
      #     refDate = refDate.replace('day' => ref[-2..-1].to_i)
      #   elsif ref[-1..-1] =~ /^\d+$/
      #     refDate = refDate.replace('day' => ref[-1..-1].to_i)
      #   else
      #     raise Exception, "Day of month required after month name"
      #   end
      # elsif weekdays.include? ref[0...3] #DayOfWeek (Monday, etc)
      #   todayDayName = refDate.strftime("%a").downcase[0...3]
      #   today = weekdays.index todayDayName
      #   twoWeeks = weekdays * 2
      #   dayOffset = today - twoWeeks.index(ref[0...3])
      #   dayOffset += 7 if dayOffset < 0
      #   refDate = (refDate.to_time - timedelta('days' => dayOffset)).to_datetime
      # elsif ref
      #   raise Exception, "Unknown day reference"
      # end
      # return refDate
    end

    def parseTimeOffset(offset)
      if offset.empty?
        return 0
      end

      t = 0

      if offset[0] =~ /^\d+$/
        sign = 1
      else
        sign = { '+' => 1, '-' => -1 }[offset[0..0]] #1.8 compat
        offset = offset[1..-1]
      end

      while !offset.empty?
        i = 1
        i += 1 while offset[0...i] =~ /^\d+$/ && i <= offset.size
        num = offset[0...i-1].to_i
        offset = offset[i-1..-1]
        i = 1
        i += 1 while offset[0...i] =~ /^[[:alpha:]]+$/ && i <= offset.size
        unit = offset[0...i-1]
        offset = offset[i-1..-1]
        unitString = getUnitString(unit)
        if unitString == 'months'
          unitString = 'days'
          num *= 30
        end
        if unitString == 'years'
          unitString = 'days'
          num *= 365
        end
        t += timedelta(unitString => num * sign)
      end
      return t
    end

    def timedelta (hash)
      h = {
        'seconds' => 1,
        'minutes' => 60,
        'hours'  => 60 * 60,
        'days'    => 24 * 60 * 60,
        'weeks'  => 24 * 60 * 60 * 7,
      }
      h[hash.keys.first] * hash.values.first
    end

    def getUnitString (s)
      return 'seconds' if s =~ /^s/
      return 'minutes' if s =~ /^min/
      return 'hours'   if s =~ /^h/
      return 'days'    if s =~ /^d/
      return 'weeks'   if s =~ /^w/
      return 'months'  if s =~ /^mon/
      return 'years'   if s =~ /^y/
      raise Exception, "Invalid offset unit '%s'" % s
    end
  end
end

if __FILE__ == $0
  STDIN.readlines.each do |l|
    begin
      puts ATTime::parseATTime(l.chomp)
    rescue Exception => e
      raise e
    end
  end
end
