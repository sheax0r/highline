#!/usr/local/bin/ruby -w

# question.rb
#
#  Created by James Edward Gray II on 2005-04-26.
#  Copyright 2005 Gray Productions. All rights reserved.

require "optparse"
require "date"

class HighLine
	#
	# Question objects contain all the details of a single invocation of
	# HighLine.ask().  The object is initialized by the parameters passed to
	# HighLine.ask() and then queried to make sure each step of the input
	# process is handled according to the users wishes.
	#
	class Question
		#
		# Create an instance of HighLine::Question.  Expects a _question_ to ask
		# (can be <tt>""</tt>) and an _answer_type_ to convert the answer to.
		# The _answer_type_ parameter must be a type recongnized by
		# Question.convert(). If given, a block is yeilded the new Question
		# object to allow custom initializaion.
		#
		def initialize( question, answer_type )
			# initialize instance data
			@question    = question
			@answer_type = answer_type
			
			@whitespace   = :strip
			@default      = nil
			@validate     = nil
			@above        = nil
			@below        = nil
			@in           = nil
			@responses     = Hash.new
			
			# allow block to override settings
			yield self if block_given?

			# finalize responses based on settings
			append_default unless default.nil?
			@responses = { :ambiguous_completion =>
			                   "Ambiguous choice.  " +
			                   "Please choose one of #{@answer_type.inspect}.",
		                   :ask_on_error         =>
		                       "?  ",
			               :invalid_type         =>
			                   "You must enter a valid #{@answer_type}.",
		                   :not_in_range         =>
		                       "Your answer isn't within the expected range " +
		                       "(#{expected_range}).",
			               :not_valid            =>
			                   "Your answer isn't valid (must match " +
			                   "#{@validate.inspect})." }.merge(@responses)
		end
		
		# The type that will be used to convert this answer.
		attr_reader :answer_type
		#
		# Used to control whitespace processing for the answer to this question.
		# See HighLine::Question.remove_whitespace() for acceptable settings.
		#
		attr_accessor :whitespace
		# Used to provide a default answer to this question.
		attr_accessor :default
		#
		# If set to a Regexp, the answer must match (before type conversion).
		# Can also be set to a Proc which will be called with the provided
		# answer to validate with a +true+ or +false+ return.
		#
		attr_accessor :validate
		# Used to control range checks for answer.
		attr_accessor :above, :below
		# If set, answer must pass an include?() check on this object.
		attr_accessor :in
		#
		# A Hash that stores the various responses used by HighLine to notify
		# the user.  The currently used responses and their purpose are as
		# follows:
		#
		# <tt>:ambiguous_completion</tt>::  Used to notify the user of an
		#                                   ambiguous answer the auto-completion
		#                                   system cannot resolve.
		# <tt>:ask_on_error</tt>::          This is the question that will be
		#                                   redisplayed to the user in the event
		#                                   of an error.  Can be set to
		#                                   <tt>:question</tt> to repeat the
		#                                   original question.
		# <tt>:invalid_type</tt>::          The error message shown when a type
		#                                   conversion fails.
		# <tt>:not_in_range</tt>::          Used to notify the user that a
		#                                   provided answer did not satisfy
		#                                   the range requirement tests.
		# <tt>:not_valid</tt>::             The error message shown when
		#                                   validation checks fail.
		#
		attr_reader :responses
		
		#
		# Returns the provided _answer_string_ or the default answer for this
		# Question if a default was set and the answer is empty.
		#
		def answer_or_default( answer_string )
			if answer_string.length == 0 and not @default.nil?
				@default
			else
				answer_string
			end
		end

		#
		# Transforms the given _answer_string_ into the expected type for this
		# Question.  Currently supported conversions are:
		#
		# <tt>[...]</tt>::        Answer must be a member of the passed Array. 
		#                         Auto-completion is used to expand partial
		#                         answers.
		# <tt>lambda {...}</tt>:: Answer is passed to lambda for conversion.
		# Date::                  Date.parse() is called with answer.
		# DateTime::              DateTime.parse() is called with answer.
		# Float::                 Answer is converted with Kernel.Float().
		# Integer::               Answer is converted with Kernel.Integer().
		# +nil+::                 Answer is left in String format.  (Default.)
		# String::                Answer is converted with Kernel.String().
		# Regexp::                Answer is fed to Regexp.new().
		# Symbol::                The method to_sym() is called on answer and
		#                         the result returned.
		#
		# This method throws ArgumentError, if the conversion cannot be
		# completed for any reason.
		# 
		def convert( answer_string )
			if @answer_type.nil?
				answer_string
			elsif [Float, Integer, String].include?(@answer_type)
				Kernel.send(@answer_type.to_s.to_sym, answer_string)
			elsif @answer_type == Symbol
				answer_string.to_sym
			elsif @answer_type == Regexp
				Regexp.new(answer_string)
			elsif @answer_type.is_a?(Array)
				# cheating, using OptionParser's Completion module
				@answer_type.extend(OptionParser::Completion)
				@answer_type.complete(answer_string).last
			elsif [Date, DateTime].include?(@answer_type)
				@answer_type.parse(answer_string)
			elsif @answer_type.is_a?(Proc)
				@answer_type[answer_string]
			end
		end

		# Returns a english explination of the current range settings.
		def expected_range(  )
			expected = [ ]

			expected << "above #{@above}" unless @above.nil?
			expected << "below #{@below}" unless @below.nil?
			expected << "included in #{@in.inspect}" unless @in.nil?

			case expected.size
			when 0 then ""
			when 1 then expected.first
			when 2 then expected.join(" and ")
			else        expected[0..-2].join(", ") + ", and #{expected.last}"
			end
		end
		
		#
		# Returns +true+ if the _answer_object_ is greater than the _above_
		# attribute, less than the _below_ attribute and included?()ed in the
		# _in_ attribute.  Otherwise, +false+ is returned.  Any +nil+ attributes
		# are not checked.
		#
		def in_range?( answer_object )
			(@above.nil? or answer_object > @above) and
			(@below.nil? or answer_object < @below) and
			(@in.nil? or @in.include?(answer_object))
		end
		
		#
		# Returns the provided _answer_string_ after processing whitespace by
		# the rules of this Question.  Valid settings for whitespace are:
		#
		# +nil+::                        Do not alter whitespace.
		# <tt>:strip</tt>::              Calls strip().  (Default.)
		# <tt>:chomp</tt>::              Calls chomp().
		# <tt>:collapse</tt>::           Collapses all whitspace runs to a
		#                                single space.
		# <tt>:strip_and_collapse</tt>:: Calls strip(), then collapses all
		#                                whitspace runs to a single space.
		# <tt>:chomp_and_collapse</tt>:: Calls chomp(), then collapses all
		#                                whitspace runs to a single space.
		# <tt>:remove</tt>::             Removes all whitespace.
		# 
		# An unrecognized choice (like <tt>:none</tt>) is treated as +nil+.
		# 
		def remove_whitespace( answer_string )
			if @whitespace.nil?
				answer_string
			elsif [:strip, :chomp].include?(@whitespace)
				answer_string.send(@whitespace)
			elsif @whitespace == :collapse
				answer_string.gsub(/\s+/, " ")
			elsif [ :strip_and_collapse,
			        :chomp_and_collapse ].include?(@whitespace)
				result = answer_string.send(@whitespace.to_s[/^[a-z]+/])
				result.gsub(/\s+/, " ")
			elsif @whitespace == :remove
				answer_string.gsub(/\s+/, "")
			else
				answer_string
			end
		end
		
		# Stringifies the question to be asked.
		def to_s(  )
			@question
		end

		#
		# Returns +true+ if the provided _answer_string_ is accepted by the 
		# _validate_ attribute or +false+ if it's not.
		#
		def valid_answer?( answer_string )
			@validate.nil? or 
			(@validate.is_a?(Regexp) and answer_string =~ @validate) or
			(@validate.is_a?(Proc)   and @validate[answer_string])
		end
		
		private
		
		#
		# Adds the default choice to the end of question between <tt>|...|</tt>.
		# Trailing whitespace is preserved so the function of HighLine.say() is
		# not affected.
		#
		def append_default(  )
			if @question =~ /([\t ]+)\Z/
				@question << "|#{@default}|#{$1}"
			elsif @question == ""
				@question << "|#{@default}|  "
			elsif @question[-1, 1] == "\n"
				@question[-2, 0] =  "  |#{@default}|"
			else
				@question << "  |#{@default}|"
			end
		end
	end
end
