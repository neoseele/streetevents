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
require 'csv'
require 'cgi'

### constants

CONFIG = 'config.yaml'
USERAGENT = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.1) Gecko/20060111 Firefox/1.5.0.1'
STREETEVENTS = 'http://www.streetevents.com'
STREETEVENTS_HTTPS = 'https://www.streetevents.com'

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

def get_response(path)
  uri = URI.parse(STREETEVENTS)
  http = Net::HTTP.new uri.host, uri.port
  resp = http.request_get(path, {'User-Agent' => USERAGENT, 'Cookie' => @cookie})
  show_body(resp) if @debug
  return http, resp
end

def logged_in?(resp)
  resp.response['set-cookie'].split(' ').each_with_object([]){|c, ary| ary << c if c =~ /^SE%/}.length > 1
end

def login
  uri = URI.parse(STREETEVENTS_HTTPS)
  http = Net::HTTP.new uri.host, uri.port
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  http.use_ssl = true
  path = '/cookieTest.aspx'

  resp = http.request_get(path, {'User-Agent' => USERAGENT})
  cookie = get_cookie(resp)
  pp cookie if @debug

  headers = {
    'User-Agent' => USERAGENT,
    'Cookie' => cookie,
    'Referer' => STREETEVENTS_HTTPS + '/cookieTest.aspx',
    'Content-Type' => 'application/x-www-form-urlencoded'
  }

  data = "Destinations=&JavascriptURL=&CookieTest=OK"

  resp = http.post('/Login.aspx', data, headers)
  cookie = get_cookie(resp)
  pp cookie if @debug

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
    'Referer' => STREETEVENTS_HTTPS + '/Login.aspx',
    'Content-Type' => 'application/x-www-form-urlencoded'
  }

  resp = http.post('/login.aspx', data, headers)
  cookie = get_cookie(resp)
  pp cookie if @debug

  unless logged_in?(resp)
    puts '* Incorrect Username or Password'
    exit 1
  end

  puts "* Logged in as #{@username}"
  @cookie = cookie
end

def create_dir(ticker, company)
  dir = "#{ticker}_#{company}"
  FileUtils.mkdir dir unless File.directory? dir
  dir
end

def search(ticker)
  path = "/capsule/TranscriptList.aspx?forceSearch=false&s=#{ticker.downcase}&st=1&r=0&d=1&silo=64&func="
  http,resp = get_response(path)

  doc = Nokogiri::HTML(resp.body)
  tables = doc.css('table')

  # the page has 2 tables
  # if table #1 has 2 tr>td>b, the text of the second one will be 'No Matches Were Found.'
  # if table #1 has just 1 tr>td>b, ticker search returns 1 or more results

  if tables[0].css('tr td b').length == 1
    doc.css('table')[1].css('tbody tr').each do |tr|
      real_ticker = tr.css('td')[0].text.gsub(/[[:space:]]/,'')
      a = tr.css('a')[0]
      company = a.text.gsub(/\W/,'_').strip
      path = a['href']

      transcript(path, real_ticker, company)
    end
  else
    out("no matches found for ticker: #{ticker}")
  end
end

def transcript(path, ticker, company)
  http,resp = get_response(path)

  doc = Nokogiri::HTML(resp.body)
  if doc.css('#gridTransList thead tr')[1].text.strip.include? 'no data available'
    out("no transcript found for #{ticker} - #{company}")
  else
    options = doc.css("#gridTransList_ctl00_ddlPages option")
    pages = options.nil? ? 1 : options.length
    (1..pages).to_a.each do |page|
      fetch(http, resp, ticker, company, path, page)
    end
  end
end

def fetch(http,resp, ticker, company, path, page)
  # get cid from path
  cid = CGI::parse(path.split('?')[1])['cid'][0]

  viewstate = ''
  resp.body.each_line do |line|
    if line =~ /_VIEWSTATE/
      viewstate = /value=\"(.*)\"/.match(line)[1]
      break
    end
  end
  #pp viewstate

  form_enum = {
    '__EVENTARGUMENT' => '',
    '__EVENTTARGET' => 'gridTransList$ctl00$ddlPages',
    '__LASTFOCUS' => '',
    '__VIEWSTATE' => viewstate,
    'cid' => cid,
    'gridTranscriptList$ctl00$ddlPages' => page,
    'siteId' => '1',
  }
  data = URI.encode_www_form(form_enum)

  headers = {
    'User-Agent' => USERAGENT,
    'Cookie' => @cookie,
    'Referer' => STREETEVENTS + path,
    'Content-Type' => 'application/x-www-form-urlencoded'
  }

  resp = http.post(path, data, headers)
  resp.body.each_line do |line|
    if line =~ /text\.thomsonone\.com/
      #puts line
      line.scan(/javascript:DownloadDocument\(&#39;\S+&#39;\)/).each do |s|
        url = /javascript:DownloadDocument\(&#39;(.*)&#39;\)/.match(s)[1].gsub('amp;','')
        if @dl
          download(ticker, company, url)
        else
          out("#{ticker} | #{company} | #{url}")
        end
      end
    end
  end
end

def out(line)
  File.open(@output, 'a') do |f|
    f.puts line
  end
end

def download(ticker, company, url)
  dir = create_dir(ticker, company)

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
@opts.on('-i', "--input CSV", String, 'Require: inpurt CSV file') do |i|
  options.input = i if File.exist?(i)
end
@opts.on('-d', "--download", 'Download Trascripts immediately') do |d|
  options.download = d
end
@opts.on('-v', "--debug", 'Show debug message') do |v|
  options.debug = v
end
@opts.on_tail("-h", "--help", "Show this message") do
  puts @opts
  exit
end
@opts.parse! rescue usage

### main

csv = options.input
usage if csv.nil?

@debug = options.debug
@output = 'out.txt'

# download the files immediately?
@dl = options.download

# load config
cfg = load_config
@username = cfg['login']['username']
@password = cfg['login']['password']

# backup the previous output file if it exists
FileUtils.mv(@output, @output.sub(/\.txt$/,'_bak.txt')) if @dl.nil? and File.exist?(@output)

# login
login

CSV.foreach(csv, {:headers => true}) do |r|
  ticker = r['of_ticker']
  search(ticker)
end

puts "* done !"
