-- Preparation of Gutenberg's UTF-8 plain text. No HTML/EPUB guessing: the
-- original download is retained separately, including its credits and license.
local M = {}

local function marker(line, kind)
  local qualifier, body =
    line:upper():match('^%*%*%* ' .. kind .. ' OF (.-) PROJECT GUTENBERG (.-) %*%*%*%s*$')
  return (qualifier == 'THE' or qualifier == 'THIS')
    and (body:match('^EBOOK ') or body:match('^ETEXT '))
end

local function blank(line)
  return not line or not line:find('%S')
end

local function heading(lines, i)
  local line = vim.trim(lines[i])
  if blank(line) or #line > 160 or not blank(lines[i - 1]) then
    return false
  end
  -- A following blank allows a separate subtitle, but is not enough to rule
  -- out tables of contents (Moby Dick puts a blank after every entry).
  if not blank(lines[i + 1]) and not blank(lines[i + 2]) then
    return false
  end
  local upper = line:upper()
  if
    upper:match('^CHAPTER%s+%S')
    or upper:match('^ACT%s+[IVX%d]')
    or upper:match('^BOOK%s+[IVX%d]')
    or upper:match('^PART%s+[IVX%d]')
  then
    -- Prefer paragraph-based parts to false chapters in compact/ambiguous
    -- layouts. Gutenberg's body chapters normally have extra blank padding.
    return blank(lines[i - 2]) and 'section'
  end
  -- Isolated capitals also cover individual poems. Require generous spacing so
  -- speakers, verse lines, and lists of contents do not become spurious units.
  return i > 2
    and blank(lines[i - 2])
    and blank(lines[i + 1])
    and blank(lines[i + 2])
    and line == upper
    and line:find('%u')
    and 'title'
end

local function wrap(line)
  -- Keep intentional indentation, tabular spacing, short verse and the source's
  -- existing physical breaks. Only overlong, unindented prose needs wrapping.
  if
    vim.fn.strwidth(line) <= 80
    or line:match('^%s')
    or line:find('  ', 1, true)
    or line:find('\t', 1, true)
  then
    return { line }
  end
  local rows, row = {}, ''
  for word in line:gmatch('%S+') do
    if row ~= '' and vim.fn.strwidth(row .. ' ' .. word) > 72 then
      rows[#rows + 1], row = row, ''
    end
    row = row == '' and word or row .. ' ' .. word
  end
  rows[#rows + 1] = row
  return rows
end

function M.prepare(lines, title, preserve_lines)
  local first, last
  for i, line in ipairs(lines) do
    if line:find('[%z\1-\8\11-\31\127]') then
      error('Lilt: unsupported control character in Gutenberg text', 0)
    end
    if marker(line, 'START') then
      if first then
        error('Lilt: ambiguous Gutenberg start markers', 0)
      end
      first = i + 1
    elseif marker(line, 'END') then
      if last then
        error('Lilt: ambiguous Gutenberg end markers', 0)
      end
      last = i - 1
    end
  end
  if not first or not last or first > last then
    error('Lilt: cannot safely locate the Gutenberg text boundaries', 0)
  end
  while first <= last and blank(lines[first]) do
    first = first + 1
  end
  while last >= first and blank(lines[last]) do
    last = last - 1
  end
  if first > last then
    error('Lilt: Gutenberg text is empty', 0)
  end
  local boundaries, structured = {}, false
  for i = first, last do
    local kind = heading(lines, i)
    if kind == 'section' or (kind == 'title' and not structured) then
      boundaries[#boundaries + 1] = i
      structured = structured or kind == 'section'
    end
  end
  boundaries[#boundaries + 1] = last + 1
  local boundary = 1
  local units, rows, unit_title, nonblank = {}, {}, title, 0
  local function flush()
    while #rows > 0 and blank(rows[#rows]) do
      table.remove(rows)
    end
    local start = 1
    while start <= #rows and blank(rows[start]) do
      start = start + 1
    end
    if start > #rows then
      rows = {}
      return
    end
    units[#units + 1] = { title = unit_title, lines = vim.list_slice(rows, start) }
    rows, nonblank = {}, 0
  end
  local part = 1
  for i = first, last do
    if i == boundaries[boundary] then
      -- A volume heading alone belongs with the following poem/chapter.
      if nonblank > 1 then
        flush()
      end
      boundary = boundary + 1
      unit_title, part = vim.trim(lines[i]), 1
      if not blank(lines[i + 1]) then
        unit_title = unit_title .. ' ' .. vim.trim(lines[i + 1])
      end
    elseif #rows >= 300 and blank(lines[i]) and boundaries[boundary] - i >= 80 then
      flush()
      part = part + 1
      unit_title = unit_title:gsub(' · %d+$', '') .. ' · ' .. part
    end
    for _, row in ipairs(preserve_lines and { lines[i] } or wrap(lines[i])) do
      rows[#rows + 1] = row
      if not blank(row) then
        nonblank = nonblank + 1
      end
    end
  end
  flush()
  return units
end

return M
