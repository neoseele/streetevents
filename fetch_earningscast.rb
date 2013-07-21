#!/usr/bin/env ruby
# encoding: UTF-8

require 'rubygems'
require 'net/http'
require 'net/https'
require 'uri'
require 'pp'
require 'erb'
require 'optparse'
require 'ostruct'
require 'logger'
require 'nokogiri'
require 'date'
#require 'yaml'
require 'csv'

### constants

USERAGENT = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.1) Gecko/20060111 Firefox/1.5.0.1'

### classes

class String
  def clean_up
    self.scan(/[[:print:]]/).join.strip
  end
end

### functions

def fetch(ticker)
  uri = URI.parse("http://www.earningscast.com/search?utf8=%E2%9C%93&query=#{ticker}&commit=")
  begin
    res = Net::HTTP.get_response(uri)
  rescue
    err "#{ticker} skipped: http error"
    return
  end

  doc = Nokogiri::HTML(res.body)
  calls = doc.css("#tab1 div[class^='item']")

  unless calls.length > 0
    err "#{ticker} skipped: no call found"
    return
  end

  calls.each do |div|
    t = div.css('div.info > a')[0].text.clean_up
    a = div.css('h3 > a')[0]
    date = div.xpath('./span').text.clean_up

    desc = a.text.clean_up
    uri = "http://www.earningscast.com#{a['href']}"
    @csv << [t, desc, uri, date]
  end

  info "#{ticker} data fetched"
end

def info(msg)
  @log.info msg
  @stdout.info msg
end

def err(msg)
  @log.error msg
  @stdout.error msg
end

def csv_out(content, path)
  CSV.open(path, 'wb') do |csv|
    content.each do |arr|
      csv << arr
    end
  end
end

def usage
  puts @opts
  exit 1
end

### logger
log_dt_format = "%Y-%m-%d %H:%M:%S"
@log = Logger.new('out.log')
@log.datetime_format = log_dt_format
@log.level = Logger::INFO
@stdout = Logger.new(STDOUT)
@stdout.datetime_format = log_dt_format
@stdout.level = Logger::DEBUG

### options
options = OpenStruct.new
@opts = OptionParser.new
@opts.banner = "Usage: #{File.basename($0)} [options]"
@opts.on('-s', "--source FILE", String, 'Require: input source') do |s|
  options.source = s if File.exist?(s)
end
@opts.on_tail("-h", "--help", "Show this message") do
  puts @opts
  exit
end
@opts.parse! rescue usage

### main
usage if options.source.nil?

@csv = [['ticker','desc','url','date']]

# read the ticker list
data = CSV.read(options.source, :headers => true, :encoding => 'UTF-8')
data.each do |r|
  puts r[0]
  fetch r[0].downcase.clean_up
  #break
end
#pp @csv
csv_out(@csv, 'result.csv')
