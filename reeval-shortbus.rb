#!/usr/bin/env ruby

# This program is free software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License as published by the Free Software Foundation; either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.

require 'shortbus'
require 'reeval'

NICKRE = /^:([^!]*)!.*/

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
		hook_command( 'REDUMP', XCHAT_PRI_NORM, method( :dump), '')
		hook_server( 'Disconnected', XCHAT_PRI_NORM, method( :disable))
		hook_server( 'Notice', XCHAT_PRI_NORM, method( :notice_handler))
		hook_server( 'Quit', XCHAT_PRI_NORM, method( :quit_handler))
		hook_server( 'Part', XCHAT_PRI_NORM, method( :process_message))
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
	
	# Dumps the last 10 messages for words[1] (nick|channel)
	# and messages them to words[2]
	def dump(words, words_eol, data)
		begin
			words.shift()
			if(words && 2 == words.size)
				@reeval.dump(words[0]).each{ |line|
					if(line) then command("MSG #{words[1]} #{line}"); end
				}
			end
		rescue
		end
	end # dump

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
	
	# Process quit messages
	def quit_handler(words, words_eol, data)
		begin
			if (3 < words.size)
				words[2] = get_info('channel')
				process_message(words, words_eol, data)
			end
		rescue
		end
	end # quit_handler

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
			if(/^([^ ]+\s?thinks )?[^ ]+ meant:/.match(words[1]) || (0 < @exclude.select{ |item| item == get_info('channel') }.size)) then return XCHAT_EAT_NONE; end

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
			mynick = words[0].sub(NICKRE,'\1')
			nick = nil
			storekey = nil
			index = 0
			line = nil
			channel = words[2]

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
				if(!words[2].match(/^#/) && (matches = words[3].match(/^:(#[-\w\d]+)$/)))
				# Allow /msg Tak #sslug ledge: -1s/.*/I suck!
					sometext = words_eol[4]
					channel = matches[1]
				else
					sometext = words_eol[3].sub(/^:/,'')
				end
				storekey = "#{mynick}|#{channel}"	# Append channel name for (some) uniqueness

				response = @reeval.process_full(storekey, mynick, sometext){ |from, to, msg|
					output_replacement(from, to, channel, msg)
				}

				if(response)
					command("MSG #{mynick} #{response}")
				end
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
	def output_replacement(nick, tonick, channel, sometext)
		mynick = get_info('nick')
		if(tonick)
			nick = (nick == mynick) ? 'Me' : "#{nick} "
			tonick = (tonick == mynick) ? 'I' : tonick
			command("MSG #{channel} #{nick}thinks #{tonick} meant: #{sometext}")
		else
			nick = (nick == mynick) ? 'I' : nick
			command("MSG #{channel} #{nick} meant: #{sometext}")
		end
	end # output_replacement

end # REEvalShortBus

if(__FILE__ == $0)
	blah = REEvalShortBus.new()
	blah.run()
end
