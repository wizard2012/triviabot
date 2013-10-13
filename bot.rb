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
		@question_time_limit = 60
		@question_warn_times = [45,30,15]

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
	
	def repeat(m)
		send_question
	end	

	def start_question
		next_question
		@hint_count = 0
		@hint_str = nil
		@question_time = @question_time_limit
		send_question
	end

	def send_question
		Channel(@channel).send Format(:green, ">>> %s" % [@question[:question]])
	end


	def check_answer(m,t)
		return unless @active
		
		if @question[:answer].each{|a| a.strip!;a.downcase!}.include? t.strip.downcase
			@timeout_count = 0
			m.reply("%s %s wins!" % [Format(:blue,"Correct!"),m.user.nick])
			add_score m.user.nick, 1
			start_question
		end
	end

	def next_question
		File.open(Dir.glob('questions/*.txt').shuffle.first,'r') do |file| 
			questions = file.read

			questions.lines.with_index(rand questions.size) do |q,idx|
				pcs = q.strip.split("\t")
				@question = Hash[ [:question, :answer].zip( [pcs.first, pcs.drop(1)] ) ]
				break
			end
		end
	end

	def do_hint
		return unless @active

		answer = @question[:answer].first

		if @hint_count == 0 or not @hint_str or answer.length < 5
			@hint_str = answer.gsub(/[^ ]/, '*')
		else 
			idx = []

			(0..@hint_str.length).each do |i|
				idx << i if '*' == @hint_str[i]
			end
			
			#unmask 30%...
			idx.sample(idx.length/3).each{|i| @hint_str[i] = answer[i]}
		end
		@hint_count += 1
		Channel(@channel).send "%s: %s" % [Format(:yellow, "Hint"), @hint_str]

	end

	def check_question_time
		@question_time -= 1
	
		if @question_time <= 0
			question_timeout
		elsif @question_warn_times.include? @question_time
			Channel(@channel).send "%s %d seconds remain..." % [Format(:yellow, '***'),@question_time]
			do_hint
		end
	end

	def game_timeout 
		if @timeout_count >= 3
			Channel(@channel).send("Ending game after 3 consecutive timeouts!")
			@active = false
			return true
		else
			return false
		end
	end

	def question_timeout

		Channel(@channel).send "%s The answer is: %s" % [Format(:red,'Timeout!'), Format(:green,@question[:answer].first)]
		@timeout_count += 1
		
		start_question unless game_timeout
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
