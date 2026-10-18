local work = require('lilt.work')
local prep = require('lilt.online.gutenberg')

local function words(lines)
  local result = {}
  for _, row in ipairs(lines) do
    for word in row:gmatch('%S+') do
      result[#result + 1] = word
    end
  end
  return result
end

local function run()
  local source = work.read('tests/fixtures/gutenberg.txt')
  local prepared = prep.prepare(source, 'Test Letters')
  assert(
    #prepared == 3 and prepared[2].title == 'CHAPTER I. The letter',
    'chapters, front matter, and TOC'
  )
  local text = table.concat(prepared[2].lines, '\n')
  assert(
    text:find('    Little Lamb, who made thee?\n    Dost thou know who made thee?\n\n', 1, true),
    'verse and stanza boundaries'
  )
  assert(text:find('“Café, 文学, and a rabbit 🐇,”', 1, true), 'Unicode fidelity')
  assert(text:find('CHORUS', 1, true), 'embedded capitals must stay inside chapters')
  assert(
    table.concat(prepared[3].lines, '\n'):find('  north    south', 1, true),
    'table indentation'
  )
  for _, row in ipairs(prepared[2].lines) do
    assert(vim.fn.strwidth(row) <= 80, 'prose wrapping')
  end
  local original_body, prepared_body, inside = {}, {}, false
  for _, row in ipairs(source) do
    if row:find('*** END OF', 1, true) then
      inside = false
    end
    if inside then
      original_body[#original_body + 1] = row
    end
    if row:find('*** START OF', 1, true) then
      inside = true
    end
  end
  for _, unit in ipairs(prepared) do
    vim.list_extend(prepared_body, unit.lines)
  end
  assert(
    vim.deep_equal(words(original_body), words(prepared_body)),
    'preparation must preserve words and punctuation in order, including word boundaries'
  )
  local verse = prep.prepare(source, 'Poetry', { preserve_lines = true })
  local long_line = table.concat(source, '\n'):match('(The snow arrived[^\n]+)')
  assert(
    vim.fn.strwidth(long_line) > 80 and vim.tbl_contains(verse[2].lines, long_line),
    'cataloged verse keeps even long lines'
  )
  local start_marker = '*** START OF THE PROJECT GUTENBERG EBOOK TEST ***'
  local end_marker = '*** END OF THE PROJECT GUTENBERG EBOOK TEST ***'
  local quoted = {
    start_marker,
    '    “Café,” she said. ‘Don’t’ change — dashes – or …; «文学», ʼ, and café́.',
    '',
    string.rep('A long verse line. ', 8) .. '“Still here.”',
    end_marker,
  }
  local original = vim.deepcopy(quoted)
  local plain = prep.prepare(quoted, 'Quotes', { plain_quotes = true, preserve_lines = true })
  assert(
    vim.deep_equal(plain[1].lines, {
      [[    "Café," she said. 'Don't' change — dashes – or …; «文学», ʼ, and café́.]],
      '',
      string.rep('A long verse line. ', 8) .. '"Still here."',
    }),
    'quote simplification must preserve other Unicode, punctuation, spacing, and verse rows'
  )
  assert(vim.deep_equal(quoted, original), 'preparation must not mutate the source lines')
  -- Moby Dick's unindented, blank-separated contents used to become dozens
  -- of tiny fake chapters. Even wrapped entries must remain in the front matter.
  local contents = {
    start_marker,
    '',
    'MOBY-DICK;',
    '',
    'By Herman Melville',
    '',
    'CONTENTS',
    '',
    'CHAPTER 1. Loomings.',
    '',
    'CHAPTER 2. The Carpet-Bag.',
    '',
    'CHAPTER 56. Of the Less Erroneous Pictures of Whales, and the True',
    'Pictures of Whaling Scenes.',
    '',
    '',
    'CHAPTER 1. Loomings.',
    '',
    'Call me Ishmael.',
    '',
    '',
    'CHAPTER 2. The Carpet-Bag.',
    '',
    'I stuffed a shirt or two into my old carpet-bag.',
    '',
    end_marker,
  }
  local chapters = prep.prepare(contents, 'Moby Dick')
  assert(
    #chapters == 3
      and chapters[2].title == 'CHAPTER 1. Loomings.'
      and chapters[3].title == 'CHAPTER 2. The Carpet-Bag.',
    'blank-separated contents entries must not create chapter units'
  )
  local expected, actual = {}, {}
  for i = 2, #contents - 1 do
    if contents[i]:find('%S') then
      expected[#expected + 1] = contents[i]
    end
  end
  for _, chapter in ipairs(chapters) do
    for _, row in ipairs(chapter.lines) do
      if row:find('%S') then
        actual[#actual + 1] = row
      end
    end
  end
  assert(
    vim.deep_equal(expected, actual),
    'contents and body lines must remain intact and in order'
  )
  for _, bad in ipairs({
    {},
    { 'no markers' },
    { start_marker, start_marker, 'text', end_marker },
    { start_marker, 'text', end_marker, end_marker },
    { start_marker, end_marker },
    { end_marker, 'text', start_marker },
    { start_marker, '\0', end_marker },
  }) do
    assert(not pcall(prep.prepare, bad, 'Bad'), 'unsafe boundaries/control characters accepted')
  end
  local many = { '*** START OF THIS PROJECT GUTENBERG ETEXT LETTERS ***' }
  for i = 1, 650 do
    many[#many + 1] = i % 10 == 0 and '' or 'Row ' .. i
  end
  many[#many + 1] = '*** END OF THIS PROJECT GUTENBERG ETEXT LETTERS ***'
  local parts = prep.prepare(many, 'Letters')
  assert(
    #parts > 1 and #parts[#parts].lines >= 80,
    'long texts need useful parts, without tiny tails'
  )

  print('Lilt Gutenberg: boundaries, layout, text fidelity and reading units passed')
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
