-- Content discovery shares the Picker's navigation and request lifetime.
local providers = require('lilt.online.providers')
local discovery = require('lilt.online.discovery')
local acquisition = require('lilt.online.acquire')
local information = require('lilt.picker.information')
local M = {}

function M.open(s, root, catalog, units, refresh)
  local sources = providers.list(catalog)
  local categories = discovery.categories(sources)
  local results, expand, browse

  local function details(provider, entry)
    local items = information.identity(entry, 'Current online catalog metadata')
    local page = { title = 'Work information', items = items, selected = items[1] }
    local primary
    local ok, existing = pcall(acquisition.existing, root, entry)
    local function open_copy(reading)
      return {
        key = 'o',
        label = 'Open library copy',
        select = function()
          units(reading, false)
        end,
      }
    end
    if not ok then
      items[#items + 1] = { label = tostring(existing), hl = 'DiagnosticError', wrap = 'full' }
    elseif existing then
      items[#items + 1] = { label = 'Available offline in your library', wrap = 'full' }
      primary = open_copy(existing)
      items[#items + 1] = primary
      items[#items + 1] = {
        label = 'Library copy keeps its saved metadata; use i from its reading units.',
        wrap = 'full',
      }
    else
      if entry.availability then
        items[#items + 1] = { label = entry.availability, wrap = 'full' }
      end
      if entry.supported then
        local acquire
        acquire = {
          key = 'a',
          label = 'Add to library',
          select = function()
            require('lilt.picker.name').prompt(s, root, entry.title, entry.source, function(name)
              s:request(page, function(callback)
                return acquisition.acquire(root, provider, entry, callback, name)
              end, function(reading)
                refresh()
                local action = open_copy(reading)
                acquire.key, acquire.label, acquire.select = action.key, action.label, action.select
                units(reading, false)
              end, 'Downloading and preparing… · Esc cancels')
            end)
          end,
        }
        primary = acquire
        items[#items + 1] = acquire
      end
    end
    vim.list_extend(items, information.fields(entry))
    page.footer = function(width)
      if not primary then
        return width < 40 and ' h back · q/Esc quit ' or ' j/k scroll · h back · q/Esc quit '
      end
      if width < 40 then
        return ' '
          .. primary.key
          .. (primary.key == 'a' and ' Add' or ' Open')
          .. ' · h back · q '
      end
      return ' ' .. primary.key .. ' ' .. primary.label .. ' · h back · q/Esc quit '
    end
    items[#items + 1] = {
      label = 'Back to results',
      select = function()
        s:back()
      end,
    }
    s:push(page)
  end

  local function result_item(provider, entry)
    local detail
    if entry.kind ~= 'group' and not entry.label and entry.authors and #entry.authors > 0 then
      detail = table.concat(entry.authors, '; ')
    end
    return {
      label = entry.label or entry.title,
      detail = detail,
      marker = entry.kind == 'group' and '›' or nil,
      compact = true,
      select = function()
        if entry.kind == 'group' then
          expand(provider, entry.query, true, entry.label or entry.title)
        else
          details(provider, entry)
        end
      end,
    }
  end

  local function menu_items(query)
    return {
      {
        key = 's',
        label = 'Search title or author…',
        select = function()
          s:search(query.search or '', function(value)
            if value ~= '' then
              results({ search = value }, s:page() == browse)
            end
          end)
        end,
      },
      {
        key = 'b',
        label = 'Browse categories…',
        select = function()
          local items = {}
          for _, category in ipairs(categories) do
            items[#items + 1] = {
              label = category.label,
              select = function()
                s:back() -- category menu
                if s:page() ~= browse then
                  s:back() -- search layer
                end
                if browse.category ~= category.id then
                  results({ category = category.id }, false)
                end
              end,
            }
          end
          s:push({ title = 'Browse categories', items = items })
        end,
      },
    }
  end

  expand = function(provider, query, push, title)
    local page = {
      title = title,
      blocking = false,
      items = {},
      height = 20,
      max_width = 96,
    }
    local progress = push and 'Loading…' or 'Loading more…'
    page.footer = function(width)
      if page.busy then
        return ' ' .. progress .. (width < 40 and ' · h back ' or ' · h back · q/Esc quit ')
      end
      if page.status then
        return width < 30 and ' r retry · h back · q ' or ' r retry · h back · q/Esc quit '
      end
      return width < 30 and ' Enter · h back · q ' or ' Enter · h back · q/Esc quit '
    end
    if push then
      s:push(page)
    else
      s:replace(page)
    end
    s:request(page, function(callback)
      return provider.expand(query, callback)
    end, function(result)
      page.items = { { label = result.title or title, hl = 'Title', wrap = 'full' } }
      page.items[#page.items + 1] = { label = 'Source: ' .. provider.name, wrap = 'full' }
      if result.count then
        page.items[#page.items + 1] =
          { label = tostring(result.count) .. ' source records', wrap = 'full' }
      end
      for _, entry in ipairs(result.entries) do
        local item = result_item(provider, entry)
        page.items[#page.items + 1] = item
        page.selected = page.selected or item
      end
      if #result.entries == 0 then
        local empty = { label = result.empty or 'No works found.', wrap = 'full' }
        page.items[#page.items + 1], page.selected = empty, empty
      end
      for _, direction in ipairs({
        { 'previous', '[', 'Previous page' },
        { 'next', ']', 'Next page' },
      }) do
        if result[direction[1]] then
          page.items[#page.items + 1] = {
            key = direction[2],
            label = direction[3],
            select = function()
              expand(provider, result[direction[1]], false, title)
            end,
          }
        end
      end
      s:render(true)
    end, progress, function() end)
  end

  results = function(query, push)
    local feed = discovery.new(sources, query)
    local title = query.search and ('Search: ' .. query.search)
    for _, category in ipairs(categories) do
      if category.id == query.category then
        title = category.label
      end
    end
    local menu = menu_items(query)
    local context = { label = title, hl = 'Title', wrap = 'full' }
    local page = {
      title = 'Discover',
      max_width = 96,
      items = menu,
      selected = context,
      height = 20,
      blocking = false,
      category = query.category,
    }
    if query.category then
      browse = page
    end
    local rows = {}
    local coverage_note = { label = 'Some collections are browse-only.', wrap = 'full' }
    local load, retry
    local progress = 'Loading…'
    local can_retry, can_continue, active_progress = false, false, nil
    page.footer = function(width)
      if active_progress then
        if width < 40 then
          return ' ' .. active_progress .. ' · h back '
        elseif width < 68 then
          return ' ' .. active_progress .. ' · h back · q/Esc quit '
        end
        return ' ' .. active_progress .. ' · s search · b browse · h back · q/Esc quit '
      end
      if can_continue then
        local recovery = '] load · ' .. (can_retry and 'r retry · ' or '')
        if width < 30 then
          return ' ' .. recovery .. (can_retry and 'q ' or 'h back · q ')
        elseif width < 50 then
          return ' ' .. recovery .. 'h back · q '
        elseif width < 68 then
          return ' Enter · ' .. recovery .. 'h back · q '
        end
        return ' Enter · ' .. recovery .. 's search · b browse · h back · q '
      end
      if width < 30 then
        return can_retry and ' r retry · h back · q ' or ' Enter · h back · q '
      elseif width < 50 then
        return can_retry and ' r retry · h back · q/Esc quit '
          or ' Enter · h back · q/Esc quit '
      elseif width < 68 then
        return can_retry and ' Enter · r retry · h back · q/Esc quit '
          or ' Enter · s search · b browse · h back · q quit '
      end
      return ' Enter open · s search · b browse · '
        .. (can_retry and 'r retry · ' or '')
        .. 'h back · q/Esc quit '
    end
    local function present(snapshot, render)
      local items = vim.list_slice(menu)
      items[#items + 1] = context
      local first_arrival = #rows == 0 and #snapshot.entries > 0
      for i, value in ipairs(snapshot.entries) do
        rows[i] = rows[i] or result_item(value.provider, value.entry)
        items[#items + 1] = rows[i]
      end
      local failed, pending, supported = false, false, false
      local browse_only = false
      local errors = {}
      for _, source in ipairs(snapshot.sources) do
        local status = source.status
        supported = supported or status ~= 'unsupported'
        failed = failed or status == 'error'
        pending = pending or status == 'idle' or status == 'loading'
        if status == 'unsupported' and query.search then
          browse_only = true
        elseif status == 'error' then
          errors[#errors + 1] = {
            label = source.provider.name
              .. ' · Request failed: '
              .. tostring(source.error):gsub('%c', ' '),
            hl = 'DiagnosticError',
            wrap = 'full',
          }
        end
      end
      local status
      active_progress = snapshot.loading and progress or nil
      if pending and not snapshot.loading then
        status = 'Paused'
      end
      if failed then
        local failure = #rows > 0 and 'Some results unavailable'
          or (query.search and 'Could not complete search.' or 'Could not complete browse.')
        status = status and (status .. ' · ' .. failure) or failure
      elseif not supported then
        status = 'Unsupported by available sources'
      elseif #rows == 0 and not pending then
        status = query.search and 'No matching works found.' or 'No works found in this batch.'
      end
      context.label = title .. (status and (' · ' .. status) or '')
      can_retry = snapshot.retry and not snapshot.loading
      can_continue = pending and snapshot.more and not snapshot.loading
      local note
      if browse_only then
        note = coverage_note
        -- Empty and failed searches keep their coverage note next to the feedback.
        items[#items + 1] = note
      end
      if not snapshot.loading then
        if snapshot.more then
          items[#items + 1] = load
        end
        if snapshot.retry then
          items[#items + 1] = retry
        end
      end
      for _, item in ipairs(errors) do
        items[#items + 1] = item
      end
      local selected = page.selected
      if selected == context or (selected == coverage_note and first_arrival) then
        if first_arrival then
          page.offset = 0
        end
        page.selected = rows[1] or (not pending and note) or context
        if page.selected == note then
          page.offset = math.huge
        end
      elseif not vim.tbl_contains(items, selected) then
        page.selected = rows[#rows] or context
        page.offset = math.huge
      end
      page.items = items
      if render then
        s:render(true)
      end
    end
    local function request(method, initial)
      progress = method == 'retry' and 'Retrying…'
        or (initial and 'Loading…' or 'Loading more…')
      s:request(
        page,
        function(done, update)
          return feed[method](feed, update, function(snapshot)
            done(nil, snapshot)
          end)
        end,
        function(snapshot)
          present(snapshot, true)
        end,
        progress,
        function(snapshot)
          present(snapshot, true)
        end
      )
    end
    load = {
      key = ']',
      label = 'Load more',
      select = function()
        request('load')
      end,
    }
    retry = {
      key = 'r',
      label = 'Retry failed',
      select = function()
        request('retry')
      end,
    }
    -- Cancellation updates the cached page without rendering over its destination.
    page.cancelled = function()
      present(feed:snapshot(), false)
    end
    present(feed:snapshot(), false)
    if push then
      s:push(page)
    else
      s:replace(page)
    end
    request('load', true)
  end

  results({ category = 'explore' }, true)
end

return M
