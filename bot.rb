require 'cinch'

class TriviaTicker
	include Cinch::Plugin

	def initialize(*args)
		super
	end

	timer 1, method: :tick
	def tick
		@bot.handlers.dispatch(:tick)
	end
end

class TriviaBot < Cinch::Bot

	def trivia_init
		load_questions
		@question_time_limit = 60
		@question_warn_times = [30,15]

		@scores = []
	end

	def get_score_entry(nick)
		entries = @scores.select {|entry| entry[:nick].downcase == nick.downcase}
		return nil if entries.empty?
		return entries.first
	end

	def add_score(nick,score)
		entry = get_score_entry(nick)

		unless entry	
			entry = {:nick => nick, :score => 0}
			@scores << entry
		end

		entry[:score] += score
	end

	def load_questions
		@questions = []

		db = File.open('questions.txt','r');
		db.read.lines.each do |line|
			@questions << Hash[ [:question, :answer].zip( line.strip.split("\t") ) ]
		end
		db.close

		shuffle
	end
	
	def shuffle
		@question_idx = 0
		@questions.shuffle!
	end

	def start_game m
		return if @active

		@channel = m.channel
		start_question
		@timeout_count = 0
		@active = true
	end

	def stats(m)
		scores = @scores.sort_by {|score| [score[:score]]}
		rank = 1
		scores.each do |entry|
			m.reply("%d. %s %d" % [rank,entry[:nick],entry[:score]])
			rank+=1
		end
	end

	def start_question
		next_question
		@question_time = @question_time_limit
		Channel(@channel).send @question[:question]
	end

	def check_answer(m,t)
		return unless @active
		
		if t == @question[:answer]
			@timeout_count = 0
			m.reply("Correct! %s wins!" % m.user.nick)
			add_score m.user.nick, 1
			start_question
		end
	end

	def next_question
		shuffle if @question_idx >= @questions.length

		@question = @questions[@question_idx]
		@question_idx += 1
	end

	def check_question_time
		@question_time -= 1

		if @question_time <= 0
			question_timeout
		elsif @question_warn_times.include? @question_time
			Channel(@channel).send "%d seconds remain..." % @question_time
		end
	end

	def question_timeout
		Channel(@channel).send "Timeout! The answer was %s" % @question[:answer]
		@timeout_count += 1
		
		if @timeout_count >= 3
			Channel(@channel).send("Ending game after 3 consecutive timeouts!")
			@active = false
		else
			start_question
		end
	end

	def tick
		return unless @active
		check_question_time
	end
end

bot = TriviaBot.new do
	trivia_init

	configure do |c|
		c.nick = "derp"
		c.server = "irc.consental.com"
		c.verbose = true
		c.channels = ["#derp"]
		c.plugins.plugins = [TriviaTicker]
	end

	on :join do |m|
		#derp derp derp
	end

	on :channel, /^!start$/ do |m|
		bot.start_game m
	end

	on :channel, /^!stats$/ do |m|
		bot.stats m
	end

	on :channel, /^([^!].*)$/ do |m,t|
		bot.check_answer m,t
	end

	on :tick do
		bot.tick
	end

end

bot.start
