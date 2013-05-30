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

    @call_date = Date.parse(@date).strftime("%Y%m%d")
  end

  def full_name
    "#{@first_nm} #{@surname}"
  end

  def =~(b)
    @ticker == b.ticker and @ca == b.ca and full_name == b.full_name
  end

  def merge(b)
    @no_words += b.no_words
    @no_questions += b.no_questions
    @no_words_having_questions += b.no_words_having_questions
  end

  def to_a
    [@ticker,@date,@reason,@ca,@first_nm,@surname,@affln,@firm,@jobt,@no_words,@no_questions,@no_words_having_questions,@call_date]
  end
end

class Qa
  attr_accessor :q, :a, :order

  def initialize(q, order=1, a={})
    @q = q
    @a = a
    @order = order
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

usage unless ARGV.length == 1 and File.exist?(ARGV[0]) and File.extname(ARGV[0]) == ".csv"

input = ARGV[0]
output_dir = File.dirname(input)
output_file = File.basename(input).sub(/\.csv$/,'_squashed.csv')
output = File.join(output_dir,output_file)

rows = CSV.read(input, {:headers => :false})

qas = []
last_qa = nil
order = 1

rows.each do |r|
  e = Entry.new(r)

  # save the first entry into last_qa
  if last_qa.nil?
    if e.ca == 'A'
      last_qa = Qa.new(e,order)
      qas << last_qa
    end
    next
  end

  last_q = last_qa.q

  # current entry is a A
  if e.ca == 'A'
    # same ticker and same full_name ? => merge them
    if e =~ last_q
      last_q.merge e
      next
    end

    # from this point, either ticker or full_name changed

    # ticker is the same ? increase order : reset order
    (e.ticker == last_q.ticker) ? order += 1 : order = 1

    # create a new qa object
    last_qa  = Qa.new(e,order)
    qas << last_qa
    next
  end

  # current entry is a C
  if e.ticker == last_q.ticker
    last_a = last_qa.a

    if last_a.key?(e.full_name)
      # a existing C found in answer hash => merge them 
      last_a[e.full_name].merge e
    else
      # new C found, add it into the answer hash
      last_qa.a[e.full_name] = e
    end
  end

end

#pp qas.length

@csv = [['ticker','date','reason','ca','first_nm','surname','affln','firm','jobt','no_words','no_questions','no_words_having_questions','call_date','no_people_respond','order']]

qas.each do |qa|
  @csv << qa.q.to_a + [qa.a.length,qa.order]
  qa.a.values.each do |e|
    @csv << e.to_a
  end
end

## write to csv
puts "* writing results to #{output}"
write_to_csv(@csv, output)

