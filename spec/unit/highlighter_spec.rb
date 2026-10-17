require 'rspec'
require 'mongoid/full_text_search/highlighter'

describe Mongoid::FullTextSearch::Highlighter do
  let(:config) do
    {
      alphabet: Hash[('a'..'z').map { |character| [character, true] }],
      word_separators: { ' ' => true, '-' => true },
      ngram_width: 3, max_ngrams_to_search: 6, remove_accents: true,
      apply_prefix_scoring_to_all_words: true, index_full_words: true,
      index_short_prefixes: false, stop_words: { 'the' => true }
    }
  end

  it 'returns plain text, escaped HTML and half-open original character ranges' do
    text = 'A GHOST & <script>alert(1)</script>'
    snippets = described_class.highlight(text, 'ghost', config)
    expect(snippets).to eq([
                             { text: text, html: 'A <mark>GHOST</mark> &amp; &lt;script&gt;alert(1)&lt;/script&gt;',
                               start: 0, end: text.length, ranges: [{ start: 2, end: 7 }] }
                           ])
  end

  it 'maps composed and decomposed accents to whole original graphemes' do
    ["A Caf\u00e9!", "A Cafe\u0301!"].each do |text|
      snippet = described_class.highlight(text, 'cafe', config).first
      expect(snippet[:html]).to eq("A <mark>#{text[2...-1]}</mark>!")
      expect(snippet[:ranges]).to eq([{ start: 2, end: text.length - 1 }])
    end
  end

  it 'includes discarded characters between matching normalized characters' do
    snippet = described_class.highlight('g.h.o.s.t', 'ghost', config).first
    expect(snippet[:html]).to eq('<mark>g.h.o.s.t</mark>')
    expect(snippet[:ranges]).to eq([{ start: 0, end: 9 }])
  end

  it 'supports Unicode alphabets and original character rather than byte offsets' do
    options = config.merge(alphabet: /[\p{L}\p{M}\p{N}]/)
    snippet = described_class.highlight("\u4e2d\u6587 Caf\u00e9", 'cafe', options).first
    expect(snippet[:ranges]).to eq([{ start: 3, end: 7 }])
  end

  it 'merges overlapping and adjacent ngram matches' do
    snippet = described_class.highlight('ghost ghost', 'ghost', config).first
    expect(snippet[:html]).to eq('<mark>ghost</mark> <mark>ghost</mark>')
    expect(snippet[:ranges]).to eq([{ start: 0, end: 5 }, { start: 6, end: 11 }])
  end

  it 'uses bounded query samples, not every substring in a long query' do
    options = config.merge(max_ngrams_to_search: 2, index_full_words: false)
    expect(described_class.highlight('def', 'abcdefghijk', options)).to eq([])
    expect(described_class.highlight('abc and ijk', 'abcdefghijk', options).first[:ranges]).to eq(
      [{ start: 0, end: 3 }, { start: 8, end: 11 }]
    )
  end

  it 'only highlights full-word terms at word boundaries' do
    options = config.merge(ngram_width: 6)
    expect(described_class.highlight('bob bobcat', 'bob', options).first[:html]).to eq('<mark>bob</mark> bobcat')
  end

  it 'only highlights short-prefix terms at the start of a word' do
    options = config.merge(ngram_width: 4, index_full_words: false, index_short_prefixes: true)
    expect(described_class.highlight('abcat cater', 'cat', options).first[:html]).to eq('abcat <mark>cat</mark>er')
  end

  it 'respects disabled stop-word bonuses but retains sliding-window matches' do
    expect(described_class.highlight('the cat', 'the', config.merge(ngram_width: 4))).to eq([])
    expect(described_class.highlight('the cat', 'the', config).first[:html]).to eq('<mark>the</mark> cat')
  end

  it 'bounds snippet count and context while keeping source ranges absolute' do
    text = "ghost#{' ' * 40}ghost#{' ' * 40}ghost"
    snippets = described_class.highlight(text, 'ghost', config, snippet_size: 9, max_snippets: 2)
    expect(snippets.length).to eq(2)
    expect(snippets.map { |snippet| snippet[:text].length }).to eq([9, 9])
    expect(snippets[1][:ranges]).to eq([{ start: 45, end: 50 }])
    snippets.each do |snippet|
      expect(text[snippet[:start]...snippet[:end]]).to eq(snippet[:text])
    end
  end

  it 'does not truncate a matching span longer than the requested snippet' do
    text = 'abcdefghijk'
    snippet = described_class.highlight(text, text, config, snippet_size: 3).first
    expect(snippet[:html]).to eq('<mark>abcdefghijk</mark>')
  end

  it 'does not drop a match crossing a context boundary' do
    snippets = described_class.highlight('cat cat cat', 'cat', config, snippet_size: 6)
    expect(snippets.flat_map { |snippet| snippet[:ranges] }).to eq(
      [{ start: 0, end: 3 }, { start: 4, end: 7 }, { start: 8, end: 11 }]
    )
  end

  it 'returns no snippets for nil, empty, unmatched, or empty normalized queries' do
    [nil, '', 'painting'].each { |text| expect(described_class.highlight(text, 'ghost', config)).to eq([]) }
    [nil, '', '!!!'].each { |query| expect(described_class.highlight('ghost', query, config)).to eq([]) }
  end

  it 'validates display limits even for empty text' do
    [nil, 0, -1, 1.5].each do |invalid|
      expect { described_class.highlight(nil, nil, config, snippet_size: invalid) }.to raise_error(ArgumentError)
      expect { described_class.highlight(nil, nil, config, max_snippets: invalid) }.to raise_error(ArgumentError)
    end
  end

  it 'does not mutate text, query, or configuration' do
    text = 'A ghost'.freeze
    query = 'ghost'.freeze
    original = Marshal.dump(config)
    described_class.highlight(text, query, config.freeze)
    expect(text).to eq('A ghost')
    expect(query).to eq('ghost')
    expect(Marshal.dump(config)).to eq(original)
  end
end
