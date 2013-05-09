#!/usr/bin/env ruby

require 'date'
require 'pp'
require 'find'
require 'csv'
require 'logger'

### functions

def usage
  puts 'Usage: ' + File.basename(__FILE__) + ' <directory>'
  exit 1
end

def debug(msg)
  return unless DEBUG
  if msg.is_a? String
    puts msg
  else
    pp msg
  end
end

def err(msg)
  @log.error msg
  @stdout.error msg
end

def write_to_csv(content, path)
  CSV.open(path, 'wb') do |csv|
    content.each do |arr|
      csv << arr
    end
  end
end

def parse(file)
  txt = ''
  File.open(file, 'r').each do |line|
    l = line.strip
    l.gsub!(/\s+/, ' ')
    l.gsub!(/^=+$/, '===')
    l.gsub!(/^-+$/, '---')
    txt += "|#{l}" unless l == ''
  end
  sections = txt.split('===')
  #pp sections

  sections.collect! {|l| l[1..-2]} # remove the leading and trailing '|'
  header = sections.shift.split('|')
  #pp header

  ticker = header[2].split('-')[0].strip
  reason = header[3]
  datetime_str = header[4]

  datetime = DateTime.parse(datetime_str)
  date_str = datetime.strftime('%Y-%m-%d')
  time_str = datetime.strftime('%H:%M')

  timezone_str = datetime_str[/\W[A-Z]{2,}$/]
  timezone_str = timezone_str.strip unless timezone_str.nil?

  ## build the csv array
  @csv << [ticker,date_str,time_str,timezone_str,reason]
end

### main

usage unless ARGV.length == 1 and File.directory?(ARGV[0])

DEBUG = false

log_dt_format = "%Y-%m-%d %H:%M:%S"
@log = Logger.new('parse.log')
@log.datetime_format = log_dt_format
@log.level = Logger::INFO

@stdout = Logger.new(STDOUT)
@stdout.datetime_format = log_dt_format
@stdout.level = Logger::DEBUG

@csv = [['ticker','date','time','timezone','reason']]

input = ARGV[0]
output_dir = File.dirname(input)
output_file = File.basename(input).gsub(/\W+/,'_') + '.csv'
output = File.join(output_dir, output_file)

Find.find(input) do |path|
  if File.directory? (path)
    next
  else
    if File.extname(path) == '.txt' and not File.basename(path) =~ /^\./
      msg = "Parsing [" + path + "]"
      @log.info msg
      @stdout.info msg
      parse(path)
    end
  end
end

## write to csv
write_to_csv(@csv, output)
