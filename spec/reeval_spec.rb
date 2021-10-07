require 'reeval'

# <jcopenha> Tak: why don't you just rerun your regression test suite
RSpec.describe REEval do
  before(:all){ @reeval = REEval::REEval.new() }

  it 'has a version number' do
    expect(REEval::VERSION).not_to be nil
  end

  context 'when performing index-based message processing' do
    it 'performs replacements on messages from yourself' do
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      myto = nil
      inputs = [
          ['blah', nil],
          ['s/blah/foo/ > s/foo/meh', 'meh'],
          ['tr/a-j/A-J/ > tr/k-z/K-Z', 'MEH'],
          ['s/./A/g', 'AAA'],
          ['s/a/!/gi', '!!!'],
          ['4tr/abhl/lhba', 'halb'],
          ['-1s/hal/HAL', nil],
          ['hallo', 'HALlo'],
          ["\001ACTIONwat\001", nil],
          ['s/wat/duh/', "\001ACTIONduh\001"],
          ['s/duh/wat/', "\001ACTIONwat\001"]
      ]
      count = 0

      inputs.each{ |input|
        @reeval.process_full(storekey, mynick, input[0]){ |from, to, msg|
          count += 1
          expect([from, to, msg]).to eq([mynick, myto, input[1]])
        }
      }
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs replacements on directed messages' do
      storekey = 'Tak|#utter-failure'
      key = 'jcopenha|#utter-failure'
      mynick = 'Tak'
      myto = 'JCopenHa'
      inputs = [
          ['s/blah/foo/ > s/foo/meh', 'meh'],
          ['tr/a-j/A-J/ > Tr/k-z/K-Z/', 'BLAH'],
          ['S/./A/g', 'AAAA'],
          ['s/a/!/gi', 'bl!h'],
          ['1tr/abhl/lhba', 'halb']
      ]
      count = 0

      ['blah','blah'].each{ |msg|
        @reeval.process_full(key, myto, msg){ |from, to, msg|
          raise 'Should not execute'
        }
      }

      inputs.each{ |input|
        @reeval.process_full(storekey, mynick, "#{myto}: #{input[0]}"){ |from, to, msg|
          count += 1
          expect([from, to, msg]).to eq([mynick, myto, input[1]])
        }
      }
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs transpositions' do
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      myto = nil
      inputs = [
          ['The quick, brown fox jumps over the lazy dog.', nil],
          ['tr/aeiou/AEIOU/', 'ThE qUIck, brOwn fOx jUmps OvEr thE lAzy dOg.'],
          ['TR/a-zA-Z/A-Za-z/', 'tHe QuiCK, BRoWN FoX JuMPS oVeR THe LaZY DoG.'],
          ['tr/a-zA-Z/*', '*** *****, ***** *** ***** **** *** **** ***.'],
          ['tr/*/œ', 'œœœ œœœœœ, œœœœœ œœœ œœœœœ œœœœ œœœ œœœœ œœœ.'],
          ['tr/œ/ß', 'ßßß ßßßßß, ßßßßß ßßß ßßßßß ßßßß ßßß ßßßß ßßß.']
      ]
      count = 0

      inputs.each{ |input|
        @reeval.process_full(storekey, mynick, input[0]){ |from, to, msg|
          count += 1
          expect([from, to, msg]).to eq([mynick, myto, input[1]])
        }
      }
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs stochastic replacements and transpositions' do
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      myto = nil
      inputs = [
          ['The quick, brown fox jumps over the lazy dog.', nil],
          ['tR/aeiou/AEIOU/50%', 'ThE qUIck, brOwn fOx jUmps OvEr thE lAzy dOg.'],
          ['Tr/a-zA-Z/A-Za-z/50%', 'tHe QuiCK, BRoWN FoX JuMPS oVeR THe LaZY DoG.'],
          ['s/\w+/yaddle/50%', 'yaddle yaddle, yaddle yaddle yaddle yaddle yaddle yaddle yaddle.'],
          ['S/\w+/yaddle/g > s/yaddle/eeerm/50%', 'yaddle yaddle, yaddle yaddle yaddle yaddle yaddle yaddle yaddle.']
      ]
      count = 0

      inputs.each{ |input|
        @reeval.process_full(storekey, mynick, input[0]){ |from, to, msg|
          count += 1
          expect([from, to, msg]).to_not eq([mynick, myto, input[1]])
        }
      }
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs pipelined operations' do
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      myto = nil
      inputs = [
          ['The quick, brown fox jumps over the lazy dog.', nil],
          ['s/\w*o\w*/yaddle/g > tR/d/g', 'The quick, yaggle yaggle jumps yaggle the lazy yaggle.']
      ]
      count = 0

      inputs.each{ |input|
        @reeval.process_full(storekey, mynick, input[0]){ |from, to, msg|
          count += 1
          expect([from, to, msg]).to eq([mynick, myto, input[1]])
        }
      }
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs operations on queued messages' do
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      myto = nil
      inputs = [
          ['4tr/aeiou/AEIOU', 'blAh'],
          ['4tr/aeiou/AEIOU', 'mEh'],
          ['4tr/aeiou/AEIOU', 'fOO'],
          ['4tr/aeiou/AEIOU', 'bAr'],
          ['4tr/aeiou/AEIOU', 'bAz'],
          ['-9tr/aeiou/AEIOU', nil],
          ['-7tr/aeiou/AEIOU', nil],
          ['-5tr/aeiou/AEIOU', nil],
          ['-3tr/aeiou/AEIOU', nil],
          ['-1tr/aeiou/AEIOU', nil],
          ['blah', 'blAh'],
          ['meh', 'mEh'],
          ['foo', 'fOO'],
          ['bar', 'bAr'],
          ['baz', 'bAz']
      ]
      count = 0

      ['blah','meh','foo','bar','baz'].each{ |text|
        @reeval.process_full(storekey, mynick, text){ |from, to, msg|
          raise 'Should not execute'
        }
      }

      # Bounds check
      @reeval.process_full(storekey, mynick, '100s/.*/meh'){ |from, to, msg|
        raise 'Should not execute'
      }

      inputs.each{ |input|
        @reeval.process_full(storekey, mynick, input[0]){ |from, to, msg|
          count += 1
          expect([from, to, msg]).to eq([mynick, myto, input[1]])
        }
      }
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs replacements using fill expressions' do
      trigger = false
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'

      inputs = [
          ['blah foo bar', 's/(\w+)/a{\l1}/', 'aaaa foo bar'],
          ['blah foo bar', 's/(\w+)/(ab){\l1}/', 'abababab foo bar'],
          ['blah foo bar', 's/(\w+)/(ab){\l1}/ > s/(\w+) (\w+)/\1 b{\l2}/', 'abababab bbb bar'],
          ['blah foo bar', 's/(\w+)/a{\l1}/ > S/(\w+) (\w+)/\1 (ba){\l2}/', 'aaaa bababa bar'],
      ]
      count = 0

      inputs.each{ |input|
        trigger = false
        @reeval.process_full(storekey, mynick, input[0]){ |from, to, msg|
          raise 'Should not execute'
        }

        @reeval.process_full(storekey, mynick, input[1]){ |from, to, msg|
          count += 1
          expect(msg).to eq(input[2])
          trigger = true
        }
        expect(trigger).to eq(true)
      }
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end
  end

  context 'when performing reply-based message processing' do
    it 'performs replacements on messages from yourself' do
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      inputs = [
        ['blah', nil, ''],
        ['s/blah/foo/ > s/foo/meh', 'meh', 'blah'],
        ['tr/a-j/A-J/ > tr/k-z/K-Z', 'MEH', 'meh'],
        ['s/./A/g', 'AAA', 'MEH'],
        ['s/a/!/gi', '!!!', 'AAA'],
        ['4tr/abhl/lhba', 'halb', 'blah'],
        ["\001ACTIONwat\001", nil, ''],
        ['s/wat/duh/', "\001ACTIONduh\001", "\001ACTIONwat\001"],
        ['s/duh/wat/', "\001ACTIONwat\001", "\001ACTIONduh\001"]
      ]
      count = 0

      inputs.each{ |input|
        @reeval.process_reply(storekey, mynick, input[0], nil, input[2]){ |from, to, msg|
          count += 1
          expect([from, to, msg]).to eq([mynick, nil, input[1]])
        }
      }
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs replacements on directed messages' do
      storekey = 'Tak|#utter-failure'
      key = 'jcopenha|#utter-failure'
      mynick = 'Tak'
      myto = 'JCopenHa'
      jcopenhinput = 'blah'
      inputs = [
        ['s/blah/foo/ > s/foo/meh', 'meh'],
        ['tr/a-j/A-J/ > Tr/k-z/K-Z/', 'BLAH'],
        ['S/./A/g', 'AAAA'],
        ['s/a/!/gi', 'bl!h'],
        ['1tr/abhl/lhba', 'halb']
      ]
      count = 0

      [jcopenhinput, jcopenhinput].each do |msg|
        @reeval.process_reply(key, mynick, msg, myto, msg) do
          raise 'Should not execute'
        end
      end

      inputs.each do |input|
        @reeval.process_reply(storekey, mynick, "#{myto}: #{input[0]}", myto, jcopenhinput) do |from, to, msg|
          count += 1
          expect([from, to, msg]).to eq([mynick, myto, input[1]])
        end
      end
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs transpositions' do
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      inputs = [
        ['The quick, brown fox jumps over the lazy dog.', nil, ''],
        ['tr/aeiou/AEIOU/', 'ThE qUIck, brOwn fOx jUmps OvEr thE lAzy dOg.', 'The quick, brown fox jumps over the lazy dog.'],
        ['TR/a-zA-Z/A-Za-z/', 'tHe QuiCK, BRoWN FoX JuMPS oVeR THe LaZY DoG.', 'ThE qUIck, brOwn fOx jUmps OvEr thE lAzy dOg.'],
        ['tr/a-zA-Z/*', '*** *****, ***** *** ***** **** *** **** ***.', 'tHe QuiCK, BRoWN FoX JuMPS oVeR THe LaZY DoG.'],
        ['tr/*/œ', 'œœœ œœœœœ, œœœœœ œœœ œœœœœ œœœœ œœœ œœœœ œœœ.', '*** *****, ***** *** ***** **** *** **** ***.'],
        ['tr/œ/ß', 'ßßß ßßßßß, ßßßßß ßßß ßßßßß ßßßß ßßß ßßßß ßßß.', 'œœœ œœœœœ, œœœœœ œœœ œœœœœ œœœœ œœœ œœœœ œœœ.']
      ]
      count = 0

      inputs.each do |input|
        @reeval.process_reply(storekey, mynick, input[0], mynick, input[2]) do |from, to, msg|
          count += 1
          expect([from, to, msg]).to eq([mynick, mynick, input[1]])
        end
      end
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs stochastic replacements and transpositions' do
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      inputs = [
        ['The quick, brown fox jumps over the lazy dog.', nil, ''],
        ['tR/aeiou/AEIOU/50%', 'ThE qUIck, brOwn fOx jUmps OvEr thE lAzy dOg.', 'The quick, brown fox jumps over the lazy dog.'],
        ['Tr/a-zA-Z/A-Za-z/50%', 'tHe QuiCK, BRoWN FoX JuMPS oVeR THe LaZY DoG.', 'ThE qUIck, brOwn fOx jUmps OvEr thE lAzy dOg.'],
        ['s/\w+/yaddle/50%', 'yaddle yaddle, yaddle yaddle yaddle yaddle yaddle yaddle yaddle.', 'tHe QuiCK, BRoWN FoX JuMPS oVeR THe LaZY DoG.'],
        ['S/\w+/yaddle/g > s/yaddle/eeerm/50%', 'yaddle yaddle, yaddle yaddle yaddle yaddle yaddle yaddle yaddle.', 'yaddle yaddle, yaddle yaddle yaddle yaddle yaddle yaddle yaddle.']
      ]
      count = 0

      inputs.each do |input|
        @reeval.process_reply(storekey, mynick, input[0], mynick, input[2]) do |from, to, msg|
          count += 1
          expect([from, to, msg]).to_not eq([mynick, mynick, input[1]])
        end
      end
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs pipelined operations' do
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      inputs = [
        ['The quick, brown fox jumps over the lazy dog.', nil, ''],
        ['s/\w*o\w*/yaddle/g > tR/d/g', 'The quick, yaggle yaggle jumps yaggle the lazy yaggle.', 'The quick, brown fox jumps over the lazy dog.']
      ]
      count = 0

      inputs.each do |input|
        @reeval.process_reply(storekey, mynick, input[0], mynick, input[2]) do |from, to, msg|
          count += 1
          expect([from, to, msg]).to eq([mynick, mynick, input[1]])
        end
      end
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end

    it 'performs replacements using fill expressions' do
      trigger = false
      storekey = 'Tak|#utter-failure'
      mynick = 'Tak'
      reply_input = 'blah foo bar'

      inputs = [
        ['blah foo bar', 's/(\w+)/a{\l1}/', 'aaaa foo bar'],
        ['blah foo bar', 's/(\w+)/(ab){\l1}/', 'abababab foo bar'],
        ['blah foo bar', 's/(\w+)/(ab){\l1}/ > s/(\w+) (\w+)/\1 b{\l2}/', 'abababab bbb bar'],
        ['blah foo bar', 's/(\w+)/a{\l1}/ > S/(\w+) (\w+)/\1 (ba){\l2}/', 'aaaa bababa bar'],
      ]
      count = 0

      inputs.each do |input|
        trigger = false
        @reeval.process_reply(storekey, mynick, input[0], mynick, '') do
          raise 'Should not execute'
        end

        @reeval.process_reply(storekey, mynick, input[1], mynick, reply_input) { |_, _, msg|
          count += 1
          expect(msg).to eq(input[2])
          trigger = true
        }
        expect(trigger).to be_truthy
      end
      expect(count).to eq(inputs.select{|pair| pair[1]}.size)
    end
  end
end
