require 'strscan'

class PuppetLint
  class Lexer
    # Document this
    # TODO
    class StringSlurper
      class UnterminatedStringError < StandardError; end

      attr_accessor :scanner
      attr_accessor :results
      attr_accessor :interp_stack

      START_INTERP_PATTERN = %r{\$\{}
      END_INTERP_PATTERN = %r{\}}
      END_STRING_PATTERN = %r{(\A|[^\\])(\\\\)*"}
      UNENC_VAR_PATTERN = %r{(\A|[^\\])\$(::)?(\w+(-\w+)*::)*\w+(-\w+)*}
      ESC_DQUOTE_PATTERN = %r{\\+"}
      LBRACE_PATTERN = %r{\{}

      def initialize(string)
        @scanner = StringScanner.new(string)
        @results = []
        @interp_stack = []
        @segment = []
      end

      def parse
        @segment_type = :STRING

        until scanner.eos?
          if scanner.match?(START_INTERP_PATTERN)
            start_interp
          elsif !interp_stack.empty? && scanner.match?(LBRACE_PATTERN)
            read_char
          elsif scanner.match?(END_INTERP_PATTERN)
            end_interp
          elsif unenclosed_variable?
            unenclosed_variable
          elsif scanner.match?(ESC_DQUOTE_PATTERN)
            @segment << scanner.scan(ESC_DQUOTE_PATTERN)
          elsif scanner.match?(END_STRING_PATTERN)
            end_string
            break if interp_stack.empty?
          else
            read_char
          end
        end

        raise UnterminatedStringError if results.empty? && scanner.matched?

        results
      end

      def unenclosed_variable?
        interp_stack.empty? &&
          scanner.match?(UNENC_VAR_PATTERN) &&
          (@segment.last.nil? ? true : !@segment.last.end_with?('\\'))
      end

      def parse_heredoc(heredoc_tag)
        heredoc_name = heredoc_tag[%r{\A"?(.+?)"?(:.+?)?#{PuppetLint::Lexer::WHITESPACE_RE}*(/.*)?\Z}, 1]
        end_heredoc_pattern = %r{\A\|?\s*-?\s*#{Regexp.escape(heredoc_name)}}
        interpolation = heredoc_tag.start_with?('"')

        @segment_type = :HEREDOC

        until scanner.eos?
          if scanner.match?(end_heredoc_pattern)
            end_heredoc(end_heredoc_pattern)
            break if interp_stack.empty?
          elsif interpolation && scanner.match?(START_INTERP_PATTERN)
            start_interp
          elsif interpolation && !interp_stack.empty? && scanner.match?(LBRACE_PATTERN)
            read_char
          elsif interpolation && unenclosed_variable?
            unenclosed_variable
          elsif interpolation && scanner.match?(END_INTERP_PATTERN)
            end_interp
          else
            read_char
          end
        end

        results
      end

      def read_char
        @segment << scanner.getch

        return if interp_stack.empty?

        case @segment.last
        when '{'
          interp_stack.push(true)
        when '}'
          interp_stack.pop
        end
      end

      def consumed_bytes
        scanner.pos
      end

      def start_interp
        if interp_stack.empty?
          scanner.skip(START_INTERP_PATTERN)
          results << [@segment_type, @segment.join]
          @segment = []
        else
          @segment << scanner.scan(START_INTERP_PATTERN)
        end

        interp_stack.push(true)
      end

      def end_interp
        if interp_stack.empty?
          @segment << scanner.scan(END_INTERP_PATTERN)
          return
        else
          interp_stack.pop
        end

        if interp_stack.empty?
          results << [:INTERP, @segment.join]
          @segment = []
          scanner.skip(END_INTERP_PATTERN)
        else
          @segment << scanner.scan(END_INTERP_PATTERN)
        end
      end

      def unenclosed_variable
        read_char if scanner.match?(%r{.\$})

        results << [@segment_type, @segment.join]
        results << [:UNENC_VAR, scanner.scan(UNENC_VAR_PATTERN)]
        @segment = []
      end

      def end_heredoc(pattern)
        results << [:HEREDOC, @segment.join]
        results << [:HEREDOC_TERM, scanner.scan(pattern)]
      end

      def end_string
        if interp_stack.empty?
          @segment << scanner.scan(END_STRING_PATTERN).gsub!(%r{"\Z}, '')
          results << [@segment_type, @segment.join]
        else
          @segment << scanner.scan(END_STRING_PATTERN)
        end
      end
    end
  end
end
