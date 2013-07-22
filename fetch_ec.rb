#!/usr/bin/env ruby
# encoding: UTF-8

require './base.rb'
require 'net/http'
require 'net/https'
require 'uri'
require 'erb'
require 'nokogiri'

class Fetcher < Base

  def fetch(ticker)
    uri = URI.parse("http://www.earningscast.com/search?utf8=%E2%9C%93&query=#{ticker}&commit=")
    begin
      res = Net::HTTP.get_response(uri)
    rescue
      err "#{ticker} skipped: http error"
      return
    end

    doc = Nokogiri::HTML(res.body)

    doc.css("#tab1 div[class^='item']").each do |div|
      next if div.text =~ /No events/
      t = div.css('div.info > a')[0].text.clean_up
      a = div.css('h3 > a')[0]
      date,time = slice_datetime(div.xpath('./span').text.clean_up)

      desc = a.text.clean_up
      uri = "http://www.earningscast.com#{a['href']}"
      @csv << [t, desc, uri, date, time]
    end

    info "#{ticker} data fetched"
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

f = Fetcher.new
f.csv = [['ticker','desc','url','date', 'time']]

# read the ticker list
data = CSV.read(options.source, :headers => true, :encoding => 'UTF-8')
data.each do |r|
  #puts r[0]
  f.fetch r[0].downcase.clean_up
end

# write to csv
f.csv_out('result.csv')
