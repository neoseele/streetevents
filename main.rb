require 'win32ole'
require 'date'
require 'pp'
require 'find'
require 'csv'
require 'logger'

class Participant
	attr_accessor :first_name, :last_name, :firm, :title, :type

	def initialize(name_str, firm_title_str, type)
		@first_name, @last_name = name_str.split(' ', 2)
		@firm, @title = firm_title_str.split(' - ', 2) unless firm_title_str.nil?
		@type = type
	end

	## ex: Thomas A. Moore - Biopure Corporation - President, CEO and Director
	def to_s
		str = @first_name
		str += ' ' + @last_name unless @last_name.nil?
		str += ' - ' + @firm unless @firm.nil?
		str += ' - ' + @title unless @title.nil?
		return str
	end
end

class Qna
	attr_accessor :index, :participant, :sentences

	def initialize
		@sentences = []
	end

	def questions
		questions = []
		@sentences.each do |s|
			questions << s if s =~ /\?/
		end
		questions
	end

	def num_of_words(sentences=@sentences)
		count = 0
		sentences.each do |s|
			#puts s
			s.split(' ').each do |w|
				count += 1 unless w =~ /^\W+$/
			end
		end
		count
	end

	def num_of_questions
		questions.size
	end

	def num_of_words_in_questions
		num_of_words(questions)
	end
	
end

def usage
	puts 'Usage: ' + File.basename(__FILE__) + ' <directory>'
	exit 1
end

def out(msg)
	puts '---------------'
	pp msg
	puts '---------------'
end

def err(msg)
	@log.error msg
	out msg
end

def to_csv(content, path)
	#unless File.exist?(path)
		CSV.open(path, 'wb') do |csv|
			content.each do |arr|
				csv << arr
			end
		end
	#end
end

def count_word_frequence(sentences, word_freq={})
	sentences.each do |s|
		s.split(' ').each do |w|
			cw = w.downcase.gsub(/\W/, '')
			next unless cw != ''

			if word_freq[cw].nil?
				word_freq[cw] = 1
			else
				word_freq[cw] += 1
			end	
		end
	end
	word_freq
end

def parse(file)
	## read content from word
	pgs = []
	sents = []

	doc = @word.documents.open(file, 'ReadOnly' => true)
	doc.paragraphs.each do |p|
		pg = p.range.text.scan(/[[:print:]]/).join.strip
		pgs << pg
		break if pg =~ /PRESENTATION|TRANSCRIPT/
	end
	doc.sentences.each do |s|
		sent = s.text.scan(/[[:print:]]/).join.strip
		sents << sent unless sent == ''
	end
	@word.activedocument.close

	## processing headers
	headers = []
	pgs.each do |pg|
		next if pg == ''
		break if pg == 'CORPORATE PARTICIPANTS'
		headers << pg
	end
	reason = headers[2]
	ticker = reason.split(' - ')[0]
	datetime = DateTime.parse(headers[3].match(/Event Date\/Time: (.*)/)[1])

	puts "------------------"
	puts "Reason: " + reason
	puts "Ticker: " + ticker
	puts "DateTime: " + datetime.strftime('%Y%m%d')
	puts "------------------"

	## processing participants
	pgs_str = pgs.join('|')
	#pp pgs_str
	cps = pgs_str.match(/CORPORATE PARTICIPANTS\|(.*)CONFERENCE CALL PARTICIPANTS\|/)[1].gsub(/ \(\w*\)/, '').split('|')
	ccps = pgs_str.match(/CONFERENCE CALL PARTICIPANTS\|(.*)(PRESENTATION|TRANSCRIPT)/)[1].gsub(/ \(\w*\)/, '').split('|')

	#pp cps
	#pp ccps

	## create participant objects
	pps = {}
	# create cps
	(0..cps.length - 1).step(2).each do |i|
		pp = Participant.new(cps[i], cps[i+1], 'C')
		pps[pp.to_s] = pp
	end
	# create ccps
	(0..ccps.length - 1).step(2).each do |i|
		pp = Participant.new(ccps[i], ccps[i+1], 'A')
		pps[pp.to_s] = pp
	end
	pps['Operator'] = 'Operator'
	pp pps

	## find Q&A
	qna_found = sents.join('|').squeeze(' ').match(/QUESTION AND ANSWER\|(.*DISCLAIMER)/)
	#out qna_found

	## do not proceed if no Q&A is found
	if qna_found.nil?
		msg = File.basename(file) + " skipped: [Question and Answer] section is missing"
		err msg
		return
	end

	## senatize Q&A
	#
	# say we have a participant named: Thomas A. Moore
	# ms word stupidly think "Thomas A." is a sentence, since it have a dot in it
	# as such, after the previous "sents.join('|')" call, "Thomas A. Moore" will turn into
	# "Thomas A.|Moore" in string "qna_str"
	# 
	qna_str = qna_found[1]
	pps.each_key do |k|
		if k =~ /\. /
			#pp k
			sub = k.gsub('. ','.|')
			#pp sub
			qna_str.gsub!(sub, k)
		end
	end
	qna_contents = qna_str.split('|')
	#out qna_contents

	search_strings = pps.keys
	#out(search_strings)

	current_qna = nil
	qnas = []

	qna_contents.each_with_index do |value, index|
		if value == 'DISCLAIMER'
			qnas << current_qna.clone unless current_qna.nil?
			break
		end
		# found a match
		# save the current qna object to qnas if it exist
		# create a new qna object
		if search_strings.include? value
			qnas << current_qna.clone unless current_qna.nil?
			current_qna = Qna.new
			current_qna.index = index
			current_qna.participant = pps[value]
		else
			current_qna.sentences << value unless current_qna.nil?
		end
	end

	#out(qnas)
	qnas.each do |qna|
		next if qna.participant == 'Operator'
		#puts '------------------------'
		#puts qna.participant.to_s
		#puts '# of words: ' + qna.num_of_words.to_s
		#puts '# of questions: ' + qna.num_of_questions.to_s
		#puts '# of words in questions: ' + qna.num_of_words_in_questions.to_s
		#puts '------------------------'

		count_word_frequence(qna.sentences, @word_freq) if qna.participant.type == 'A'
	end
end

usage unless File.exist?(ARGV[0])

log_dir = File.expand_path("..",File.dirname(__FILE__))
@log = Logger.new(File.join(log_dir, 'parse.log'))
@log.level = Logger::INFO

@word = WIN32OLE.new('Word.Application')
@word.visible = false

@word_freq = {}
#=begin
input = ARGV[0]

if File.directory?(input)
	Find.find(input) do |path|
		if File.directory? (path)
			next
		else
			if File.extname(path) == '.doc' and File.basename(path) =~ /^\w/
				@log.info "Parsing [" + path + "]"
				parse(path)
			end
		end
	end
else
	parse(input)
end

#=end
to_csv(@word_freq.to_a.sort {|a,b| b[1] <=> a[1]}, 'c:\temp\out.csv')

@word.quit
