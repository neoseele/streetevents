require 'rubygems'
require 'logger'
require 'pp'
require 'optparse'
require 'ostruct'
require 'date'
require 'yaml'
require 'csv'

### classes

class String
  def clean_up
    self.scan(/[[:print:]]/).join.strip
  end
end

class Base
  USERAGENT = 'Mozilla/5.0 (X11; Linux i686; rv:21.0) Gecko/20100101 Firefox/21.0'

  attr_accessor :log, :stdout, :csv

  def initialize
    log_dt_format = "%Y-%m-%d %H:%M:%S"
    @log = Logger.new('out.log')
    @log.datetime_format = log_dt_format
    @log.level = Logger::INFO

    @stdout = Logger.new(STDOUT)
    @stdout.datetime_format = log_dt_format
    @stdout.level = Logger::DEBUG
  end

  def info(msg)
    @log.info msg
    @stdout.info msg
  end

  def err(msg)
    @log.error msg
    @stdout.error msg
  end

  def csv_out(path)
    CSV.open(path, 'wb') do |csv|
      @csv.each do |arr|
        csv << arr
      end
    end
  end

  def slice_datetime(str)
    begin
      datetime = DateTime.parse(str)
      date = datetime.strftime('%Y-%m-%d')
      time = datetime.strftime('%H:%M')
      return [date,time]
    rescue ArgumentError
      return ['', '']
    end
  end
end
