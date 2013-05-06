#!/usr/bin/env ruby

require 'date'
require 'pp'
require 'find'
require 'csv'
require 'logger'
#require 'tactful_tokenizer'
require 'stanford-core-nlp'

### classes

class Participant
  attr_accessor :first_name, :last_name, :affil, :title, :type

  def initialize(name_str, affil_str, type)
    @first_name, @last_name = name_str.split(' ', 2)
    @affil, @title = affil_str.split(' - ', 2) unless affil_str.nil?
    @type = type
  end

  ## ex: Thomas A. Moore - Biopure Corporation - President, CEO and Director
  def to_s
    str = @first_name
    str += ' ' + @last_name unless @last_name.nil?
    str += ', ' + @affil unless @affil.nil?
    str += ' - ' + @title unless @title.nil?
    return str
  end
end

class Qna
  attr_accessor :participant, :transcript, :sentences

  def initialize
    @transcript = ''
  end

  def questions
    qw_regex = "(what|where|when|which|who|whom|would|do|does|doesn't|is|isn't|can|could|to what exten|should|was|has|how|which|if)\W+"
    questions = []
    sentences.each do |s|
      if s =~ /\?/
        questions << s
        next
      end
      questions << s if s.downcase =~ /^#{qw_regex}/
    end
    questions
  end

  def num_of_words(sents=@sentences)
    count = 0
    sents = sentences if sents.nil?
    sents.each do |s|
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

  def sentences
    if @sentences.nil?
      #m = TactfulTokenizer::Model.new
      #@sentences = m.tokenize_text(@transcript)

      text = StanfordCoreNLP::Annotation.new(@transcript)
      @@pipeline.annotate(text)

      @sentences = []
      text.get(:sentences).each do |s|
        @sentences << s.to_s
      end
    end
    @sentences
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

def write_to_csv(content, path)
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


def parse_p(entry,type)
  participants = []

  h = Hash[entry.map.with_index.to_a]
  names = entry.select {|l| l =~ /^\*/}

  names.each do |n|
    name = n[1..-1].strip
    affil = entry[h[n]+1]
    participants << Participant.new(name, affil, type)
  end
  participants
end

def parse(file)
  txt = ''
  File.open(file, 'r').each do |line|
    l = line.strip
    l.gsub!(/\s+/, ' ')
    l.gsub!(/^=+$/, '===')
    l.gsub!(/^-+$/, '---')
    txt += "|#{l}" unless l == ''
  end
  sections = txt.split('===')
  #pp sections

  sections.collect! {|l| l[1..-2]} # remove the leading and trailing '|'
  header = sections.shift.split('|')
  #pp header

  ticker = header[2].split('-')[0].strip
  reason = header[3]
  datetime = DateTime.parse(header[4])
  date_str = datetime.nil? ? 'unknown' : datetime.strftime('%Y-%m-%d')
  time_str = datetime.nil? ? 'unknown' : datetime.strftime('%H:%M')

  # parse participants
  ops = {}
  h = Hash[sections.map.with_index.to_a]
  if h.has_key?(CP)
    cp = sections[h[CP]+1].split('|')
    parse_p(cp, 'C').each do |p|
      ops[p.to_s] = p
    end
  end
  if h.has_key?(CCP)
    ccp = sections[h[CCP]+1].split('|')
    parse_p(ccp, 'A').each do |p|
      ops[p.to_s] = p
    end
  end
  ops['Operator'] = 'Operator'
  #pp ops

  # parse questions and answers
  search_strings = ops.keys
  current_qna = nil
  qnas = []

  sections.select! {|l| l =~ /^#{QNA}/}
  qna_entries = sections.shift.split'|---|'
  qna_entries.each do |l|
    if l == 'Definitions' or l == 'Disclaimer'
      qnas << current_qna.clone unless current_qna.nil?
      break
    end

    # "Fred Ziegel,  Topeka Capital Markets - Analyst   [31]"
    l.gsub!(/\s+\[\d+\]$/, '')

    if search_strings.include?(l)
      qnas << current_qna.clone unless current_qna.nil?
      current_qna = Qna.new
      current_qna.participant = ops[l]
    else
      current_qna.transcript += l.gsub('|', ' ') unless current_qna.nil?
    end
  end

  ## build the csv array
  qnas.each do |qna|
    next if qna.participant == 'Operator'
    p = qna.participant
    @csv << [
      ticker,date_str,time_str,reason,
      p.type,p.first_name,p.last_name,p.to_s,p.affil,p.title,
      qna.num_of_words,qna.num_of_questions,qna.num_of_words_in_questions
    ]
  end

end

### main

usage unless ARGV.length == 1 and File.directory?(ARGV[0])

StanfordCoreNLP.jar_path = '/opt/stanford-core-nlp-minimal/'
StanfordCoreNLP.model_path = '/opt/stanford-core-nlp-minimal/'
StanfordCoreNLP.set_model('pos.model', 'english-left3words-distsim.tagger')
StanfordCoreNLP.use :english
@@pipeline =  StanfordCoreNLP.load(:tokenize, :ssplit)

DEBUG = false

CP = 'Corporate Participants'
CCP = 'Conference Call Participants'
QNA = 'Questions and Answers'

log_dt_format = "%Y-%m-%d %H:%M:%S"
@log = Logger.new('parse.log')
@log.datetime_format = log_dt_format
@log.level = Logger::INFO

@stdout = Logger.new(STDOUT)
@stdout.datetime_format = log_dt_format
@stdout.level = Logger::DEBUG

@csv = [['ticker','date','time','reason','ca',
  'first_nm','surname','affln','firm','jobt',
  'no_words','no_questions','no_words_having_questions']]

input = ARGV[0]
output_dir = File.dirname(input)
output_file = File.basename(input).gsub(/\W+/,'_') + '.csv'
output = File.join(output_dir, output_file)

Find.find(input) do |path|
  if File.directory? (path)
    next
  else
    if File.extname(path) == '.txt' and File.basename(path) =~ /^\w/
      msg = "Parsing [" + path + "]"
      @log.info msg
      @stdout.info msg
      parse(path)
    end
  end
end

## write to csv
write_to_csv(@csv, output)
