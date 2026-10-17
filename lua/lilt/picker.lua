local api = vim.api
local work = require('lilt.work')
local library = require('lilt.library')
local manuscript = require('lilt.manuscript')
local session = require('lilt.session')
local online = require('lilt.online')
local M = {}
local active
-- Only buffer handles, keyed by example reference path. Authored text and undo
-- remain in ordinary buffers; wiping one starts fresh on the next selection.
local examples = {}

local function clip(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local part = vim.fn.strcharpart(text, 0, math.max(0, width - 1))
  while vim.fn.strdisplaywidth(part) > width - 1 do
    part = vim.fn.strcharpart(part, 0, vim.fn.strchars(part) - 1)
  end
  return part .. '…'
end

local function close()
  local s = active
  if not s then
    return
  end
  active = nil
  if s.cancel then
    s.cancel()
  end
  api.nvim_del_augroup_by_id(s.group)
  if s.win and api.nvim_win_is_valid(s.win) then
    api.nvim_win_close(s.win, true)
  end
  if api.nvim_buf_is_valid(s.buf) then
    api.nvim_buf_delete(s.buf, { force = true })
  end
end

local function attempt(callback)
  local ok, err = pcall(callback)
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

local function discover(directory)
  local ok, works, errors = pcall(work.discover, directory)
  if not ok then
    vim.notify(tostring(works), vim.log.levels.WARN)
    return {}
  end
  if #errors > 0 then
    vim.notify(table.concat(errors, '\n'), vim.log.levels.WARN)
  end
  return works
end

local browse
browse = function(root, example_root, catalog, installed)
  catalog = catalog or online.default_catalog
  if active then
    if api.nvim_win_is_valid(active.win) then
      api.nvim_set_current_win(active.win)
      return
    end
    close()
  end
  local s = { pages = {}, buf = api.nvim_create_buf(false, true) }
  vim.bo[s.buf].bufhidden = 'wipe'
  s.group = api.nvim_create_augroup('LiltPicker', { clear = true })
  active = s

  local function render(reset)
    local page = s.pages[#s.pages]
    local index = not reset and s.win and api.nvim_win_get_cursor(s.win)[1] or page.index or 1
    local width = math.max(1, math.min(72, vim.o.columns - 4))
    local height = math.max(1, math.min(#page.items, vim.o.lines - vim.o.cmdheight - 4))
    local footer = width >= 58 and ' j/k move · Enter/l select · h/q/Esc back/close '
      or ' Enter · q/Esc back '
    local config = {
      relative = 'editor',
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - height - 2) / 2)),
      col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
      border = 'rounded',
      title = clip(' Lilt · ' .. page.title .. ' ', width),
      footer = clip(footer, width),
    }
    local lines = {}
    for _, item in ipairs(page.items) do
      local label = '  ' .. item.label
      local progress_width = item.progress and vim.fn.strdisplaywidth(item.progress)
      if progress_width and width > progress_width + 4 then
        label = clip(label, width - progress_width - 2)
        label = label .. string.rep(' ', width - vim.fn.strdisplaywidth(label) - progress_width)
        label = label .. item.progress
      end
      lines[#lines + 1] = clip(label, width)
    end
    vim.bo[s.buf].modifiable = true
    api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
    vim.bo[s.buf].modifiable = false
    if s.win then
      api.nvim_win_set_config(s.win, config)
    else
      config.style = 'minimal'
      s.win = api.nvim_open_win(s.buf, true, config)
      vim.wo[s.win].cursorline = true
      vim.wo[s.win].cursorlineopt = 'line'
      vim.wo[s.win].wrap = false
      vim.wo[s.win].scrolloff = 0
      vim.wo[s.win].scrollbind = false
      vim.wo[s.win].cursorbind = false
      vim.wo[s.win].foldenable = false
      vim.wo[s.win].conceallevel = 0
      vim.wo[s.win].colorcolumn = ''
      vim.wo[s.win].spell = false
      vim.wo[s.win].winbar = ''
    end
    api.nvim_win_set_cursor(s.win, { math.min(index, #page.items), 0 })
  end

  local function push(page)
    if #s.pages > 0 then
      s.pages[#s.pages].index = api.nvim_win_get_cursor(s.win)[1]
    end
    s.pages[#s.pages + 1] = page
    render(true)
  end

  local function back()
    if s.cancel then
      s.cancel()
      s.cancel = nil
    end
    if #s.pages == 1 then
      close()
    else
      table.remove(s.pages)
      render(true)
    end
  end

  -- Async operations belong to a page and picker lifetime. Back/close cancels
  -- the request, and late callbacks cannot reopen UI or install a work.
  local function pending(page, start, done, message)
    local generation = {}
    page.generation = generation
    page.idle_items = page.idle_items or page.items
    page.items = { { label = (message or 'Loading catalog…') .. ' · h/q/Esc cancels' } }
    render(true)
    s.cancel = start(function(err, value)
      if active ~= s or s.pages[#s.pages] ~= page or page.generation ~= generation then
        return
      end
      s.cancel = nil
      attempt(function()
        if err then
          page.items = {
            {
              label = 'Request failed — retry',
              select = function()
                pending(page, start, done, message)
              end,
            },
            { label = tostring(err):gsub('%c', ' ') },
          }
          vim.notify(tostring(err), vim.log.levels.ERROR)
          render(true)
        else
          page.items = page.idle_items
          done(value)
        end
      end)
    end)
  end

  local function units(reading, temporary)
    local items = {}
    for _, unit in ipairs(reading.units) do
      local progress, progress_error
      if not temporary then
        local ok, value = pcall(library.progress, root, reading, unit)
        if ok then
          progress = value
        else
          progress_error = value
        end
      end
      local saved = not temporary
          and (progress_error and '?' or progress and (progress .. '%') or '—')
        or nil
      items[#items + 1] = {
        label = unit.title,
        progress = saved,
        select = function()
          if progress_error then
            vim.notify(tostring(progress_error), vim.log.levels.WARN)
          end
          local reference = work.read_unit(reading, unit)
          local buf
          if temporary then
            buf = examples[unit.reference]
            if not buf or not api.nvim_buf_is_valid(buf) then
              buf = manuscript.open()
              examples[unit.reference] = buf
            end
          else
            buf = manuscript.open(library.manuscript(root, reading, unit))
          end
          close()
          session.open('ghost', { manuscript = buf, reference = reference })
        end,
      }
    end
    push({ title = reading.title, items = items })
  end

  local function work_items(works, temporary)
    local items = {}
    for _, reading in ipairs(works) do
      items[#items + 1] = {
        label = reading.title .. ' [' .. reading.name .. ']',
        select = function()
          units(reading, temporary)
        end,
      }
    end
    return items
  end

  local home
  local function details(book)
    local page = { title = 'Gutenberg #' .. book.id, items = {} }
    local function info(text)
      -- Give long titles/authors room beyond the clipped catalog row.
      local row = ''
      for word in text:gmatch('%S+') do
        if row ~= '' and vim.fn.strdisplaywidth(row .. ' ' .. word) > 64 then
          page.items[#page.items + 1] = { label = row }
          row = ''
        end
        row = row == '' and word or row .. ' ' .. word
      end
      if row ~= '' then
        page.items[#page.items + 1] = { label = row }
      end
    end
    local ok, existing = pcall(online.existing, root, book)
    if not ok then
      info(tostring(existing))
    elseif existing then
      page.items[#page.items + 1] = {
        label = 'Open library copy',
        select = function()
          units(existing, false)
        end,
      }
    elseif book.supported then
      page.items[#page.items + 1] = {
        label = 'Acquire and read',
        select = function()
          pending(page, function(callback)
            return online.acquire(root, book, callback)
          end, function(reading)
            -- Refresh the library page so backing out immediately shows the copy.
            home(true)
            page.items[1] = {
              label = 'Open library copy',
              select = function()
                units(reading, false)
              end,
            }
            units(reading, false)
          end, 'Downloading and preparing…')
        end,
      }
    else
      info('Unavailable: requires public-domain UTF-8 plain text.')
    end
    info(book.title)
    info('Author: ' .. (book.author ~= '' and book.author or 'Unknown'))
    info('Languages: ' .. table.concat(book.languages, ', '))
    info(online.url(book))
    if book.supported then
      info('Public domain in the USA; check your local law.')
    end
    for _, subject in ipairs(book.subjects) do
      info('Subject: ' .. subject)
    end
    push(page)
  end

  local catalog_page
  catalog_page = function(query, title)
    local page = { title = title, items = { { label = 'Loading catalog…' } } }
    push(page)
    pending(page, function(callback)
      return online.catalog(catalog, query, callback)
    end, function(result)
      local function search()
        s.prompt = true
        local ok, err = pcall(
          vim.ui.input,
          { prompt = 'Title or author: ', default = query.search or '' },
          function(value)
            if active ~= s or not api.nvim_win_is_valid(s.win) then
              return
            end
            api.nvim_set_current_win(s.win)
            s.prompt = false
            if value ~= nil then
              value = vim.trim(value)
              catalog_page(
                value == '' and {} or { search = value },
                value == '' and 'Popular' or value
              )
            end
          end
        )
        if not ok then
          s.prompt = false
          error(err, 0)
        end
      end
      local items = {
        { label = 'Search title or author…', select = search },
        {
          label = 'Browse popular',
          select = function()
            catalog_page({}, 'Popular')
          end,
        },
        {
          label = 'Browse newest',
          select = function()
            catalog_page({ sort = 'descending' }, 'Newest')
          end,
        },
        {
          label = 'Browse poetry',
          select = function()
            catalog_page({ topic = 'poetry' }, 'Poetry')
          end,
        },
        {
          label = 'Browse short stories',
          select = function()
            catalog_page({ topic = 'short stories' }, 'Short stories')
          end,
        },
        { label = result.count .. ' results · page ' .. (query.page or 1) },
      }
      for _, book in ipairs(result.books) do
        items[#items + 1] = {
          label = book.title .. (book.author ~= '' and (' — ' .. book.author) or ''),
          select = function()
            details(book)
          end,
        }
      end
      if #result.books == 0 then
        items[#items + 1] = { label = 'No works found. Try another title or author.' }
      end
      if result.more then
        items[#items + 1] = {
          label = 'More results…',
          select = function()
            local next_query = vim.deepcopy(query)
            next_query.page = (query.page or 1) + 1
            catalog_page(next_query, title)
          end,
        }
      end
      page.items = items
      render(true)
    end)
  end

  home = function(refresh)
    local items = work_items(discover(root .. '/references'), false)
    local empty = #items == 0
    items[#items + 1] = {
      label = 'Add local work…',
      select = function()
        close()
        vim.ui.input({ prompt = 'Local work directory: ', completion = 'dir' }, function(directory)
          attempt(function()
            local reading
            if directory and directory ~= '' then
              local ok, value = pcall(library.add, root, vim.fn.expand(directory))
              if ok then
                reading = value
              else
                vim.notify(tostring(value), vim.log.levels.ERROR)
              end
            end
            browse(root, example_root, catalog, reading)
          end)
        end)
      end,
    }
    items[#items + 1] = {
      label = 'Discover online…',
      select = function()
        catalog_page({}, 'Popular')
      end,
    }
    items[#items + 1] = {
      label = 'Examples',
      select = function()
        local choices = work_items(discover(example_root), true)
        if #choices == 0 then
          vim.notify('Lilt: no examples found.', vim.log.levels.INFO)
          return
        end
        push({ title = 'Examples', items = choices })
      end,
    }
    local title = empty and 'Library (empty)' or 'Library'
    if refresh then
      s.pages[1].title, s.pages[1].items = title, items
    else
      push({ title = title, items = items })
    end
  end

  for _, key in ipairs({ '<CR>', 'l' }) do
    vim.keymap.set('n', key, function()
      attempt(function()
        local selected = s.pages[#s.pages].items[api.nvim_win_get_cursor(s.win)[1]]
        if selected and selected.select then
          selected.select()
        end
      end)
    end, { buffer = s.buf, silent = true })
  end
  for _, key in ipairs({ 'h', '<Esc>', 'q' }) do
    vim.keymap.set('n', key, back, { buffer = s.buf, silent = true })
  end
  api.nvim_create_autocmd('VimResized', {
    group = s.group,
    callback = function()
      if active == s and s.win and api.nvim_win_is_valid(s.win) then
        render(false)
      end
    end,
  })
  api.nvim_create_autocmd({ 'WinLeave', 'BufWipeout' }, {
    group = s.group,
    buffer = s.buf,
    callback = function()
      vim.schedule(function()
        if
          active == s
          and (
            not api.nvim_buf_is_valid(s.buf)
            or (not s.prompt and api.nvim_get_current_win() ~= s.win)
          )
        then
          close()
        end
      end)
    end,
  })
  api.nvim_create_autocmd('VimLeavePre', { group = s.group, callback = close })
  -- Initialization may fail before a window exists (for example, E36).
  local ok, err = pcall(function()
    home()
    if installed then
      units(installed, false)
    end
  end)
  if not ok then
    close()
    error(err, 0)
  end
end

function M.open(root, example_root, catalog)
  attempt(function()
    browse(root, example_root, catalog)
  end)
end

return M
