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

# Regular expression to match an irc nick pattern (:nick[!user@host])
# and capture the nick portion in \1
NICKRE = /^:([^!]*)!.*/

# Match beanfootage's tinyurl output
TINYURL_REGEX = /^(:)?\[AKA\]/

REEVAL_MAX_MESSAGE_LENGTH = 1024

# XChat plugin to interpret replacement regexen
module REEval
  class REEvalShortBus < ShortBus::ShortBus
    # Constructor
    def initialize()
      super

      # Expression to match an action/emote message
      @ACTION = /^\001ACTION(.*)\001/

      @reeval = REEval.new()
      @exclude = []
      @hooks = []
      hook_command( 'REEVAL', ShortBus::XCHAT_PRI_NORM, method( :enable), '')
      hook_command( 'REEXCLUDE', ShortBus::XCHAT_PRI_NORM, method( :exclude), '')
      hook_command( 'REDUMP', ShortBus::XCHAT_PRI_NORM, method( :dump), '')
      hook_server( 'Disconnected', ShortBus::XCHAT_PRI_NORM, method( :disable))
      hook_server( 'Notice', ShortBus::XCHAT_PRI_NORM, method( :notice_handler))
      hook_server( 'Quit', ShortBus::XCHAT_PRI_NORM, method( :quit_handler))
      hook_server( 'Part', ShortBus::XCHAT_PRI_NORM, method( :process_message))
      hook_server( 'Kick', ShortBus::XCHAT_PRI_NORM, method( :kick_handler))
      puts('REEval loaded. Run /REEVAL to enable.')
    end # initialize

    # Enables the plugin
    def enable(words, words_eol, data)
      begin
        if([] == @hooks)
          @hooks << hook_server('PRIVMSG', ShortBus::XCHAT_PRI_NORM, method(:process_message))
          @hooks << hook_print('Your Message', ShortBus::XCHAT_PRI_NORM, method(:your_message))
          @hooks << hook_print('Your Action', ShortBus::XCHAT_PRI_NORM, method(:your_action))
          puts('REEval enabled.')
        else
          disable()
        end
      rescue
        # puts("#{caller.first}: #{$!}")
      end

      return ShortBus::XCHAT_EAT_ALL
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

      return ShortBus::XCHAT_EAT_ALL
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

      return ShortBus::XCHAT_EAT_NONE
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

    # Process kick messages
    def kick_handler(words, words_eol, data)
      begin
        if(3 < words.size)
          words.slice!(3)
          3.upto(words_eol.size-1){ |i|
            words_eol[i].sub!(/^[^\s]+\s+/, '')
          }
        end
        return process_message(words, words_eol, data)
      rescue
      end
    end # kick_handler

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

      return ShortBus::XCHAT_EAT_ALL
    end # exclude

    # Processes outgoing actions
    # (Really formats the data and hands it to process_message())
    # * param words [Mynick, mymessage]
    # * param data Unused
    # * returns ShortBus::XCHAT_EAT_NONE
    def your_action(words, data)
      words[1] = "\001ACTION#{words[1]}\001"
      return your_message(words, data)
    end # your_action

    # Processes outgoing messages
    # (Really formats the data and hands it to process_message())
    # * param words [Mynick, mymessage]
    # * param data Unused
    # * returns ShortBus::XCHAT_EAT_NONE
    def your_message(words, data)
      rv = ShortBus::XCHAT_EAT_NONE

      begin
        # Don't catch the outgoing 'Joe meant: blah'
        if(/^([^ ]+\s?thinks )?[^ ]+ meant:/.match(words[1]) || (0 < @exclude.select{ |item| item == get_info('channel') }.size)) then return ShortBus::XCHAT_EAT_NONE; end

        words_eol = []
        # Build an array of the format process_message expects
        newwords = [words[0], 'PRIVMSG', get_info('channel')] + (words - [words[0]])

        # puts("Outgoing message: #{words.join(' ')}")

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
          return ShortBus::XCHAT_EAT_NONE
        end
        # puts("Processing message: #{words_eol.join('|')}")

        if(3<words_eol.size)
          if(!words[2].match(/^#/) && (matches = words[3].match(/^:(#[-\w\d]+)$/)))
          # Allow /msg Tak #sslug ledge: -1s/.*/I suck!
            sometext = words_eol[4]
            channel = matches[1]
          else
            sometext = words_eol[3].sub(/^:/,'')
            if(sometext.match(TINYURL_REGEX)) then return ShortBus::XCHAT_EAT_NONE; end
          end
          storekey = "#{mynick}|#{channel}"	# Append channel name for (some) uniqueness

          response = @reeval.process_full(storekey, mynick, sometext){ |from, to, msg|
            output_replacement(from, to, channel, msg)
          }

          if(response)
            response = REEvalShortBus.ellipsize(response)
            command("MSG #{mynick} #{response}")
          end
        end
      rescue
        # puts("#{caller.first}: #{$!}")
      end

      return ShortBus::XCHAT_EAT_NONE
    end # process_message

    # Sends a replacement message
    # * nick is the nick of the user who issued the replacement command
    # * tonick is the nick of the user whose text nick is replacing,
    # or nil for his own
    # * sometext is the replacement text
    def output_replacement(nick, tonick, channel, sometext)
      sometext = REEvalShortBus.ellipsize(sometext)
      mynick = get_info('nick')

      if(tonick)
        if(matches = @ACTION.match(sometext)); then sometext = "* #{tonick} #{matches[1]}"; end
        nick = (nick == mynick) ? 'Me' : "#{nick} "
        tonick = (tonick == mynick) ? 'I' : tonick
        command("MSG #{channel} #{nick}thinks #{tonick} meant: #{sometext}")
      else
        if(matches = @ACTION.match(sometext)); then sometext = "* #{nick} #{matches[1]}"; end
        nick = (nick == mynick) ? 'I' : nick
        command("MSG #{channel} #{nick} meant: #{sometext}")
      end
    end # output_replacement

    def REEvalShortBus.ellipsize(str)
      (REEVAL_MAX_MESSAGE_LENGTH < str.size) ?
        "#{str.slice(0, REEVAL_MAX_MESSAGE_LENGTH)}..." :
        str
    end # ellipsize
  end # REEvalShortBus
end # REEval
