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

class TriviaTaunter
	def initialize(bot)
		@bot = bot
		@idle = 0
	end

	def start_game
		reset_idle
	end

	def reset_idle
		@idle = 0
	end

	def tick
		return if @bot.active
		@idle += 1

		taunt if @idle >= 900
	end
	
	def taunt
		reset_idle
		first = @bot.get_leaderboard.first

		if first
			@bot.chanmsg "%s is in first with %d points. You should !start a game and put him in his place!" % [first[:nick],first[:score]]
		else
			@bot.chanmsg "The leaderboard is empty. You should !start a game and grab first place!"
		end
	end
end

class TriviaStreak
	include Cinch::Helpers

	def initialize(bot)
		@bot = bot
	end

	def question_answered(nick)
		@streak ||= 0
		@nick ||= nick
		
		if @nick.downcase != nick.downcase
			@nick = nick
			@streak = 0
		end

		@streak += 1

		if @streak == 2
			@bot.chanact "hands %s beer!" % [nick]
		elsif @streak == 3
			@bot.chanmsg "%s is on fire: %d answer streak!" % [nick, @streak]
		elsif @streak == 5
			@bot.chanmsg "%d answers in a row!?!? %s is UNSTOPPABLE!" % [@streak, nick]
		end
	end

	def question_timeout
		@nick = nil
		@streak = nil
	end
end

class TriviaHints
	include Cinch::Helpers
	def initialize(bot) 
		@bot = bot
	end

	def start_question
		@hint_count = 0
		@hint_str = nil
	end

	def unmask_hint
		idx = []

		(0..@hint_str.length).each do |i|
			idx << i if '*' == @hint_str[i]
		end
	
		return if idx.size <= 1

		unmask_count = idx.length/3
		unmask_count = 1 if unmask_count == 0
		idx.sample(unmask_count).each{|i| @hint_str[i] = get_answer[i]}
	end

	def get_answer
		@bot.question[:answer].first
	end

	def timeout_warn
		if @hint_count == 0 or not @hint_str
			@hint_str = get_answer.gsub(/[^ ]/, '*')
		else 
			unmask_hint
		end

		@hint_count += 1
		@bot.chanmsg "%s %d: %s" % [Format(:yellow, "Hint"), ,@hint_count, @hint_str]
	end
end

class TriviaBot < Cinch::Bot
	attr_reader	:question
	attr_reader :active

	def trivia_init
		@channel = '#derp'
		@question_time_limit = 60
		@question_warn_times = [45,30,15]

		@scores = []
		@trivia_plugins = [TriviaHints.new(self), TriviaStreak.new(self), TriviaTaunter.new(self)]
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

	def start_game m
		return if @active
		
		#@channel = m.channel
		start_question
		@timeout_count = 0
		@active = true

		fire_event :start_game
	end

	def get_leaderboard
		@scores.sort_by {|score| [-score[:score]]}
	end

	def stats(m)
		rank = 1
		get_leaderboard.each do |entry|
			m.reply("%d. %s %d" % [rank,entry[:nick],entry[:score]])
			rank+=1
		end
	end
	
	def repeat(m)
		send_question
	end	

	def start_question
		next_question
		@question_time = @question_time_limit
		
		fire_event :start_question

		send_question
	end

	def fire_event(event,*args)
		@trivia_plugins.each do |mod|
			next unless mod.respond_to? event
			begin
				mod.send event, *args
			rescue
				#@todo log this
				puts $!,$@
			end
		end
	end

	def chanmsg(msg)
		Channel(@channel).send msg
	end

	def chanact(msg)
		Channel(@channel).action msg
	end

	def send_question
		chanmsg Format(:green, ">>> %s" % [@question[:question]])
	end

	def normalize_answer(a)
		a.strip.downcase
	end

	def check_answer(m,t)
		return unless @active
		@timeout_count = 0
		@question[:answer].each do |a|
			if normalize_answer(a) == normalize_answer(t)
				@question[:answer].delete a if @kaos
				question_answered(m.user.nick)
				return
			end
		end
	end

	def question_answered(nick)
		add_score nick, 1
		fire_event :question_answered, nick

		if @kaos
			remain = @question[:answer].size
			chanmsg "Good job, %s! %d answers remain." % [nick,remain]
			start_question if remain == 0
		else
			chanmsg "%s %s wins!" % [Format(:blue,"Correct!"), nick]
			start_question
		end
	end

	def next_question
		File.open(Dir.glob('questions/*.txt').shuffle.first,'r') do |file| 
			questions = file.read

			pcs = questions.split("\n").shuffle.first.strip.split("\t")

			@question = Hash[ [:question, :answer].zip( [pcs.first, pcs.drop(1)] ) ]
		end

		if @question[:question].start_with? 'KAOS:'
			@kaos = true
		else
			@kaos = false
		end
	end

	def check_question_time
		return unless @active

		@question_time -= 1
	
		if @question_time <= 0
			question_timeout
		elsif @question_warn_times.include? @question_time
			chanmsg "%s %d seconds remain..." % [Format(:yellow, '***'),@question_time]
			fire_event :timeout_warn
		end
	end

	def game_timeout 
		if @timeout_count >= 3
			chanmsg "Ending game after 3 consecutive timeouts!"
			@active = false
			return true
		else
			return false
		end
	end

	def question_timeout
		chanmsg "%s The answer is: %s" % [Format(:red,'Timeout!'), Format(:green,@question[:answer].first)]
		@timeout_count += 1
		
		fire_event :question_timeout

		start_question unless game_timeout
	end

	def tick
		fire_event :tick

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

	on :channel, /^!repeat$/ do |m|
		bot.repeat m
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
