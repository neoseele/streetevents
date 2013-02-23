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

USERNAME="vragunathan"
PASSWORD="uniqueens"

USERAGENT = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.1) Gecko/20060111 Firefox/1.5.0.1'

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

	data = "Destinations=&" +
		"JavascriptURL=&" +
		"CookieTest=OK" 

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

	puts viewstate

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

def transcripts(cookie)
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
	pp viewstate

	sd1 = 'Feb+01,+2012'
	sd2 = '02/01/2012'
	ed1 = 'Feb+22,+2013'
	ed2 = '02/22/2013'

	data = "__EVENTARGUMENT=&" +
    "__EVENTTARGET=&" +
		"__VIEWSTATE=#{ERB::Util.url_encode(viewstate)}&" +
		"companySearchSilo=8&" +
		"companySearchText=&" +
		"companySearchType=1&" +
		"filterArea%24briefSummaryFilter=on&" +
		"filterArea%24countryCodeFilter=ALL&" +
		"filterArea%24ctl01%24ctl00=Feb+01%2C+2012&" +
		"filterArea%24ctl01%24hiddenDate=#{ERB::Util.url_encode(sd2)}&" +
		"filterArea%24ctl02%24ctl00=Feb+22%2C+2013&" +
		"filterArea%24ctl02%24hiddenDate=#{ERB::Util.url_encode(ed2)}&" +
		"filterArea%24eventTypeFilter%24ctl00=1074003971&" +
		"filterArea%24eventTypeFilter%24ctl00group1=1074003971&" +
		"filterArea%24industryCodeFilter=201010&" +
		"filterArea%24languageFilter=1&" +
		"filterArea%24transcriptDocumentStatusFilter%24Available=on&" +
		"filterArea%24watchlistFilter=0&" +
		"gridTranscriptList%24ctl00%24ddlPages=1&" +
		"siteId=1"
	
	#puts data

	headers = {
		'User-Agent' => USERAGENT,
		'Cookie' => cookie,
		'Referer' => 'http://www.streetevents.com/transcript/ListView.aspx',
		'Content-Type' => 'application/x-www-form-urlencoded'
	}

	resp = http.post(path, data, headers)
end

def get_download_links(resp)
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
	links
end
http,cookie = login
resp = transcripts(cookie)
#show_body(resp)
pp get_download_links(resp)
