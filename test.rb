#!/usr/bin/env ruby

require 'pp'
require 'stanford-core-nlp'

exit 1 if ARGV.length < 1

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

pipeline =  StanfordCoreNLP.load(:tokenize, :ssplit)

sentences = []
transcript = File.readlines(ARGV[0])

transcript.collect! do |line|
  line.strip
end

text = StanfordCoreNLP::Annotation.new(transcript.join(' '))
pipeline.annotate(text)

text.get(:sentences).each do |s|
  sentences << s.to_s
end

pp sentences[0..10]
