require 'win32ole'
require 'date'
require 'pp'
require 'find'
require 'csv'
require 'logger'

### classes

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
    qw_regex = "(what|where|when|which|who|whom|would|do|does|doesn't|is|isn't|can|could|to what exten|should|was|has|how|which|if)\W+"
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

### functions

def usage
  puts 'Usage: ' + File.basename(__FILE__) + ' <directory>'
  exit 1
end

def debug(msg)
  return unless DEBUG
  if msg.is_a? String
    puts msg
  else
    pp msg
  end
end

def err(msg)
  @log.error msg
  @stdout.error msg
end

def csv_out(content, path)
  CSV.open(path, 'wb') do |csv|
    content.each do |arr|
      csv << arr
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

  ## find ticker
  reason = pgs[2]
  ticker = reason.split(' - ')[0]
  dt_string = pgs[3][/Event Date\/Time: (.*)/,1]
  datetime = DateTime.parse(dt_string)
  date_str = datetime.nil? ? 'unknown' : datetime.strftime('%Y-%m-%d')
  time_str = datetime.nil? ? 'unknown' : datetime.strftime('%H:%M')

  debug "------------------"
  debug "Reason: " + reason
  debug "Ticker: " + ticker
  debug "DateTime: " + datetime.strftime('%Y%m%d')
  debug "------------------"

  ## find participants
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

  ## find Q&A
  qna_found = sents.join('|').squeeze(' ').match(/QUESTION AND ANSWER\|(.*DISCLAIMER)/)
  debug qna_found

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
      sub = k.gsub('. ','.|')
      qna_str.gsub!(sub, k)
    end
  end
  qna_contents = qna_str.split('|') 
  
  search_strings = pps.keys
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

  qnas.each do |qna|
    next if qna.participant == 'Operator'
    debug '------------------------'
    debug qna.participant.to_s
    debug '# of words: ' + qna.num_of_words.to_s
    debug '# of questions: ' + qna.num_of_questions.to_s
    debug '# of words in questions: ' + qna.num_of_words_in_questions.to_s
    debug '------------------------'
  end

  ## build the csv array
  qnas.each do |qna|
    next if qna.participant == 'Operator'
    p = qna.participant
    @csv << [ticker,date_str,time_str,reason,p.type,p.first_name,p.last_name,p.to_s,p.firm,p.title,qna.num_of_words,qna.num_of_questions,qna.num_of_words_in_questions]
  end
end

### main

usage unless ARGV.length == 1 and File.directory?(ARGV[0])

DEBUG = false

log_dt_format = "%Y-%m-%d %H:%M:%S"
@log = Logger.new('parse.log')
@log.datetime_format = log_dt_format
@log.level = Logger::INFO

@stdout = Logger.new(STDOUT)
@stdout.datetime_format = log_dt_format
@stdout.level = Logger::DEBUG

@word = WIN32OLE.new('Word.Application')
@word.visible = false

@csv = [['ticker','date','time','reason','ca','first_nm','surname','affln','firm','jobt','no_words','no_questions','no_words_having_questions']]

input = ARGV[0]
output_dir = File.dirname(input)
output_file = File.basename(input).gsub(/\W+/,'_') + '.csv'
output = File.join(output_dir, output_file)

Find.find(input) do |path|
  if File.directory? (path)
    next
  else
    if File.extname(path) == '.doc' and not File.basename(path) =~ /^\./
      msg = "Parsing [" + path + "]"
      @log.info msg
      @stdout.info msg
      parse(path)
    end
  end
end

## write to csv
csv_out(@csv, output)

@word.quit
