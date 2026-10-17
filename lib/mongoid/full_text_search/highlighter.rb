require 'cgi'
require_relative 'ngrams'

module Mongoid
  module FullTextSearch
    # Builds display snippets from current text without storing positional index metadata.
    module Highlighter
      module_function

      def highlight(text, query, config, options = {})
        size = options.fetch(:snippet_size, 160)
        limit = options.fetch(:max_snippets, 3)
        raise ArgumentError, ':snippet_size must be a positive integer' unless size.is_a?(Integer) && size > 0
        raise ArgumentError, ':max_snippets must be a positive integer' unless limit.is_a?(Integer) && limit > 0
        return [] if text.nil?

        terms = Ngrams.calculate(query, config).keys.reject(&:empty?)
        return [] if terms.empty?

        normalized, positions = normalized_positions(text, config)
        indexed_terms = Ngrams.calculate(text, config, false)
        ranges = matching_ranges(normalized, terms & indexed_terms.keys, config).map do |start, finish|
          [positions[start][0], positions[finish - 1][1]]
        end
        merged = merge_ranges(ranges)
        snippets(text, merged, size, limit)
      end

      def normalized_positions(text, config)
        positions = []
        offset = 0
        UnicodeUtils.each_grapheme(text) do |grapheme|
          part = Ngrams.normalized_text(grapheme, config)
          part.length.times { positions << [offset, offset + grapheme.length] }
          offset += grapheme.length
        end
        # Whole-string case conversion can be contextual; preserve its actual characters.
        whole = Ngrams.normalized_text(text, config)
        raise ArgumentError, 'Normalization changed character counts across grapheme boundaries' unless whole.length == positions.length

        [whole, positions]
      end

      def matching_ranges(text, terms, config)
        separators = config[:word_separators]
        terms.each_with_object([]) do |term, ranges|
          offset = 0
          while (start = text.index(term, offset))
            finish = start + term.length
            word_start = start.zero? || separators.key?(text[start - 1])
            word_end = finish == text.length || separators.key?(text[finish])
            window = term.length == config[:ngram_width]
            prefix = config[:index_short_prefixes] && term.length == config[:ngram_width] - 1 && word_start
            word = config[:index_full_words] && word_start && word_end
            ranges << [start, finish] if window || prefix || word
            offset = start + 1
          end
        end
      end

      def merge_ranges(ranges)
        ranges.sort.each_with_object([]) do |range, merged|
          if !merged.empty? && range[0] <= merged.last[1]
            merged.last[1] = [merged.last[1], range[1]].max
          else
            merged << range.dup
          end
        end
      end

      def snippets(text, ranges, size, limit)
        output = []
        consumed = 0
        ranges.each do |start, finish|
          next if start < consumed
          break if output.length >= limit

          width = [size, finish - start].max
          left = [start - (width - (finish - start)) / 2, consumed].max
          left = [left, [text.length - width, 0].max].min
          left = [left, consumed].max
          right = [left + width, text.length].min
          ranges.each { |first, last| right = last if first < right && last > right }
          visible = ranges.select { |first, last| first >= left && last <= right }
          snippet = text[left...right]
          html = ''
          cursor = left
          visible.each do |first, last|
            html << CGI.escapeHTML(text[cursor...first])
            html << '<mark>' << CGI.escapeHTML(text[first...last]) << '</mark>'
            cursor = last
          end
          html << CGI.escapeHTML(text[cursor...right])
          output << { text: snippet, html: html, start: left, end: right,
                      ranges: visible.map { |first, last| { start: first, end: last } } }
          consumed = right
        end
        output
      end

      private_class_method :normalized_positions, :matching_ranges, :merge_ranges, :snippets
    end
  end
end
