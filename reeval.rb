#!/usr/bin/env ruby

require 'shortbus'
require 'fixedqueue'

# XChat plugin to interpret replacement regexen
class REEval < ShortBus
	# Constructor
	def initialize()
		super
		@lastmessage=''
		@lines = {}
		# @RERE = /^([^ :]+: *)?s(.)([^\2]*)\2([^\2]*)(\2([ginx]+|[0-9]{2}\%|))?/
		@RERE = /^([^ :]+: *)?(-?\d*)?s([^\w])([^\3]*)\3([^\3]*)(\3([ginx]+|[0-9]{2}\%|))$/
		@TRRE = /^([^ :]+: *)?(-?\d*)?tr([^\w])([^\3]*)\3([^\3]*)(\3([0-9]{2}\%)?)$/
		@PARTIAL = /^([^ :]+: *)?(-?\d*)?(s|tr)([^\w])/
		@ACTION = /^\001ACTION.*\001/
		@REOPTIONS = {	'i' => Regexp::IGNORECASE,
				'n' => Regexp::MULTILINE,
				'x' => Regexp::EXTENDED
				}
		@NOMINAL_SIZE = 5
		@exclude = []
		@hooks = []
		hook_command( 'REEVAL', XCHAT_PRI_NORM, method( :enable), '')
		hook_command( 'REEXCLUDE', XCHAT_PRI_NORM, method( :exclude), '')
		hook_server( 'Disconnected', XCHAT_PRI_NORM, method( :disable))
		hook_server( 'Notice', XCHAT_PRI_NORM, method( :notice_handler))
		puts('REEval loaded. Run /REEVAL to enable.')
	end # initialize

	# Enables the plugin
	def enable(words, words_eol, data)
		begin
			if([] == @hooks)
				@hooks << hook_server('PRIVMSG', XCHAT_PRI_NORM, method(:process_message))
				@hooks << hook_print('Your Message', XCHAT_PRI_NORM, method(:your_message))
				puts('REEval enabled.')
			else
				disable()
			end
		rescue
			# puts("#{caller.first}: #{$!}")
		end

		return XCHAT_EAT_ALL
	end # enable

	# Disables the plugin
	def disable(words=nil, words_eol=nil, data=nil)
		begin
			if([] == @hooks)
				puts('REEval already disabled.')
			else
				@hooks.each{ |hook| unhook(hook) }
				@hooks = []
				puts('REEval disabled.')
			end
		rescue
			# puts("#{caller.first}: #{$!}")
		end

		return XCHAT_EAT_ALL
	end # disable

	# Check for disconnect notice
	def notice_handler(words, words_eol, data)
		begin
			if(words_eol[0].match(/Lost connection to server/))
				disable()
			end
		rescue
			# puts("#{caller.first}: #{$!}")
		end

		return XCHAT_EAT_NONE
	end # notice_handler

	def exclude(words, words_eol, data)
		begin
			1.upto(words.size-1){ |i|
				if(0 == @exclude.select{ |item| item == words[i] }.size)
					@exclude << words[i]
					puts("Excluding #{words[i]}")
				else
					@exclude -= [words[i]]
					puts("Unexcluding #{words[i]}")
				end
			}
		rescue
			# puts("#{caller.first}: #{$!}")
		end

		return XCHAT_EAT_ALL
	end # exclude

	# Processes outgoing messages 
	# (Really formats the data and hands it to process_message())
	# * param words [Mynick, mymessage]
	# * param data Unused
	# * returns XCHAT_EAT_NONE
	def your_message(words, data)
		rv = XCHAT_EAT_NONE

		begin
			# Don't catch the outgoing 'Joe meant: blah'
			if(/^([^ ]+ thinks )?[^ ]+ meant:/.match(words[1]) || (0 < @exclude.select{ |item| item == get_info('channel') }.size)) then return XCHAT_EAT_NONE; end

			words_eol = []
			# Build an array of the format process_message expects
			newwords = [words[0], 'PRIVMSG', get_info('channel')] + (words - [words[0]]) 

			#puts("Outgoing message: #{words.join(' ')}")

			# Populate words_eol
			1.upto(newwords.size){ |i|
				words_eol << (i..newwords.size).inject(''){ |str, j|
					"#{str}#{newwords[j-1]} "
				}.strip()
			}

			rv = process_message(newwords, words_eol, data)
		rescue
			# puts("#{caller.first}: #{$!}")
		end

		return rv
	end # your_message

	# Processes an incoming server message
	# * words[0] -> ':' + user that sent the text
	# * words[1] -> PRIVMSG
	# * words[2] -> channel
	# * words[3..(words.size-1)] -> ':' + text
	# * words_eol is the joining of each array of words[i..words.size] 
	# * (e.g. ["all the words", "the words", "words"]
	def process_message(words, words_eol, data)
		begin
			sometext = ''
			outtext = ''
			mynick = words[0].sub(/^:([^!]*)!.*/,'\1')
			nick = nil
			storekey = nil

			# Strip intermittent trailing @ word
			if(words.last == '@')
				words.pop()
				words_eol.collect!{ |w| w.gsub(/\s+@$/,'') }
			end

			if(0 < @exclude.select{ |item| item == get_info('channel') }.size)
				return XCHAT_EAT_NONE
			end
			#puts("Processing message: #{words_eol.join('|')}")
			
			if(3<words_eol.size)
				sometext = words_eol[3].sub(/^:/,'')

				[@RERE, @TRRE, @PARTIAL].each{ |expr|
					if(matches = expr.match(sometext))
						if(matches[1])
							nick = mynick
							mynick = matches[1].sub(/: *$/, '')
						end
						if(matches[2])
						end
						break
					end
				}# Check for "nick: expression"

				# Append channel name for (some) uniqueness
				key = "#{mynick}|#{words[2]}"
				storekey = (nick) ? "#{nick}|#{words[2]}" : key
				#puts("#{nick} #{mynick} #{key}")

				if(@lines[key])
					outtext = sometext.split('|').inject(@lines[key]){ |input, expr|
						#puts("Applying #{expr} to #{input}")
						substitute(input.strip(), expr.strip())
					}# pipeline expressions
					if(!outtext || outtext.strip() == @lines[key].strip()) then outtext = sometext; end
				else
					outtext = sometext
				end

				# Add latest line to db
				#puts("Adding '#{sometext}' for #{key} (was: '#{@lines[storekey]}')")
				if(!@RERE.match(outtext) && !@TRRE.match(outtext) && !@ACTION.match(outtext) && !@PARTIAL.match(outtext)) then @lines[storekey] = outtext; end

				if(outtext != sometext)
					if(nick)
						command("SAY #{nick} thinks #{mynick} meant: #{outtext}")
					else
						command("SAY #{mynick} meant: #{outtext}")
					end

					return XCHAT_EAT_NONE
				end
			end
		rescue
			# puts("#{caller.first}: #{$!}")
		end

		return XCHAT_EAT_NONE
	end # process_message

	# Performs a substitution and returns the result 
	# (or nil on no match)
	# * origtext is the text to be manipulated
	# * restring is a string representing the entire replacement string 
	# * (e.g. 's/blah(foo)bar/baz\1zip/')
	def substitute(origtext, restring, recurse=true)
		begin
			if(rematches = @RERE.match(restring))
			# If the string is a valid replacement...
				# Build options var from trailing characters
				options = @REOPTIONS.inject(0){ |val, pair|
					(rematches[7] && rematches[7].include?(pair[0])) ? val | pair[1] : val
				}

				subex = Regexp.compile(rematches[4], options)
				if(foo = subex.match(origtext))
				# Only process replacements that actually match something
					#puts(foo.inspect())
					# if(rematches[5]) then puts("Suffix #{rematches[5]}"); end

					if(0 < (percent = get_percent(rematches[7])))
					# if(rematches[5] && rematches[5].strip()[2,1] == '%')
						#Stochastic crap
						# puts("Using #{percent}%")

						return origtext.gsub(subex){ |match|
							blah = rand(101)
							# puts("Randomly drew #{blah}: #{(blah < percent) ? '' : 'not '}replacing")
							((blah < percent) ? match.sub(subex, rematches[5]) : match)
						}
					else
						return ((rematches[7] && rematches[7].include?('g')) ? 
							origtext.gsub(subex, rematches[5]) : 
							origtext.sub(subex, rematches[5]))
					end
				end
			elsif(trmatches = @TRRE.match(restring))
			# If the string is a valid transposition
				if(0 > (percent = get_percent(trmatches[7]))) then percent = 1000; end
				return tr_rand(origtext, trmatches[4], trmatches[5], percent)
			elsif((partial = @PARTIAL.match(restring)) && recurse)
				# puts("Recursing to #{restring + partial[3].to_s()}")
				return substitute(origtext, restring + partial[4].to_s(), false)
			# else
			# 	puts("No match for #{restring}")
			end
		rescue
			# puts("#{caller.first}: #{$!}")
		end

		return origtext
	end # substitute

	# Gets the percentage value from a string
	# * str is a string of the form: '42%(optionalgarbagehere)'
	def get_percent(str)
		begin
			if(str && str.strip()[2,1] == '%')
				return str.strip()[0,2].to_i()
			end
		rescue
			# puts("#{caller.first}: #{$!}")
		end

		return -1
	end

	# Randomly transposes patterns in a string
	# If this is brokeback, blame beanfootage
	# * str is the source string
	# * from is the input pattern of the transposition
	# * to is the output pattern of the transposition
	# * prob is the probability as an integer percentage
	def tr_rand(str, from, to, prob)
		return str.split(//).inject(''){ |accum,x| accum + ((rand(101) < prob) ? x.tr(from, to) : x) }
	end
end # REEval

if(__FILE__ == $0)
	blah = REEval.new()
	blah.run()
end
