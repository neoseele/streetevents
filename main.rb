require 'win32ole'
require 'date'
require 'pp'

class Participant
	attr_accessor :first_name, :last_name, :firm, :title, :type

	def initialize(name_str, firm_title_str, type)
		@first_name, @last_name = name_str.split(' ', 2)
		@firm, @title = firm_title_str.split(' - ')
		@type = type
	end

	def to_s
		str = @first_name + ' ' + @last_name + ' - ' + @firm
		str += ' - ' + @title unless @title.nil?
		return str
	end
end

class Qna
	attr_accessor :index, :participant, :sentences

	def initialize
		@sentences = []
	end
end

file = ARGV[0]

## read content from word
pgs = []
sents = []

word = WIN32OLE.new('Word.Application')
word.visible = false
doc = word.documents.open(file, 'ReadOnly' => true)
doc.paragraphs.each do |p|
	pg = p.range.text.scan(/[[:print:]]/).join.strip
	pgs << pg unless pg == ''
	break if pg == "PRESENTATION"
end
doc.sentences.each do |s|
	sent = s.text.scan(/[[:print:]]/).join.strip
	sents << sent unless sent == ''
end
word.activedocument.close
word.quit

#pp pgs
reason = pgs[2]
ticker = reason.split(' - ')[0]
datetime = DateTime.parse(pgs[3].match(/Event Date\/Time: (.*)/)[1])

puts "------------------"
puts "Reason: " + reason
puts "Ticker: " + ticker
puts "DateTime: " + datetime.strftime('%Y%m%d')
puts "------------------"

## processing participants
tmp = pgs.join('|')
cps = tmp.match(/CORPORATE PARTICIPANTS\|(.*)CONFERENCE CALL PARTICIPANTS/)[1].gsub(/ \(\w*\)/, '').split('|')
ccps = tmp.match(/CONFERENCE CALL PARTICIPANTS\|(.*)PRESENTATION/)[1].gsub(/ \(\w*\)/, '').split('|')

pps = {}
(0..cps.length - 1).step(2).each do |i|
	pp = Participant.new(cps[i], cps[i+1], 'C')
	pps[pp.to_s] = pp
end
(0..ccps.length - 1).step(2).each do |i|
	pp = Participant.new(ccps[i], ccps[i+1], 'A')
	pps[pp.to_s] = pp
end

pps['Operator'] = 'Operator'

#pps.keys.each do |p|
#	puts p
#end

## find and senatize Q and A contents
qna_contents = sents.join('|').gsub('|-', ' -').squeeze(' ').match(/QUESTION AND ANSWER\|(.*DISCLAIMER)/)[1].split('|')

#puts "------------------"
#puts qna_contents
#puts "------------------"

current_qna = nil
qnas = []

search_strings = pps.keys

puts "------------------"
puts search_strings
puts "------------------"

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

puts "------------------"
pp qnas
puts "------------------"
