#!/usr/bin/env ruby

require 'fixedqueue'

# Core regex replacement engine
class REEval
	def initialize()
		@regexes = {}
		@lines = {}
		@RERE = /^([^ :]+: *)?(-?\d*)?s([^\w])([^\3]*)\3([^\3]*)(\3([ginx]+|[0-9]{2}\%|))$/
		@TRRE = /^([^ :]+: *)?(-?\d*)?tr([^\w])([^\3]*)\3([^\3]*)(\3([0-9]{2}\%)?)$/
		@PARTIAL = /^([^ :]+: *)?(-?\d*)?(s|tr)([^\w])/
		@ACTION = /^\001ACTION.*\001/
		@REOPTIONS = {	'i' => Regexp::IGNORECASE,
				'n' => Regexp::MULTILINE,
				'x' => Regexp::EXTENDED
				}
		@NOMINAL_SIZE = 5
	end # initialize

	# Performs a complete message process run
	# * storekey is the storage key of the user who issued the message 
	# (nick|channel)
	# * mynick is the nick of the user who issued the message
	# * sometext is the complete message
	def process_full(storekey, mynick, sometext)
		tonick = get_tonick(sometext)
		index = get_index(sometext)

		if(index && (@NOMINAL_SIZE < index.abs()))
			# Bad index
			puts("Ignoring #{sometext}: index #{index}")
			return XCHAT_EAT_NONE
		end

		# Append channel name for (some) uniqueness
		key = tonick ? storekey.sub(/.*\|/, "#{tonick}|") : storekey

		if(!index && !@ACTION.match(sometext)) 
			# Plain text message - push into the queue
			puts("Storing '#{sometext}' for #{storekey}")
			push_text(storekey, sometext)
		end

		outtext = process_statement(storekey, key, mynick, tonick, index, sometext)

		if(outtext)
			# Replacement has occurred
			if(outtext != sometext)
				yield(mynick, tonick, outtext)
			end

			if(!@RERE.match(outtext) && !@TRRE.match(outtext) && !@ACTION.match(outtext) && !@PARTIAL.match(outtext))
				# Push replaced text into queue and reprocess for pending replacements
				puts("Recursing on '#{outtext}' for #{storekey}")
				process_full(storekey, mynick, outtext)
				# push_text(storekey, outtext)
			end
		end
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
				puts("Got #{oldtext} for #{key}")
				if(oldtext) then return perform_substitution(oldtext, sometext); end
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
					process_full(seed[0], seed[1], seed[3])
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
		outtext = regextext.split('|').inject(plaintext){ |input, expr|
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
				if(foo = subex.match(origtext))
				# Only process replacements that actually match something
					#puts(foo.inspect())

					if(0 < (percent = get_percent(rematches[7])))
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
	end # get_percent

	# Randomly transposes patterns in a string
	# If this is brokeback, blame beanfootage
	# * str is the source string
	# * from is the input pattern of the transposition
	# * to is the output pattern of the transposition
	# * prob is the probability as an integer percentage
	def tr_rand(str, from, to, prob)
		return str.split(//).inject(''){ |accum,x| accum + ((rand(101) < prob) ? x.tr(from, to) : x) }
	end # tr_rand

	# Returns a new FixedQueue of the appropriate size
	def create_fixedqueue()
		return FixedQueue.new(@NOMINAL_SIZE + 1)
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

		puts("Storing regex #{regex} for #{key}(#{index})")
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
end # REEval
