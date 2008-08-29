#!/usr/bin/env ruby

include XChatRuby

# XChat plugin to interpret replacement regexen
class REEval < XChatRubyPlugin
	include XChatRuby
	
	# Constructor
	def initialize()
		@lastmessage=''
		@lines = {}
		@RERE = /^([^ :]+: *)?s\/([^\/]*)\/([^\/]*)(\/([ginx]+|[0-9]{2}\%))?/
		@TRRE = /^([^ :]+: *)?tr\/([^\/]*)\/([^\/]*)(\/([0-9]{2}\%))?/
		@ACTION = /^\001ACTION.*\001/
		@REOPTIONS = {	'i' => Regexp::IGNORECASE,
				'n' => Regexp::MULTILINE,
				'x' => Regexp::EXTENDED
				}
		@exclude = []
		@hooks = []
		hook_command( 'REEVAL', XCHAT_PRI_NORM, method( :enable), '')
		hook_command( 'REEXCLUDE', XCHAT_PRI_NORM, method( :exclude), '')
		hook_server( 'Disconnected', XCHAT_PRI_NORM, method( :disable), '')
		hook_server( 'Notice', XCHAT_PRI_NORM, method( :notice_handler), '')
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
			puts("#{caller.first}: #{$!}")
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
			puts("#{caller.first}: #{$!}")
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
			puts("#{caller.first}: #{$!}")
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
			puts("#{caller.first}: #{$!}")
		end

		return XCHAT_EAT_ALL
	end # exclude

	# Processes outgoing messages 
	# (Really formats the data and hands it to process_message())
	# * param words [Mynick, mymessage]
	# * param data Unused
	# * returns XCHAT_EAT_NONE
	def your_message(words, data)
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

			process_message(newwords, words_eol, data)
		rescue
			puts("#{caller.first}: #{$!}")
		end

		return XCHAT_EAT_NONE
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

				if((matches = @RERE.match(sometext)) && (matches[1]))
					# Check for "nick: s/foo/bar/"
					nick = mynick
					mynick = matches[1].sub(/: *$/, '')
				elsif((matches = @TRRE.match(sometext)) && (matches[1]))
					# Check for "nick: tr/bl/ah/"
					nick = mynick
					mynick = matches[1].sub(/: *$/, '')
				end

				# Append channel name for (some) uniqueness
				key = "#{mynick}|#{words[2]}"
				storekey = (nick) ? "#{nick}|#{words[2]}" : key
				#puts("#{nick} #{mynick} #{key}")

				if(@lines[key])
					outtext = sometext.split('|').inject(@lines[key]){ |input, expr|
						#puts("Applying #{expr} to #{input}")
						substitute(input.strip(), expr.strip())
					}# pipeline expressions
					if(!outtext) then outtext = sometext; end
				else
					outtext = sometext
				end

				# Add latest line to db
				#puts("Adding '#{sometext}' for #{key} (was: '#{@lines[storekey]}')")
				if(!@RERE.match(outtext) && !@TRRE.match(outtext) && !@ACTION.match(outtext)) then @lines[storekey] = outtext; end

				if(outtext != sometext)
					if(nick)
						command("SAY #{nick} thinks #{mynick} meant: #{outtext}")
					else
						command("SAY #{mynick} meant: #{outtext}")
					end

					return XCHAT_EAT_ALL
				end
			end
		rescue
			puts("#{caller.first}: #{$!}")
		end

		return XCHAT_EAT_NONE
	end # process_message

	# Performs a substitution and returns the result 
	# (or nil on no match)
	# * origtext is the text to be manipulated
	# * restring is a string representing the entire replacement string 
	# * (e.g. 's/blah(foo)bar/baz\1zip/')
	def substitute(origtext, restring)
		begin
			if(rematches = @RERE.match(restring))
			# If the string is a valid replacement...
				# Build options var from trailing characters
				options = @REOPTIONS.inject(0){ |val, pair|
					(rematches[5] && rematches[5].include?(pair[0])) ? val | pair[1] : val
				}

				subex = Regexp.compile(rematches[2], options)
				if(foo = subex.match(origtext))
				# Only process replacements that actually match something
					#puts(foo.inspect())
					# if(rematches[5]) then puts("Suffix #{rematches[5]}"); end

					if(0 < (percent = get_percent(rematches[5])))
					# if(rematches[5] && rematches[5].strip()[2,1] == '%')
						#Stochastic crap
						# puts("Using #{percent}%")

						return origtext.gsub(subex){ |match|
							blah = rand(101)
							# puts("Randomly drew #{blah}: #{(blah < percent) ? '' : 'not '}replacing")
							((blah < percent) ? match.sub(subex, rematches[3]) : match)
						}
					else
						return ((rematches[5] && rematches[5].include?('g')) ? 
							origtext.gsub(subex, rematches[3]) : 
							origtext.sub(subex, rematches[3]))
					end
				end
			elsif(trmatches = @TRRE.match(restring))
			# If the string is a valid transposition
				return origtext.tr(trmatches[2], trmatches[3])
			end
		rescue
			puts("#{caller.first}: #{$!}")
		end

		return nil
	end # substitute

	# Gets the percentage value from a string
	# * str is a string of the form: '42%(optionalgarbagehere)'
	def get_percent(str)
		begin
			if(str && str.strip()[2,1] == '%')
				return str.strip()[0,2].to_i()
			end
		rescue
			puts("#{caller.first}: #{$!}")
		end

		return -1
	end
end # REEval
