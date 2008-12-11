#!/usr/bin/env ruby

require 'shortbus'
require 'reeval'

# XChat plugin to interpret replacement regexen
class REEvalShortBus < ShortBus
	# Constructor
	def initialize()
		super
		@reeval = REEval.new()
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
			if(words_eol[0].match(/(^Disconnected|Lost connection to server)/))
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
			index = 0
			line = nil

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
				storekey = "#{mynick}|#{words[2]}"	# Append channel name for (some) uniqueness

				@reeval.process_full(storekey, mynick, sometext){ |from, to, msg|
					output_replacement(from, to, msg)
				}
			end
		rescue
			puts("#{caller.first}: #{$!}")
		end

		return XCHAT_EAT_NONE
	end # process_message

	# Sends a replacement message
	# * nick is the nick of the user who issued the replacement command
	# * tonick is the nick of the user whose text nick is replacing, 
	# or nil for his own
	# * sometext is the replacement text
	def output_replacement(nick, tonick, sometext)
		if(tonick)
			command("SAY #{nick} thinks #{tonick} meant: #{sometext}")
		else
			command("SAY #{nick} meant: #{sometext}")
		end
	end # output_replacement

end # REEvalShortBus

if(__FILE__ == $0)
	blah = REEvalShortBus.new()
	blah.run()
end
