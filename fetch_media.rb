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
require 'yaml'
require 'csv'

### constants

CONFIG = 'config.yaml'
USERAGENT = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.1) Gecko/20060111 Firefox/1.5.0.1'

### classes

class String
  def clean_up
    self.scan(/[[:print:]]/).join.squeeze.strip
  end
end

### functions

# Load in the YAML configuration file, check for errors, and return as hash 'cfg'
#
# Ex config.yaml:
#
# ---
# login:
#   username: xxx
#   password: xxx
#
def load_config
  cfg = File.open(CONFIG)  { |yf| YAML::load( yf ) } if File.exists?(CONFIG)
  # => Ensure loaded data is a hash. ie: YAML load was OK
  if cfg.class != Hash
     raise "ERROR: Configuration - invalid format or parsing error."
  else
    if cfg['login'].nil?
      raise "ERROR: Configuration: login not defined."
    end
  end

  return cfg
end

def view_response(resp)
  if @options[:debug]
    puts '------------------'
    puts 'Code = ' + resp.code
    puts 'Message = ' + resp.message
    resp.each {|key, val| puts key + ' = ' + val}
    puts '------------------'
    puts "\n"
  else
    pp resp
  end
end

def show_body(resp)
  resp.body.each_line { |line| puts line }
end

def get_cookie(resp)
  cookie = ''
  resp.response['set-cookie'].split(' ').each do |c|
    cookie += c if c =~ /^SE%/
  end
  return cookie.chomp(';')
end

def login
  url = URI.parse('https://www.streetevents.com')
  http = Net::HTTP.new url.host, url.port
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  http.use_ssl = true
  path = '/cookieTest.aspx'

  resp = http.get2(path, {'User-Agent' => USERAGENT})
  #cookie = resp.response['set-cookie'].split('; ')[0]
  cookie = get_cookie(resp)
  pp cookie

  headers = {
    'User-Agent' => USERAGENT,
    'Cookie' => cookie,
    'Referer' => 'https://www.streetevents.com/cookieTest.aspx',
    'Content-Type' => 'application/x-www-form-urlencoded'
  }

  data = "Destinations=&JavascriptURL=&CookieTest=OK" 

  resp = http.post('/Login.aspx', data, headers)
  #cookie = resp.response['set-cookie'].split('; ')[0]
  cookie = get_cookie(resp)
  pp cookie

  viewstate = ''
  resp.body.each_line do |line|
    if line =~ /__VIEWSTATE/
      viewstate = /value=\"(.*)\"/.match(line)[1]
      break
    end
  end

  #puts viewstate

  data = "__VIEWSTATE=#{ERB::Util.url_encode(viewstate)}&" +
    "Destinations=&" +
    "uname=#{@username}&" +
    "pwd=#{@password}&" +
    "post=true"

  headers = {
    'User-Agent' => USERAGENT,
    'Cookie' => cookie,
    'Referer' => 'https://www.streetevents.com/Login.aspx',
    'Content-Type' => 'application/x-www-form-urlencoded'
  }

  resp = http.post('/login.aspx', data, headers)
  #cookie = resp.response['set-cookie'].split('; ')[0]
  #cookie = resp.response['set-cookie']
  cookie = get_cookie(resp)
  pp cookie

  #show_body(resp)
  puts "* Logged in as #{@username}"
  return http,cookie
end

def events(http,cookie)
  cookie = cookie + ";filterview=expand"
  pp cookie
  headers = {
    'User-Agent' => USERAGENT,
    'Cookie' => cookie,
    'Referer' => 'https://www.streetevents.com/Login.aspx',
  }
  path = '/events/streetsheet.aspx'
  resp = http.get2(path, headers)
  show_body(resp)

  puts '---------------------'

  url = URI.parse('http://www.streetevents.com')
  http = Net::HTTP.new url.host, url.port
  path = "/events/streetsheet.aspx"
  resp = http.get(path, headers)
  show_body(resp)
end

