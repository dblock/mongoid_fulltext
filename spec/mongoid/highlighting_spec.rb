require 'spec_helper'

describe 'Post-search highlighting' do
  it 'highlights scalar and array fields without changing search results or index records' do
    artwork = TaggedArtwork.create!(title: 'Ghost story', tags: [nil, 'ghost', 'painting'])
    index = TaggedArtwork.mongoid_fulltext_config.keys.first
    collection = artwork.collection.database[index]
    before = collection.find.to_a
    expect(TaggedArtwork.fulltext_search('ghost')).to eq([artwork])
    highlights = artwork.fulltext_highlights('ghost')
    expect(highlights[:title].first[:html]).to eq('<mark>Ghost</mark> story')
    expect(highlights[:title].first[:element]).to be_nil
    expect(highlights[:tags].first[:element]).to eq(1)
    expect(highlights[:tags].first[:html]).to eq('<mark>ghost</mark>')
    expect(collection.find.to_a).to eq(before)
  end

  it 'uses the current translation and computed readers without changing the locale' do
    original_locales = I18n.available_locales
    begin
      I18n.available_locales = %i[en cs]
      artwork = LocalizedArtwork.new(title_translations: { 'en' => 'Flowers', 'cs' => 'Kvetiny' })
      I18n.with_locale(:cs) do
        expect(artwork.fulltext_highlights('kvetiny')[:title].first[:html]).to eq('<mark>Kvetiny</mark>')
        expect(artwork.fulltext_highlights('cesky')[:description].first[:html]).to eq('<mark>Cesky</mark>')
        expect(artwork.fulltext_highlights('flowers')).to eq({})
        expect(I18n.locale).to eq(:cs)
      end
    ensure
      I18n.available_locales = original_locales
    end
  end

  it 'requires a configured index name when multiple indexes exist' do
    artwork = MultiExternalArtwork.new
    expect { artwork.fulltext_highlights('ghost') }.to raise_error(Mongoid::FullTextSearch::UnspecifiedIndexError)
  end

  it 'uses the selected index and forwards snippet limits' do
    artwork = MultiExternalArtwork.new(title: 'ghost', artist: 'ghost', year: 'ghost')
    highlights = artwork.fulltext_highlights('ghost', index: 'mongoid_fulltext.titles', snippet_size: 3, max_snippets: 1)
    expect(highlights.keys).to eq([:title])
    expect(highlights[:title].first[:html]).to eq('<mark>ghost</mark>')
  end

  it 'reports unknown index names' do
    expect { BasicArtwork.new.fulltext_highlights('ghost', index: 'missing') }.to raise_error(KeyError)
  end

  it 'operates on unsaved current text even when no indexed match exists' do
    artwork = BasicArtwork.new(title: 'ghost')
    expect(artwork.fulltext_highlights('ghost')[:title].first[:html]).to eq('<mark>ghost</mark>')
    expect(BasicArtwork.fulltext_search('ghost')).to eq([])
  end
end
