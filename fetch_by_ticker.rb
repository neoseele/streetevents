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
require 'fileutils'
require 'date'
require 'yaml'

### constants

CONFIG = 'config.yaml'
USERAGENT = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.1) Gecko/20060111 Firefox/1.5.0.1'

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

def logged_in?(resp)
  resp.response['set-cookie'].split(' ').each_with_object([]){|c, ary| ary << c if c =~ /^SE%/}.length > 1
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

  unless logged_in?(resp)
    puts '* Incorrect Username or Password'
    exit 1
  else
    puts "* Logged in as #{@username}"
    return http,cookie
  end
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

  headers = {
    'User-Agent' => USERAGENT,
    'Cookie' => cookie,
    'Referer' => 'http://www.streetevents.com/transcript/ListView.aspx',
    'Content-Type' => 'application/x-www-form-urlencoded'
  }

  resp = http.post(path, data, headers)
end

def fetch_links(resp, tag)
  resp.body.each_line do |line|
    if line =~ /text\.thomsonone\.com/
      #puts line
      line.scan(/javascript:DownloadDocument\(&#39;\S+&#39;\)/).each do |s|
        link = /javascript:DownloadDocument\(&#39;(.*)&#39;\)/.match(s)[1]
        line = tag + '|' + link.gsub('amp;','')
        if @dl
          fetch(line)
        else
          out(line)
        end
      end
    end
  end
end

def num_of_pages(resp)
  doc = Nokogiri::HTML(resp.body)
  options = doc.css("#gridTranscriptList_ctl00_ddlPages option")
  return options.length unless options.nil?
  0
end

def out(line)
  File.open(@output, 'a') do |f|
    f.puts line
  end
end

def fetch(line)
  dir,url = line.split('|')
  FileUtils.mkdir dir unless File.directory? dir

  # fetch text format only
  return unless url =~ /format=Text$/

  case RUBY_PLATFORM
  when /linux/, /darwin/
    `wget -P #{dir} -nc --content-disposition -t 3 "#{url}"`
  else
    system("wget.exe -P #{dir} -nc --content-disposition -t 3 \"#{url}\"")
  end

  # pause after each successful fetch
  pause
end

def pause
  count = rand(20..40)
  puts "* sleep #{count} seconds"
  sleep(count)
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
@opts.on('-d', "--download", 'Download files immediately') do |d|
  options.download = d
end
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
@output = sd.strftime('%Y%m%d') + '_' + ed.strftime('%Y%m%d') + '.txt'

# download the files immediately?
@dl = options.download

# load config
cfg = load_config
@username = cfg['login']['username']
@password = cfg['login']['password']

# backup the previous output file if it exists
FileUtils.mv(@output, @output.sub(/\.txt$/,'_bak.txt')) if @dl.nil? and File.exist?(@output)

# login
http,cookie = login

puts "* fetching transcript download links (#{sd_str} -> #{ed_str})"

(sd..ed).to_a.each do |d|
  # tag is used by the download script
  # to catagorise the downloaded transcripts
  # ie. tag => 2007-09
  tag = d.strftime('%Y-%m')

  d_str = d.strftime('%Y-%m-%d')
  puts ' ... ' + d_str + ' ... '
  out('# ' + d_str)

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
      fetch_links(resp, tag)
    end
  else
    resp = transcripts(cookie,params)
    fetch_links(resp, tag)
  end

  # pause a bit after each day is processed
  pause
end

puts "* done !"