def transcripts(cookie, params={})
  headers = {
    'User-Agent' => USERAGENT,
    'Cookie' => cookie
  }
  url = URI.parse('http://www.streetevents.com')
  http = Net::HTTP.new url.host, url.port
  path = "/transcript/ListView.aspx"
  resp = http.get2(path, headers)

  #show_body(resp)

  viewstate = ''
  resp.body.each_line do |line|
    if line =~ /_VIEWSTATE/
      viewstate = /value=\"(.*)\"/.match(line)[1]
      break
    end
  end
  #pp viewstate

  sd = params[:start_date]
  ed = params[:end_date]
  cc = params[:country_code]
  page = params[:page]

  #pp sd
  #pp ed
  #pp cc
  #pp page

  form_enum = {
    '__EVENTARGUMENT' => '',
    '__EVENTTARGET' => '',
    '__VIEWSTATE' => viewstate,
    'companySearchSilo' => '8',
    'companySearchText' => '',
    'companySearchType' => '1',
    'filterArea$briefSummaryFilter' => 'on',
    'filterArea$countryCodeFilter' => cc,
    'filterArea$ctl01$ctl00' => sd.strftime("%b %d, %Y"), # ie. Feb 01, 2012
    'filterArea$ctl01$hiddenDate' => sd.strftime("%m/%d/%Y"), # ie. 02/01/2012
    'filterArea$ctl02$ctl00' => ed.strftime("%b %d, %Y"),
    'filterArea$ctl02$hiddenDate' => ed.strftime("%m/%d/%Y"),
    'filterArea$eventTypeFilter$ctl00' => '1074003971',
    'filterArea$eventTypeFilter$ctl00group1' => '1074003971',
    'filterArea$industryCodeFilter' => '0',
    'filterArea$languageFilter' => '1',
    'filterArea$transcriptDocumentStatusFilter$Available' => 'on',
    'filterArea$watchlistFilter' => '0',
    'siteId' => '1'
  }
  form_enum['gridTranscriptList$ctl00$ddlPages'] = page unless page.nil?
  data = URI.encode_www_form(form_enum)
  #puts data
  #exit 0

  headers = {
    'User-Agent' => USERAGENT,
    'Cookie' => cookie,
    'Referer' => 'http://www.streetevents.com/transcript/ListView.aspx',
    'Content-Type' => 'application/x-www-form-urlencoded'
  }

  resp = http.post(path, data, headers)
end

def fetch_links(resp)
  doc = Nokogiri::HTML(resp.body)
  doc.css('table#gridTranscriptList tbody tr').each do |tr|
    a = tr.css('td[id$="media"] a')[0]
    eid = a['href'][/OpenMM\((\d+),/,1].strip
    expired = a.css('img')[0]['title'] =~ /^This audio archive has expired/
    next if expired

    ticker = tr.css('td[id$="ticker"]')[0].text.clean_up
    title = tr.css('td[id$="title"] a')[0].text.clean_up
    date = tr.css('td[id$="date"]')[0].text.clean_up
    media = "https://www.streetevents.com/eventcapsule/eventcapsule.aspx?m=p&cid=0&eid=#{eid}&source="

    @csv << [ticker,title,date,media]
  end
end

def num_of_pages(resp)
  doc = Nokogiri::HTML(resp.body)
  options = doc.css("#gridTranscriptList_ctl00_ddlPages option")
  return options.length unless options.nil?
  0
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
#log_dt_format = "%Y-%m-%d %H:%M:%S"
#@log = Logger.new('parse.log')
#@log.datetime_format = log_dt_format
#@log.level = Logger::INFO

### options
options = OpenStruct.new
@opts = OptionParser.new
@opts.banner = "Usage: #{File.basename($0)} [options]"
@opts.on('-s', "--start-date DATE", String, 
        'Require: specify date in format in "yyyy-mm-dd"') do |s|
  options.start_date = s if s =~ /\d{4}\-\d{2}\-\d{2}/
end
@opts.on('-e', "--end-date DATE", String, 
        'Require: specify date in format in "yyyy-mm-dd"') do |e|
  options.end_date = e if e =~ /\d{4}\-\d{2}\-\d{2}/
end
#@opts.on('-d', "--download", 'Download files immediately') do |d|
#  options.download = d
#end
@opts.on_tail("-h", "--help", "Show this message") do
  puts @opts
  exit
end
@opts.parse! rescue usage

### main

sd_str = options.start_date
ed_str = options.end_date
usage if sd_str.nil?
usage if ed_str.nil?

#sd = Date.new(2007,9,1)
#ed = Date.new(2007,9,5)
sd = Date.strptime(sd_str, '%Y-%m-%d')
ed = Date.strptime(ed_str, '%Y-%m-%d')
output = sd.strftime('%Y%m%d') + '_' + ed.strftime('%Y%m%d') + '.csv'

# download the files immediately?
@dl = options.download

# load config
cfg = load_config
@username = cfg['login']['username']
@password = cfg['login']['password']

# login
http,cookie = login

puts "* fetching transcript media links (#{sd_str} -> #{ed_str})"

@csv = [['ticker','title','date','media']]

(sd..ed).to_a.each do |d|
  d_str = d.strftime('%Y-%m-%d') 
  puts ' ... ' + d_str + ' ... '

  params = {
    :start_date => d,
    :end_date => d,
    :country_code => 'US'
  }
  resp = transcripts(cookie,params)
  nop = num_of_pages(resp)
  if nop > 0
    (1..nop).to_a.each do |page|
      params[:page] = page
      resp = transcripts(cookie,params)
      fetch_links(resp)
    end
  else
    resp = transcripts(cookie,params)
    fetch_links(resp)
  end
end

## write to csv
csv_out(@csv, output)

puts "* done !"
