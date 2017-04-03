#!/usr/bin/env ruby

require 'find'
require 'stanford-core-nlp'

## load the base class
require File.join(File.dirname($0), 'base.rb')

### classes

class Speaker
  attr_accessor :first_name, :last_name, :affil, :title, :type

  def initialize(str)
    name, @title, @affil = str.split(', ', 3)
    @first_name, @last_name = name.split(' ', 2)
    @type = 'unknown'
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

class Speech
  attr_accessor :speaker, :transcript, :sentences

  def initialize
    @transcript = ''
  end

  def initialize(speaker, transcript)
    @speaker = speaker
    @transcript = transcript
  end

  def num_of_words(sents=nil)
    # call function sentences to initialize @sentences if not already
    load_sentences

    sents = @sentences if sents.nil?
    count = 0
    sents.each do |s|
      count += s.split(' ').reduce(0) { |sum, w| (w =~ /^\W+$/) ? sum : sum + 1 }
    end
    count
  end

  def questions
    # call function sentences to initialize @sentences if not already
    load_sentences

    @sentences.select do |sentence|
      s = sentence.downcase
      s =~ /\?/ or
      s =~ /^(what|where|when|which|who|whom|would|do|does|doesn't|is|isn't|can|could|to what exten|should|was|has|how|which|if)\W+/
    end
  end

  def num_of_questions
    questions.size
  end

  def num_of_words_in_questions
    num_of_words(questions)
  end

  private

  def load_sentences
    if @sentences.nil?
      text = StanfordCoreNLP::Annotation.new(@transcript)
      $pipeline.annotate(text)

      @sentences = []
      text.get(:sentences).each do |s|
        @sentences << s.to_s
      end
    end
    @sentences
  end

end

class Transcript
  attr_accessor :ticker, :reason, :date, :speeches

  def initialize(ticker, reason, date, speeches)
    @ticker = ticker
    @reason = reason
    @date = date
    @speeches = speeches
  end

  def save_to(csv)
    @speeches.each do |speech|
      speaker = speech.speaker

      csv << [
        @ticker,
        @date,
        'n/a',
        @reason,
        speaker.type,
        speaker.first_name,
        speaker.last_name,
        speaker.to_s,
        speaker.affil,
        speaker.title,
        speech.num_of_words,
        speech.num_of_questions,
        speech.num_of_words_in_questions,
        speech.sentences.join(' ')
      ]
    end
  end
end

class Parser < Base

  def clean_up(ticker, transcript)
    transcript.reject! {|line| line =~ /^[A-Z]+$/}

    reason = transcript[0]
    date = transcript[2]

    speeches = []
    current_speech = nil

    while transcript.size > 0
      line = transcript.shift
      # puts line
      speech_found = /^([A-Z ,\.]*):(.*)/.match(line)

      if speech_found.nil?
        # not a speech line
        # if current speech exist, add the line to the current speech
        current_speech.transcript += ' ' + line unless current_speech.nil?
      else
        # is a speech line
        # close the current speech if any, create a new one
        speeches << current_speech.clone unless current_speech.nil?
        current_speech = Speech.new(
          Speaker.new(speech_found[1].strip),
          speech_found[2].strip
        )
      end

    end

    Transcript.new(ticker, reason, date, speeches)
  end

  def run(file)
    ticker = File.basename(file).gsub('.txt','')

    transcripts = []
    transcript = nil

    # the first line of the file is always /^#+$/, so
    # the start of file.open loop will always create a empty transcript array
    File.open(file, 'r').each do |line|
      if line =~ /^##+$/
        # found a /^#+$/ line but the transcript is not empty
        # which means we found a new transcript
        # so we push the existing transcript to the transcripts array
        # and create a new transcript array to hold the content of the next
        # transcript
        unless transcript.nil?
          transcripts << clean_up(ticker, transcript)
        end
        transcript = []
      else
        line = line.strip
        transcript << line unless line.empty?
      end
    end
    transcripts
  end
end

### functions

def usage
  puts 'Usage: ' + File.basename(__FILE__) + ' <directory>'
  exit 1
end

### main

usage unless ARGV.length == 1 #and File.directory?(ARGV[0])

StanfordCoreNLP.jar_path = '/opt/stanford-corenlp-full/'
StanfordCoreNLP.model_path = '/opt/stanford-corenlp-full/'
StanfordCoreNLP.set_model('pos.model', 'english-left3words-distsim.tagger')
StanfordCoreNLP.use :english
StanfordCoreNLP.default_jars = [
  'joda-time.jar',
  'xom.jar',
  'stanford-corenlp-3.7.0.jar',
  'stanford-corenlp-3.7.0-models.jar',
  'jollyday.jar',
  'bridge.jar'
]
$pipeline =  StanfordCoreNLP.load(:tokenize, :ssplit)

parser = Parser.new
parser.csv = [['ticker','date','time','reason','ca',
  'first_nm','surname','affln','firm','jobt',
  'no_words','no_questions','no_words_having_questions','sentences']]

input = ARGV[0]

output_dir = File.dirname(input)
output_file = File.basename(input).gsub(/\W+/,'_') + '_factiva.csv'
output = File.join(output_dir, output_file)

Find.find(input) do |path|
  if File.directory?(path)
    next
  else
    if File.extname(path) == '.txt' and not File.basename(path) =~ /^\./
      parser.info "Parsing [" + path + "]"

      # run it!
      parser.run(path).each do |transcript|
        unless transcript.speeches.empty?
          transcript.save_to(parser.csv)
        end
      end
    end
  end
end

## write to csv
parser.csv_out(output)
