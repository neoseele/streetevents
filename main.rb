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
		qw_regex = "(what|where|when|which|who|whom|would|do|does|doesn't|is|isn't|can|could|to what exten|should)\W+"
		questions = []
		@sentences.each do |s|
			if s =~ /\?/
				questions << s 
				next
			end
			questions << s if s.downcase =~ /^#{qw_regex}/
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
	#exit 1
end

def out(msg)
	puts '---------------'
	pp msg
	puts '---------------'
end

def write_to_csv(content, path)
  unless File.exist?(path)
    CSV.open(path, 'wb') do |csv|
      content.each do |arr|
        csv << arr
      end
    end
  end
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
		pgs << pg unless pg == ''
		break if pg == "PRESENTATION" or pg == "TRANSCRIPT" or pg == "QUESTION AND ANSWER"
	end
	doc.sentences.each do |s|
		sent = s.text.scan(/[[:print:]]/).join.strip
		sents << sent unless sent == ''
	end
	@word.activedocument.close

	#pp pgs
	reason = pgs[2]
	ticker = reason.split(' - ')[0]
	datetime = DateTime.parse(pgs[3].match(/Event Date\/Time: (.*)/)[1])
	dt = datetime.strftime('%Y%m%d')

	puts "------------------"
	puts "Reason: " + reason
	puts "Ticker: " + ticker
	puts "DateTime: " + datetime.strftime('%Y%m%d')
	puts "------------------"

	## find and senatize Q and A contents
	#qna_contents = sents.join('|').gsub('|-', ' -').squeeze(' ').match(/QUESTION AND ANSWER\|(.*DISCLAIMER)/)[1].split('|')
	qna_contents = sents.join('|').squeeze(' ').match(/QUESTION AND ANSWER\|(.*DISCLAIMER)/)[1]

	# dealing the affiliation that have the annoying '.'
	# for some reason, doc.sentences break the word doc into sentences by '.'
	# which break the following affiliation into 2 sentences
	# ie. Quintin Lai  - Robert W. Baird - Analyst

	## processing participants
	cps = []
	ccps = []
	
	p_flag = nil
	pgs.each do |pg|
		if pg == "CORPORATE PARTICIPANTS"
			p_flag = 'cp'
			next
		end

		if pg == "CONFERENCE CALL PARTICIPANTS"
			p_flag = 'ccp'
			next
		end

		break if pg == "PRESENTATION" or pg == "TRANSCRIPT" or pg == "QUESTION AND ANSWER"

		cps << pg.gsub(/ \(\w*\)/, '') if p_flag == 'cp'
		ccps << pg.gsub(/ \(\w*\)/, '') if p_flag == 'ccp'
	end

	pps = {}
	unless cps.length == 0
		(0..cps.length - 1).step(2).each do |i|
			pp = Participant.new(cps[i], cps[i+1], 'C')
			pps[pp.to_s] = pp
		end
	end
	unless ccps.length == 0
		(0..ccps.length - 1).step(2).each do |i|
			pp = Participant.new(ccps[i], ccps[i+1], 'A')
			pps[pp.to_s] = pp
		end
	end
	pps['Operator'] = 'Operator'

	
	
	#out qna_contents

	search_strings = pps.keys
	out(search_strings)

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
	word_freq = {}

	qnas.each do |qna|
		next if qna.participant == 'Operator'
		puts '------------------------'
		puts qna.participant.to_s
		#puts '# of words: ' + qna.num_of_words(qna.sentences).to_s
		puts '# of words: ' + qna.num_of_words.to_s
		puts '# of questions: ' + qna.num_of_questions.to_s
		puts '# of words in questions: ' + qna.num_of_words_in_questions.to_s
		puts '------------------------'

		#count_word_frequence(qna.sentences, word_freq) if qna.participant.type == 'A'
		#count_word_frequence(qna.sentences, word_freq)
	end

	#repeated_words = {}
	#word_freq.each { |w, c| repeated_words[w] = c if c > 1 }
	#out repeated_words.sort_by {|k,v| v}.reverse
	
	## build the csv array
	csv = [['ticker','dt','reason','ca','first_nm','surname','affln','firm','jobt','analyst_showsup','no_words','no_questions','no_words_having_questions']]
	qnas.each do |qna|
		next if qna.participant == 'Operator'
		p = qna.participant

		csv << [ticker,dt,reason,p.type,p.first_name,p.last_name,p.to_s,p.firm,p.title,'?',qna.num_of_words,qna.num_of_questions,qna.num_of_words_in_questions]
	end

	## write to csv
	#write_to_csv(csv,'test.csv')
end

usage unless File.directory?(ARGV[0])

log_dir = File.expand_path("..",File.dirname(__FILE__))
@log = Logger.new(File.join(log_dir, 'parse.log'))
@log.level = Logger::INFO

@word = WIN32OLE.new('Word.Application')
@word.visible = false

parse(ARGV[0])
=begin
Find.find(ARGV[0]) do |path|
	if File.directory? (path)
		next
	else
		if File.extname(path) == '.doc' and File.basename(path) =~ /^\w/
			@log.info "Parsing [" + path + "]"
		end
	end
end
=end
@word.quit
