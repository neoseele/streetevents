# encoding: UTF-8

require 'net/http'
require 'net/https'
require 'uri'
require 'pp'
require 'erb'
require 'csv'
require 'optparse'
require 'ostruct'
require 'logger'
require 'nokogiri'

### constants

USERNAME = 'vragunathan'
PASSWORD = 'uniqueens'

USERAGENT = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.1) Gecko/20060111 Firefox/1.5.0.1'

OUTPUT = 'out.txt'

### functions

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

def fetch(uri_str, limit = 10)
  # You should choose better exception.
  raise ArgumentError, 'HTTP redirect too deep' if limit == 0

  url = URI.parse(uri_str)
  req = Net::HTTP::Get.new(url.path, { 'User-Agent' => USERAGENT })
  response = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
	cookie = res.response['set-cookie']
  case response
  when Net::HTTPSuccess     then response
  when Net::HTTPRedirection then fetch(response['location'], limit - 1)
  else
    response.error!
  end
end

def cookieform
	url = URI.parse('https://www.streetevents.com')
  http = Net::HTTP.new url.host, url.port
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  http.use_ssl = true
  path = '/cookieTest.aspx?Destinations=&LoginPage=%2flogin.aspx&JavascriptURL='

  resp = http.get2(path, {'User-Agent' => USERAGENT})
  cookie = resp.response['set-cookie']

	pp resp
	resp.body.each_line do |l|
		puts l
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
    "uname=#{USERNAME}&" +
    "pwd=#{PASSWORD}&" +
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

	pp sd
	pp ed
	pp cc
	pp page

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

def fetch_download_links(resp)
	links = []
	resp.body.each_line do |line|
		if line =~ /text\.thomsonone\.com/
			#puts line
			line.scan(/javascript:DownloadDocument\(&#39;\S+&#39;\)/).each do |s|
				link = /javascript:DownloadDocument\(&#39;(.*)&#39;\)/.match(s)[1]
				links << link.gsub('amp;','')
			end
		end
	end
	links.each do |l|
		out(l)
	end
end

def num_of_pages(resp)
	doc = Nokogiri::HTML(resp.body)
	options = doc.css("#gridTranscriptList_ctl00_ddlPages option")
	return options.length unless options.nil?
	0
end

def out(line)
	File.open(OUTPUT, 'a') do |f|
		f.puts line
	end
end

### main

http,cookie = login

start_date = Date.new(2007,9,1)
end_date = Date.new(2007,9,5)

sd_str = start_date.strftime("%Y-%m-%d")
ed_str = end_date.strftime("%Y-%m-%d")

out("* Earning transcripts (#{sd_str} - #{ed_str})")

(start_date..end_date).to_a.each do |d|
	d_str = d.strftime("%Y-%m-%d")
	out("* #{d_str}")

	params = {
		:start_date => d,
		:end_date => d.next,
		:country_code => 'US'
	}
	resp = transcripts(cookie,params)
	nop = num_of_pages(resp)

	if nop > 0
		(1..nop).to_a.each do |page|
			params[:page] = page
			resp = transcripts(cookie,params)
			fetch_download_links(resp)
		end
	else
		resp = transcripts(cookie,params)
		fetch_download_links(resp)
	end
end
