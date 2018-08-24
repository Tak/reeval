# encoding: utf-8

# This program is free software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License as published by the Free Software Foundation; either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.

require 'fixedqueue'
require_relative 'cicphash'

# Core regex replacement engine
module REEval
  class REEval
    def initialize()
      @regexes = {}
      @lines = CICPHash.new()

      # Expression to match a message containing a regex
      # [othernick: ][10]s/foo/bar/[ginx]
      # [othernick: ][10]s/foo/bar/[50%]
      # \1 captures othernick:
      # \2 captures message offset
      # \3 captures expression delimiter (e.g. / for s/foo/bar/)
      # \4 captures the match subexpression
      # \5 captures the substitution subexpression
      # \7 captures a trailing flag string or percentage
      @RERE = /^\s*([^ :]+: *)?(-?\d*)?[Ss]([^\w])([^\3]*)\3([^\3]*)(\3([ginx]+|[0-9]{2}\%|))$/

      # Expression to match a message containing a transposition
      # [othernick: ][10]tr/az/za/[50%]
      # \1 captures othernick:
      # \2 captures message offset
      # \3 captures expression delimiter (e.g. / for tr/az/za/)
      # \4 captures the match subexpression
      # \5 captures the transposition subexpression
      # \7 captures a trailing percentage
      @TRRE = /^\s*([^ :]+: *)?(-?\d*)?[Tt][Rr]([^\w])([^\3]*)\3([^\3]*)(\3([0-9]{2}\%)?)$/

      # Expression to match a string containing a partial regex or transposition message
      # [othernick: ][10]s/
      # [othernick: ][10]tr/
      # \1 captures othernick:
      # \2 captures message offset
      # \3 captures substitution type
      # \4 captures expression delimiter
      @PARTIAL = /^\s*([^ :]+: *)?(-?\d*)?(S|s|tr|Tr|tR|TR)([^\w])/

      # Expression to match an action/emote message
      @ACTION = /^\001ACTION(.*)\001/

      # Expression to match a character range
      # \1 captures the beginning of the range
      # \2 captures the end of the range
      @RANGE = /(.)-(.)/

      # Map flag characters to Regexp options
      @REOPTIONS = {	'i' => Regexp::IGNORECASE,
                     'n' => Regexp::MULTILINE,
                     'x' => Regexp::EXTENDED
          }
      @NOMINAL_SIZE = 100
    end # initialize

    # Performs a complete message process run
    # * storekey is the storage key of the user who issued the message
    # (nick|channel)
    # * mynick is the nick of the user who issued the message
    # * sometext is the complete message
    def process_full(storekey, mynick, sometext)
      if(@ACTION.match(sometext))
        push_text(storekey, sometext)
        return nil
      end

      tonick = get_tonick(sometext)
      index = get_index(sometext)

      if(index && (@NOMINAL_SIZE < index.abs()))
      # Bad index
        # puts("Ignoring #{sometext}: index #{index}")
        return
      end

      # Append channel name for (some) uniqueness
      key = tonick ? storekey.sub(/.*\|/, "#{tonick}|") : storekey

      if(!index)
      # Plain text message - push into the queue
        # puts("Storing '#{sometext}' for #{storekey}")
        push_text(storekey, sometext)
      end

      outtext = process_statement(storekey, key, mynick, tonick, index, sometext){ |from, to, msg|
        yield(from, to, msg)
      }

      if(outtext)
        # Replacement has occurred
        if(outtext != sometext)
          yield(mynick, tonick, outtext)
        end

        if(!@RERE.match(outtext) && !@TRRE.match(outtext) && !@PARTIAL.match(outtext))
        # Push replaced text into queue and reprocess for pending replacements
          # puts("Recursing on '#{outtext}' for #{storekey}")
          process_full(storekey, mynick, outtext){ |from, to, msg|
            yield(from, to, msg)
          }
          # push_text(storekey, outtext)
        end
      elsif(index && 0 > index)
        return 'Regex stored.'
      end

      return nil
    end # process_full

    # Processes a statement and returns its replacement, or nil
    # * storekey is the storage key for the message sender
    # * key is the storage key for the user to whom the message is directed
    # * mynick is the nick of the message sender
    # * tonick is the nick of the user to whome the message is directed,
    # or nil
    # * index is the index prepended to the message, or nil
    # * sometext is the message text
    def process_statement(storekey, key, mynick, tonick, index, sometext)
      if(index)
      # Regex
        if(0 <= index)
        # Lookup old text and replace
          oldtext = get_text(key, index)
          # puts("Got #{oldtext} for #{key}")
          if(oldtext)
            if(matches = @ACTION.match(oldtext))
              outtext = perform_substitution(matches[1], sometext)
              return "\001ACTION#{outtext}\001"
            else
              return perform_substitution(oldtext, sometext)
            end
          end
        elsif(0 > index)
        # Store regex for future
          set_regex(key, storekey, index.abs()-1, mynick, tonick, sometext.sub(@PARTIAL, '\1\3\4'))
        end
      else
      # Text
        # Check for preseeded regexes
        seeds = pop_regexes(key)
        if(seeds)
          seeds.each{ |seed|
            # Process recursively
            process_full(seed[0], seed[1], seed[3]){ |from, to, msg|
              yield(from, to, msg)
            }
          }
        end
      end
      return nil
    end # process_statement

    # Performs a substitution and returns the result, or nil
    # * plaintext is the input text for the replacement
    # * regextext is a string representing
    # a |-delimited regex chain
    def perform_substitution(plaintext, regextext)
      outtext = regextext.split('>').inject(plaintext){ |input, expr|
        #puts("Applying #{expr} to #{input}")
        substitute(input.strip(), expr.strip())
      }# pipeline expressions
      if(!outtext || outtext.strip() == plaintext.strip())
        return nil
      end
      return outtext
    end # perform_substitution

    # Matches any of the REEval matching expressions
    # and yields any non-nil match collections
    # * sometext is the text to be matched
    def any_match(sometext)
      [@RERE, @TRRE, @PARTIAL].each{ |expr|
        if(matches = expr.match(sometext))
          yield matches
        end
      }
    end # any_match

    # Searches a message for a directed nick, as in:
    # Tak: s/.*/yaddle
    # * sometext is the message to search
    def get_tonick(sometext)
      any_match(sometext){ |matches|
        if(matches[1])
          return matches[1].sub(/: *$/, '')
        end
      }
      return nil
    end # get_tonick

    # Searches a message for a specified index, as in:
    # 2s/foo/bar
    # * sometext is the message to search
    def get_index(sometext)
      any_match(sometext){ |matches|
        if(matches[2])
          return matches[2].to_i()
        end
      }
      return nil
    end # get_index

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
          if(origmatches = subex.match(origtext))
          # Only process replacements that actually match something
            #puts(origmatches.inspect())

            # Replace fill expressions:
            # a{\l1} in a substitution pattern will insert a sequence of a
            # whose length is the same as the matched \1
            # (ab){\l2} will insert a sequence of ab that repeats once
            # for each character in the matched \1
            replacement = rematches[5]
            (1..(origmatches.size-1)).each{ |i|
              numreplace = origmatches[i].size
              # Replace single-char and parenthesized expressions separately for simplicity
              replacement.gsub!(Regexp.compile("(([^)]))\\{\\\\l#{i}\\}"), '\2' * numreplace)
              replacement.gsub!(Regexp.compile("(\\(([^)]+)\\))\\{\\\\l#{i}\\}"), '\2' * numreplace)
            }

            if(0 < (percent = get_percent(rematches[7])))
            #Stochastic crap
              # puts("Using #{percent}%")

              return origtext.gsub(subex){ |match|
                blah = rand(101)
                # puts("Randomly drew #{blah}: #{(blah < percent) ? '' : 'not '}replacing")
                ((blah < percent) ? match.sub(subex, replacement) : match)
              }
            else
              return ((rematches[7] && rematches[7].include?('g')) ?
                origtext.gsub(subex, replacement) :
                origtext.sub(subex, replacement))
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
    end # get_percent

    # Randomly transposes patterns in a string
    # If this is brokeback, blame beanfootage
    # * str is the source string
    # * from is the input pattern of the transposition
    # * to is the output pattern of the transposition
    # * prob is the probability as an integer percentage
    # * returns the transposed string
    def tr_rand(str, from, to, prob)
      return str.split(//).inject(''){ |accum,x| accum + ((rand(101) < prob) ? x.tr(from, to) : x) }
    end # tr_rand

    def expand_range(tr_pattern)
      return tr_pattern.gsub(@RANGE) {|m| ($2 > $1) ? Range.new($1, $2).to_a() : Range.new($2, $1).to_a().reverse()}
    end # expand_range

    # Returns a new FixedQueue of the appropriate size
    def create_fixedqueue()
      return FixedQueue::FixedQueue.new(@NOMINAL_SIZE + 1)
    end # create_fixedqueue

    # Stores a regex at a specified index in a user's regex queue
    # * key is the key for the user in whose queue the regex belongs
    # * storekey is the key for the user who sent the regex
    # * index is the index at which to store the regex
    # (The regex will be applied after #{index} pops.)
    # * from is the nick of the user who sent the regex
    # * to is the nick of the user whose message will be replaced
    # * regex is the message containing the replacement, sans index
    def set_regex(key, storekey, index, from, to, regex)
      if(!@regexes[key])
        @regexes[key] = create_fixedqueue()
      end

      # puts("Storing regex #{regex} for #{key}(#{index})")
      store = [storekey, from, to, regex]

      if(@regexes[key][index])
        return @regexes[key][index] << store
      else
        return @regexes[key][index] = [store]
      end
    end # set_regex

    # Pops a user's regexes from his queue
    # * key is the storage key of the user whose regexes we want
    def pop_regexes(key)
      if(!@regexes[key])
        @regexes[key] = create_fixedqueue()
      end
      return @regexes[key].pop()
    end # pop_regexes

    # Gets a user's text from his queue
    # * key is the storage key of the user whose text we want
    # * index is the index of the message we want
    def get_text(key, index)
      # puts("Getting #{key}[#{index}](#{@NOMINAL_SIZE-index})")
      if(!@lines[key])
        @lines[key] = create_fixedqueue()
      end
      return @lines[key][@NOMINAL_SIZE-index]
    end # get_text

    # Pushes a message into a user's queue
    # * key is the storage key of the user
    # * text is the message to be pushed
    def push_text(key, text)
      if(!@lines[key])
        @lines[key] = create_fixedqueue()
      end
      return @lines[key].push(text)
    end # push_text

    # Dumps the last 10 lines for key
    def dump(key)
      if(@lines[key])
        return (1..10).collect{ |i|
          @lines[key][-i]
        }
      else
        puts("#{key} not found")
      end
      return []
    end # dump
  end # REEval
end # REEval
