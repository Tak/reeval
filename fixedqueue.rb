#!/usr/bin/env ruby

# This program is free software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License as published by the Free Software Foundation; either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
require 'monitor'

# A thread-safe queue of fixed size
class FixedQueue
	include Enumerable
	include MonitorMixin

	# Constructor
	# * size is the size to be used for the queue
	def initialize(size)
		@items = Array.new(size)
		super()
	end # initialize

	# For enumerable
	def each()
		synchronize {
			@items.each{ |item| yield item }
		}
	end # each

	# For enumerable
	def <=>()
		return 0 # no sorting!
	end # <=>

	# Pushes an item onto the front of the queue, 
	# and returns the popped item
	# * item is the new item to be added
	def push(item)
		synchronize {
			@items << item
			return @items.slice!(0)
		}
	end # push

	# Pushes nil onto the front of the queue, 
	# and returns the popped item
	def pop()
		return push(nil)
	end # pop

	# Returns the indexth item in the queue
	# * index is the index of the item to be returned
	def [](index)
		return @items[index]
	end # []

	# Sets the indexth item in the queue 
	# and returns it
	# * index is the index of the item to be set
	# * value is the value to be set
	def []=(index, value)
		return @items[index] = value
	end # []=
end # FixedQueue


# test
if(__FILE__ == $0)

require 'test/unit'

class FixedQueueTest < Test::Unit::TestCase
	def test_default
		fq = FixedQueue.new(3)
		assert_not_nil(fq)

		fq.each{ |x| assert_nil(x) }
		1.upto(3).each{ |x| assert_nil(fq.push(x)) }
		1.upto(3).each{ |x| assert_equal(x, fq.pop()) }
		1.upto(3).each{ |x| assert_equal(x, fq[x-1] = x) }
		1.upto(3).each{ |x| assert_equal(x, fq[x-1]) }
	end # test_default
end # FixedQueueTest

end
