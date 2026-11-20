local catalog = require('lilt.online.catalog')
local materialize = require('lilt.online.materialize')
local M = {}
local filter = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h:h:h')
  .. '/pandoc/gutenberg.lua'

function M.new(base)
  base = base or catalog.default_url
  local provider = {
    id = 'gutenberg',
    name = 'Project Gutenberg',
    menu = {
      { label = 'Popular · most downloaded', query = {} },
      { label = 'Newest · latest catalog IDs', query = { sort = 'descending' } },
      { label = 'Poetry', query = { topic = 'poetry' } },
      { label = 'Short stories', query = { topic = 'short stories' } },
      { label = 'Search title or author…', query = {}, input = 'Search title or author' },
    },
  }

  function provider.browse(query, callback)
    return catalog.fetch(base, query, function(err, result)
      if err then
        callback(err)
        return
      end
      for _, book in ipairs(result.books) do
        book.kind = 'work'
        book.source = {
          provider = provider.id,
          id = tostring(book.id),
          url = 'https://www.gutenberg.org/ebooks/' .. book.id,
        }
        book.rights = book.catalog_entry.copyright == false
            and 'Public domain in the USA. Check copyright in your country.'
          or nil
        book.rights_url = 'https://www.gutenberg.org/policy/license.html'
        book.availability = book.supported and 'Available: EPUB · public domain in the USA'
          or 'Unavailable: requires a public-domain EPUB.'
      end
      local page = query.page or 1
      local title = query.search and ('Search: ' .. query.search)
        or query.topic
        or query.sort and 'Newest'
        or 'Popular'
      callback(nil, {
        title = title .. ' · page ' .. page,
        entries = result.books,
        count = result.count,
        next = result.more and vim.tbl_extend('force', query, { page = page + 1 }) or nil,
        previous = page > 1 and vim.tbl_extend('force', query, { page = page - 1 }) or nil,
        empty = 'No works found. Try another title or author.',
      })
    end)
  end

  function provider.prepare(entry, directory, callback)
    local url = 'https://gutenberg.pglaf.org/cache/epub/'
      .. entry.id
      .. '/pg'
      .. entry.id
      .. '.epub'
    local plain_quotes = #entry.languages == 1 and entry.languages[1] == 'en'
    local metadata = {}
    for _, key in ipairs({
      'title',
      'authors',
      'translators',
      'languages',
      'subjects',
      'bookshelves',
      'source',
      'description',
      'rights',
      'rights_url',
      'publisher',
      'published',
    }) do
      metadata[key] = entry[key]
    end
    return materialize.epub(url, directory, metadata, {
      filter = filter,
      plain_quotes = plain_quotes,
    }, function(err, prepared)
      if err then
        callback(err)
        return
      end
      prepared.snapshot = { catalog_url = entry.catalog_url, entry = entry.catalog_entry }
      prepared.attribution = {
        'Downloaded from: ' .. url,
        'SOURCE.epub is the unmodified download, including original credits and license.',
        'Pandoc converts the EPUB reading order and headings to UTF-8 reading units.',
        'Distribution boilerplate and images are omitted from reading text.',
        'Prose wraps at 72 columns; explicit verse and preformatted line breaks are retained.',
        'Source nav/NCX supplies navigation; body headings are the fallback.',
        'Long sections divide at paragraph breaks under their source chapter.',
        plain_quotes
            and 'English curly quotation marks and apostrophes are converted to straight quotes.'
          or 'Source punctuation is preserved.',
        '',
        'Public domain in the USA. Check the law in your country before use.',
        'Project Gutenberg is a registered trademark; Lilt is an independent client.',
        'Before sharing, retain SOURCE.epub and review the source license and trademark terms:',
        'https://www.gutenberg.org/policy/license.html',
      }
      callback(nil, prepared)
    end)
  end

  return provider
end

return M
