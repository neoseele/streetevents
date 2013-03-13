require 'date'
require 'pp'
require 'csv'
require 'logger'

class Entry
	attr_accessor :no_words,:no_questions,:no_words_having_questions
	attr_reader :ticker,:ca

	def initialize(row)
		@ticker = row[0]
		@date = row[1]
		@reason = row[3]
		@ca = row[4]
		@first_nm = row[5]
		@surname = row[6]
		@affln = row[7]
		@firm = row[8]
		@jobt = row[9]
		@no_words = row[10].to_i
		@no_questions = row[11].to_i
		@no_words_having_questions = row[12].to_i
	end

	def full_name
		"#{@first_nm} #{@surname}"
	end

	def same_tk_ca_name?(b)
		@ticker == b.ticker and @ca == b.ca and full_name == b.full_name
	end

	def to_a
		[@ticker,@date,@reason,@ca,@first_nm,@surname,@affln,@firm,@jobt,@no_words,@no_questions,@no_words_having_questions]
	end
end

class Qa
	attr_accessor :q, :a
	
	def initialize(q, a={})
		@q = q
		@a = a
	end
end

### functions

def usage
	puts 'Usage: ' + File.basename(__FILE__) + ' <csv>'
	exit 1
end

def write_to_csv(content, path)
	CSV.open(path, 'wb') do |csv|
		content.each do |arr|
			csv << arr
		end
	end
end

usage unless ARGV.length == 1 and File.extname(ARGV[0]) == ".csv"

input = ARGV[0]
output_dir = File.dirname(input)
output_file = File.basename(input).gsub(/\W+/,'_') + '_squashed.csv'
output = File.join(output_dir, output_file)

rows = CSV.read(input, {:headers => :false})

qas = []
current_qa = nil

#i = 10

rows.each do |r|
	#i -= 1
	#break if i <= 0

	e = Entry.new(r)
	
	# first q
	if current_qa.nil?
		if e.ca == 'A'
			current_qa = Qa.new(e)
			qas << current_qa
		end
		next
	end

	current_q = current_qa.q

	# ca => A
	
	if e.ca == 'A'
		# same ticker, same ca, same full_name
		if e.same_tk_ca_name? current_q
			current_q.no_words += e.no_words
			current_q.no_questions += e.no_questions
			current_q.no_words_having_questions += e.no_words_having_questions
			next
		end

		# create a new qa object for anything else
		current_qa  = Qa.new(e)
		qas << current_qa
		next
	end

	# ca => C

	# same ticker
	if e.ticker == current_q.ticker
		current_a = current_qa.a

		if current_a.key?(e.full_name)
			# found a existing C in answer hash
			a = current_a[e.full_name]
			a.no_words += e.no_words
			a.no_questions += e.no_questions
			a.no_words_having_questions += e.no_words_having_questions
		else
			# new C
			current_qa.a[e.full_name] = e
		end

	end

end

#pp qas.length

@csv = [['ticker','date','reason','ca','first_nm','surname','affln','firm','jobt','no_words','no_questions','no_words_having_questions','no_people_respond']]

qas.each do |qa|
	@csv << qa.q.to_a + [qa.a.length]
	qa.a.values.each do |e|
		@csv << e.to_a
	end
end

## write to csv
write_to_csv(@csv, output)

