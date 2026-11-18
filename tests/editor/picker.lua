local api = vim.api
local picker = require('lilt.picker')
local work = require('lilt.work')
local root = vim.fn.tempname()
local home = root .. '/library'
local example_root = root .. '/examples'
local notify = vim.notify
local messages = {}
vim.notify = function(message)
  messages[#messages + 1] = message
end
local function keys(text)
  api.nvim_feedkeys(api.nvim_replace_termcodes(text, true, false, true), 'xt', false)
  vim.wait(10, function()
    return false
  end)
end
local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end
local function find(label)
  for i, line in ipairs(lines()) do
    if line:find(label, 1, true) then
      return i
    end
  end
  error('missing picker item: ' .. label .. '\n' .. table.concat(lines(), '\n'))
end
local function choose(label)
  api.nvim_win_set_cursor(0, { find(label), 0 })
  keys('l')
end
local function example_units(title)
  keys('e')
  choose(title)
end
local function selected(label)
  return lines()[api.nvim_win_get_cursor(0)[1]]:find(label, 1, true)
end
local function fixture(name, title, count)
  local directory = example_root .. '/' .. name
  vim.fn.mkdir(directory, 'p')
  local units = {}
  for i = 1, count do
    units[i] = { path = i .. '.txt', title = i == 1 and title or ('Unit ' .. i) }
    vim.fn.writefile({ 'Reference ' .. i }, directory .. '/' .. i .. '.txt')
  end
  vim.fn.writefile({ vim.json.encode({ title = title, units = units }) }, directory .. '/lilt.json')
end
local function no_picker()
  assert(not pcall(api.nvim_get_autocmds, { group = 'LiltPicker' }), 'picker autocmds leaked')
  for _, win in ipairs(api.nvim_list_wins()) do
    assert(api.nvim_win_get_config(win).relative == '', 'picker window leaked')
  end
end
local function run()
  local origin = api.nvim_get_current_win()
  -- Observe configured discovery paths while exercising the real entry/picker.
  local discover, xdg = work.discover, vim.env.XDG_DATA_HOME
  local seen
  work.discover = function(directory)
    seen = directory
    return {}, {}
  end
  for _, case in ipairs({
    { root .. '/data', root .. '/data/lilt/references' },
    { '', vim.env.HOME .. '/.local/share/lilt/references' },
    { 'relative/path', vim.env.HOME .. '/.local/share/lilt/references' },
    { '~/.data', vim.env.HOME .. '/.local/share/lilt/references' },
    { false, vim.env.HOME .. '/.local/share/lilt/references' },
  }) do
    vim.env.XDG_DATA_HOME = case[1] or nil
    package.loaded.lilt = nil
    local lilt = require('lilt')
    assert(seen == nil, 'loading must not discover works')
    lilt.open()
    assert(seen == case[2], 'XDG convention: ' .. tostring(seen))
    keys('q')
    no_picker()
    seen = nil
  end
  package.loaded.lilt = nil
  local lilt = require('lilt')
  lilt.setup({ library = home })
  lilt.open()
  assert(seen == home .. '/references', 'custom library must override default')
  assert(vim.fn.isdirectory(root) == 0, 'loading and browsing must not create directories')
  keys('q')
  work.discover, vim.env.XDG_DATA_HOME = discover, xdg

  fixture('first', 'A poem — ' .. string.rep('長', 80), 2)
  fixture('second', 'B letters — 文学', 24)
  local works = work.discover(example_root)
  assert(#works == 2 and #works[2].units == 24, 'multiple example works and units discovered')
  picker.open(home, example_root)
  assert(
    find('Discover online') < find('Add local work') and find('Add local work') < find('Examples'),
    'empty library actions'
  )
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  picker.open(home, example_root)
  assert(
    api.nvim_get_current_win() == win and api.nvim_get_current_buf() == buf,
    'repeated open must reuse picker'
  )
  keys('ggeh')
  assert(
    api.nvim_win_get_cursor(0)[1] == 1 and not vim.wo.cursorline,
    'return from a shortcut restores an informational cursor position'
  )
  example_units('A poem')
  assert(find('Unit 2'), 'first example has ordered units')
  local width = api.nvim_win_get_width(0)
  for _, line in ipairs(lines()) do
    assert(vim.fn.strdisplaywidth(line) <= width, 'long Unicode titles must fit')
  end
  choose('Unit 2')
  local second_unit = api.nvim_get_current_buf()
  assert(
    vim.bo.buftype == '' and api.nvim_buf_get_name(0) == '',
    'example uses ordinary temporary manuscript'
  )
  keys('iReference<Esc>')
  local undo = vim.fn.undotree().seq_cur
  lilt.close()
  picker.open(home, example_root)
  example_units('A poem')
  choose('Unit 2')
  assert(
    api.nvim_get_current_buf() == second_unit and lines()[1] == 'Reference',
    'example reopens unsaved manuscript'
  )
  assert(vim.fn.undotree().seq_cur == undo, 'example reopen keeps native undo')
  lilt.close()
  picker.open(home, example_root)
  example_units('A poem')
  keys('<CR>')
  local first_unit = api.nvim_get_current_buf()
  assert(
    first_unit ~= second_unit and lines()[1] == '',
    'example units have independent manuscripts'
  )
  lilt.close()
  api.nvim_buf_delete(second_unit, { force = true })
  picker.open(home, example_root)
  example_units('A poem')
  choose('Unit 2')
  assert(
    api.nvim_get_current_buf() ~= second_unit and lines()[1] == '',
    'wiped example starts fresh'
  )
  lilt.close()
  picker.open(home, example_root)
  example_units('B letters')
  keys('G')
  assert(selected('Unit 24'), 'G navigates a long chapter list')
  local unit_buf = api.nvim_get_current_buf()
  assert(vim.fn.winsaveview().topline > 1, 'long unit list scrolls past work metadata')
  keys('99k')
  assert(
    api.nvim_win_get_cursor(0)[1] == 1 and selected('B letters'),
    'upward movement can return to the work title'
  )
  keys('<CR>l<Right>')
  assert(api.nvim_get_current_buf() == unit_buf, 'information rows do not activate reading')
  assert(not vim.wo.cursorline, 'information rows do not look actionable')
  keys('2j')
  assert(api.nvim_win_get_cursor(0)[1] == 3, 'movement counts include information rows')
  keys('2gg')
  assert(api.nvim_win_get_cursor(0)[1] == 2, 'counted gg addresses a text row')
  keys('3G')
  assert(api.nvim_win_get_cursor(0)[1] == 3, 'counted G addresses a text row')
  keys('ggh')
  assert(selected('B letters'), 'back restores work selection')
  keys('<Esc>')
  assert(api.nvim_get_current_win() == origin, 'back/close restores original focus')
  no_picker()

  -- Information is offline metadata, independent of reading and raw snapshots.
  fixture('information', 'D information', 24)
  local info_root = example_root .. '/information'
  local info_manifest = info_root .. '/lilt.json'
  local metadata = vim.json.decode(table.concat(vim.fn.readfile(info_manifest), '\n'))
  metadata.authors = { 'First Writer', 'Second Writer' }
  metadata.translators = { 'A Translator' }
  metadata.languages = { 'en', 'fr' }
  metadata.subjects = { 'First subject', 'Last subject' }
  metadata.bookshelves = { 'Letters' }
  metadata.source = { provider = 'test-source', id = '11', url = 'https://example.invalid/book' }
  metadata.preparation = { wrap_columns = 72, plain_quotes = false }
  vim.fn.writefile({ vim.json.encode(metadata) }, info_manifest)
  vim.fn.writefile({ 'not parsed by information display' }, info_root .. '/SOURCE.json')
  local info_home = root .. '/information-library'
  local installed = require('lilt.library').add(info_home, info_root, 'saved-information')
  local saved_manifest = vim.fn.readfile(installed.root .. '/lilt.json')
  picker.open(info_home, example_root)
  choose('D information')
  keys('G')
  local position, view = api.nvim_win_get_cursor(0), vim.fn.winsaveview()
  local system = vim.system
  vim.system = function()
    error('information must not launch a process')
  end
  keys('i')
  assert(selected('D information'), 'information starts at the official title')
  assert(find('Saved local metadata'), 'local metadata has explicit provenance')
  assert(find('Authors: First Writer; Second Writer'), 'all author names retained')
  assert(find('Translators: A Translator') and find('Languages: en; fr'), 'edition metadata')
  assert(
    find('Subjects: First subject; Last subject') and find('Bookshelves: Letters'),
    'classification'
  )
  assert(find('test-source:11') and find(metadata.source.url), 'portable source identity')
  assert(find('Directory: saved-information'), 'local directory is separate from title')
  assert(
    find('Prose wrap columns: 72') and find('Plain quotes: no'),
    'actual preparation, including false'
  )
  assert(find('Saved catalog file:'), 'retained raw snapshot remains locatable without parsing')
  keys('G<CR>')
  assert(
    vim.deep_equal(api.nvim_win_get_cursor(0), position),
    'information back restores selected unit'
  )
  assert(vim.fn.winsaveview().topline == view.topline, 'information back restores list viewport')
  keys('ih')
  assert(selected('Unit 24'), 'h returns directly to the same unit')
  vim.system = system
  assert(
    vim.deep_equal(vim.fn.readfile(installed.root .. '/lilt.json'), saved_manifest),
    'information never rewrites metadata'
  )
  assert(vim.fn.isdirectory(info_home .. '/manuscripts') == 0, 'information creates no manuscript')
  keys('q')
  picker.open(home, example_root)
  example_units('A poem')
  keys('i')
  local sparse = table.concat(lines(), '\n')
  assert(
    not sparse:find('Source') and not sparse:find('Languages') and not sparse:find('Plain quotes'),
    'missing facts are omitted'
  )
  assert(
    not sparse:find('Unknown') and not sparse:find('Directory:'),
    'examples invent no metadata or installed directory'
  )
  keys('q')
  no_picker()
  vim.fn.delete(info_home, 'rf')
  vim.fn.delete(info_root, 'rf')

  -- Navigation is local metadata; aliases retain the same real manuscript.
  fixture('structured', 'C structured', 3)
  local structured = example_root .. '/structured/lilt.json'
  local data = vim.json.decode(table.concat(vim.fn.readfile(structured), '\n'))
  data.toc = {
    {
      title = 'Volume',
      children = {
        {
          title = 'First chapter',
          path = '1.txt',
          children = {
            { title = 'Second chapter', path = '2.txt' },
          },
        },
        { title = 'First chapter alias', path = '1.txt' },
      },
    },
  }
  vim.fn.writefile({ vim.json.encode(data) }, structured)
  picker.open(home, example_root)
  example_units('C structured')
  local structured_buf = api.nvim_get_current_buf()
  api.nvim_win_set_cursor(0, { find('Volume'), 0 })
  keys('<CR>')
  assert(api.nvim_get_current_buf() == structured_buf, 'group labels do not activate')
  assert(find('Other reading units') < find('Unit 3'), 'unlisted units remain accessible')
  choose('First chapter')
  local authored = api.nvim_get_current_buf()
  keys('iSaved in the real buffer<Esc>')
  lilt.close()
  picker.open(home, example_root)
  example_units('C structured')
  choose('First chapter alias')
  assert(
    api.nvim_get_current_buf() == authored and lines()[1] == 'Saved in the real buffer',
    'aliases share unsaved writing and undo'
  )
  lilt.close()

  -- Selection passively previews references, without navigation or manuscripts.
  local reference = { 'Beginning — 文学 🐇', '', 'Third physical row.' }
  for i = 4, 60 do
    reference[i] = 'Reference row ' .. i
  end
  local preview_path = example_root .. '/second/24.txt'
  vim.fn.writefile(reference, preview_path)
  local columns, editor_lines = vim.o.columns, vim.o.lines
  vim.o.columns, vim.o.lines = 120, 30
  local listed = #vim.fn.getbufinfo({ buflisted = 1 })
  local function preview()
    for _, target in ipairs(api.nvim_list_wins()) do
      if
        api.nvim_win_get_config(target).relative ~= '' and target ~= api.nvim_get_current_win()
      then
        return target, api.nvim_win_get_buf(target)
      end
    end
    error('missing reference preview')
  end
  picker.open(home, example_root)
  example_units('B letters')
  keys('G')
  local list_win = api.nvim_get_current_win()
  local preview_win, preview_buf = preview()
  local excerpt = api.nvim_buf_get_lines(preview_buf, 0, -1, false)
  assert(
    vim.deep_equal(excerpt, vim.list_slice(reference, 1, #excerpt)),
    'preview keeps Unicode and blank rows'
  )
  assert(#excerpt < #reference, 'preview holds only an opening excerpt')
  assert(not api.nvim_win_get_config(preview_win).focusable, 'preview never takes list focus')
  assert(
    vim.bo[preview_buf].readonly and not vim.bo[preview_buf].modifiable,
    'preview is protected'
  )
  assert(
    not pcall(api.nvim_buf_set_lines, preview_buf, 0, 1, false, { 'changed' }),
    'preview rejects edits'
  )
  assert(#vim.fn.getbufinfo({ buflisted = 1 }) == listed, 'preview creates no ordinary buffer')
  assert(vim.fn.isdirectory(home) == 0, 'preview writes no progress or manuscript')
  picker.open(home, example_root)
  assert(api.nvim_get_current_win() == list_win, 'reentry keeps list focus')
  keys('k')
  assert(
    api.nvim_buf_get_lines(preview_buf, 0, 1, false)[1] == 'Reference 23',
    'movement updates the same preview buffer'
  )
  keys('G')
  vim.o.columns = 80
  api.nvim_exec_autocmds('VimResized', {})
  assert(selected('Unit 24'), 'resize keeps selection')
  vim.o.lines = 8
  api.nvim_exec_autocmds('VimResized', {})
  assert(
    not api.nvim_win_is_valid(preview_win) and not api.nvim_buf_is_valid(preview_buf),
    'small terminals release preview resources'
  )
  assert(selected('Unit 24'), 'small terminals retain the unit list')
  local read_unit, reads = work.read_unit, 0
  work.read_unit = function(...)
    reads = reads + 1
    return read_unit(...)
  end
  keys('kG')
  work.read_unit = read_unit
  assert(reads == 0, 'hidden previews do not read reference files')
  vim.o.columns, vim.o.lines = 120, 30
  api.nvim_exec_autocmds('VimResized', {})
  preview_win, preview_buf = preview()
  keys('<CR>')
  no_picker()
  assert(vim.bo.buftype == '' and lines()[1] == '', 'Enter reads directly from the unit list')
  lilt.close()
  assert(
    vim.deep_equal(vim.fn.readfile(preview_path), reference),
    'preview and reading preserve the source'
  )
  -- Automatic preview failures stay local and cannot disrupt the list.
  vim.fn.writefile({ '\255' }, preview_path, 'b')
  local before = #messages
  picker.open(home, example_root)
  example_units('B letters')
  keys('G')
  preview_win, preview_buf = preview()
  assert(
    api.nvim_buf_get_lines(preview_buf, 0, 1, false)[1] == 'Preview unavailable',
    'invalid preview explains the failure inline'
  )
  assert(
    selected('Unit 24') and #messages == before,
    'failed preview leaves navigation usable without notification spam'
  )
  keys('k')
  assert(
    api.nvim_buf_get_lines(preview_buf, 0, 1, false)[1] == 'Reference 23',
    'movement recovers from preview failure'
  )
  keys('q')
  no_picker()
  vim.fn.writefile(reference, preview_path)
  for _, dismiss in ipairs({
    function(target_win)
      api.nvim_win_close(target_win, true)
    end,
    function(_, target_buf)
      api.nvim_buf_delete(target_buf, { force = true })
    end,
    function(target_win)
      api.nvim_win_set_buf(target_win, api.nvim_create_buf(true, false))
    end,
    function()
      api.nvim_set_current_win(origin)
    end,
  }) do
    picker.open(home, example_root)
    example_units('B letters')
    preview_win, preview_buf = preview()
    dismiss(preview_win, preview_buf)
    vim.wait(20, function()
      return false
    end)
    no_picker()
    assert(not api.nvim_buf_is_valid(preview_buf), 'native dismissal releases preview text')
  end
  -- Partial preview initialization must also release its scratch buffer.
  local open_preview, partial_buffer = api.nvim_open_win, nil
  api.nvim_open_win = function(buffer, enter, config)
    if config.focusable == false then
      partial_buffer = buffer
      error('preview initialization failure')
    end
    return open_preview(buffer, enter, config)
  end
  picker.open(home, example_root)
  example_units('B letters')
  api.nvim_open_win = open_preview
  keys('q')
  no_picker()
  assert(
    partial_buffer and not api.nvim_buf_is_valid(partial_buffer),
    'partial preview cleanup releases its buffer'
  )
  vim.o.columns, vim.o.lines = columns, editor_lines

  for _, quit in ipairs({ 'q', '<Esc>' }) do
    picker.open(home, example_root)
    assert(find('[e] Examples'), 'library shortcuts are visible')
    example_units('A poem')
    keys(quit)
    no_picker()
    assert(api.nvim_get_current_win() == origin, 'quit exits directly from nested units')
  end
  picker.open(home, example_root)
  keys('e<Right><BS>')
  assert(selected('A poem'), 'backspace restores the selected work')
  keys('<Left>')
  assert(find('Discover online'), 'left returns to the library')
  keys('q')
  no_picker()

  local open_win = api.nvim_open_win
  api.nvim_open_win = function()
    error('picker initialization failure')
  end
  picker.open(home, example_root)
  api.nvim_open_win = open_win
  no_picker()
  assert(
    messages[#messages]:find('picker initialization failure', 1, true),
    'initialization error must be reported'
  )

  -- Cancellation of the native path prompt returns to the library picker.
  local input = vim.ui.input
  vim.ui.input = function(_, callback)
    callback(nil)
  end
  picker.open(home, example_root)
  choose('Add local work')
  assert(find('Add local work'), 'canceling import must return to library')
  keys('q')
  vim.ui.input = function(_, callback)
    callback(root .. '/missing-work')
  end
  picker.open(home, example_root)
  choose('Add local work')
  assert(find('Add local work'), 'failed import must return to library')
  keys('q')
  vim.ui.input = function(_, callback)
    callback(example_root .. '/second')
  end
  local naming_home = root .. '/naming-library'
  picker.open(naming_home, example_root)
  choose('Add local work')
  local prompt = api.nvim_get_current_buf()
  assert(lines()[1] == works[2].title, 'local naming starts with the official title')
  keys('<Esc>')
  assert(
    find('Add local work') and vim.fn.isdirectory(naming_home .. '/references') == 0,
    'canceling directory input installs nothing'
  )
  choose('Add local work')
  api.nvim_buf_set_lines(0, 0, -1, false, { '…' })
  keys('<CR>')
  assert(
    api.nvim_get_current_buf() ~= prompt and lines()[1] == '…',
    'invalid name stays editable'
  )
  vim.fn.mkdir(naming_home .. '/manuscripts/my-letters', 'p')
  api.nvim_buf_set_lines(0, 0, -1, false, { 'My Letters' })
  local input_buf = api.nvim_get_current_buf()
  keys('<CR>')
  assert(
    api.nvim_get_current_buf() == input_buf and lines()[1] == 'My Letters',
    'orphan manuscript collision preserves input'
  )
  api.nvim_buf_set_lines(0, 0, -1, false, { 'My New_Letters' })
  keys('<CR>')
  keys('i')
  assert(
    find('Directory: my-new-letters'),
    'normalized local directory appears in work information'
  )
  keys('h')
  local local_work = work.validate(naming_home .. '/references/my-new-letters')
  assert(
    local_work.title == works[2].title and not local_work.manifest.short_title,
    'directory input is not book metadata'
  )
  choose('Unit 24')
  assert(
    api.nvim_buf_get_name(0) == naming_home .. '/manuscripts/my-new-letters/24.txt',
    'custom directory determines manuscript association'
  )
  lilt.close()
  vim.ui.input = input
  vim.fn.writefile({ 'not a directory' }, root .. '/invalid-library')
  picker.open(root .. '/invalid-library', example_root)
  example_units('A poem')
  keys('<CR>')
  assert(api.nvim_get_current_buf() == first_unit, 'unusable library must not block examples')
  lilt.close()
  no_picker()
  for _, dismiss in ipairs({
    function(target_win)
      api.nvim_win_close(target_win, true)
    end,
    function(target_win)
      api.nvim_win_set_buf(target_win, api.nvim_win_get_buf(origin))
    end,
    function()
      api.nvim_buf_delete(0, { force = true })
    end,
  }) do
    picker.open(home, example_root)
    local floating = api.nvim_get_current_win()
    dismiss(floating)
    api.nvim_exec_autocmds('VimResized', {})
    vim.wait(10, function()
      return false
    end)
    no_picker()
  end
  picker.open(home, example_root)
  local scratch = api.nvim_get_current_buf()
  api.nvim_set_current_win(origin)
  vim.wait(10, function()
    return false
  end)
  no_picker()
  assert(not api.nvim_buf_is_valid(scratch), 'leaving picker must release scratch buffer')
  assert(vim.fn.isdirectory(home) == 0, 'examples and browsing never write the library')
  -- A corrupt progress file is local to one unit and cannot hide its siblings.
  require('lilt.library').add(home, example_root .. '/second')
  vim.fn.mkdir(home .. '/manuscripts/second/1.txt', 'p')
  vim.fn.writefile({ 'Reference 2' }, home .. '/manuscripts/second/2.txt')
  picker.open(home, example_root)
  keys('l')
  assert(
    table.concat(lines(), '\n'):find('?', 1, true) and find('Unit 24'),
    'one progress error must not hide reading units'
  )
  assert(lines()[find('Unit 2')]:match('100%%$'), 'saved rows show their numeric progress')
  choose('Unit 2')
  assert(
    vim.uv.fs_realpath(api.nvim_buf_get_name(0))
      == vim.uv.fs_realpath(home .. '/manuscripts/second/2.txt'),
    'other units must remain readable'
  )
  lilt.close()
  no_picker()
  fixture('third', works[1].title, 1)
  picker.open(home, example_root)
  choose('Examples')
  assert(find('[first]') and find('[third]'), 'clipped duplicate titles keep visible identifiers')
  assert(
    not table.concat(lines(), '\n'):find('[second]', 1, true),
    'unique titles do not need identifiers'
  )
  choose('[third]')
  local _, duplicate_preview = preview()
  assert(
    api.nvim_buf_get_lines(duplicate_preview, 0, 1, false)[1] == 'Reference 1',
    'duplicate titles preview their own reference'
  )
  keys('q')
  no_picker()
  print('Lilt picker: XDG, hierarchy, multiple examples, buffer reuse and cleanup passed')
end
local ok, err = xpcall(run, debug.traceback)
vim.notify = notify
pcall(require('lilt').close)
vim.fn.delete(root, 'rf')
if not ok then
  io.write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
