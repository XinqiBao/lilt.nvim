local M = {}

-- Codepoints for comparison; zero-based, exclusive byte ranges for decoration.
-- Prepared English punctuation is supported, not general grapheme layout.
local function characters(text)
  local chars, offsets = {}, { [0] = 0 }
  for byte, char in text:gmatch('()([%z\1-\127\194-\244][\128-\191]*)') do
    chars[#chars + 1] = char
    offsets[#chars] = byte - 1 + #char
  end
  return chars, offsets
end

function M.line(reference, authored)
  local ref, rb = characters(reference)
  local text, tb = characters(authored)
  local n, m = #ref, #text
  local prefix = 0
  while prefix < math.min(n, m) and ref[prefix + 1] == text[prefix + 1] do
    prefix = prefix + 1
  end

  -- Semi-global Levenshtein: consume all authored characters, but allow a free
  -- reference suffix. Ties: more equal characters, endpoint closest to authored
  -- length, earlier endpoint, then equal / replace / extra / missing. An exact
  -- leading prefix is fixed first so repeated text cannot move it backwards.
  local dp = {}
  local function better(a, b)
    if not b then return true end
    if a.cost ~= b.cost then return a.cost < b.cost end
    if a.matches ~= b.matches then return a.matches > b.matches end
    local ad, bd = math.abs(a.finish - m), math.abs(b.finish - m)
    if ad ~= bd then return ad < bd end
    return a.finish < b.finish
  end
  for i = n, prefix, -1 do
    dp[i] = {}
    for j = m, prefix, -1 do
      if j == m then
        dp[i][j] = { cost = 0, matches = 0, finish = i }
      else
        local best
        local function consider(kind, di, dj, cost)
          local tail = dp[i + di][j + dj]
          local candidate = {
            cost = tail.cost + cost,
            matches = tail.matches + (kind == 'equal' and 1 or 0),
            finish = tail.finish, kind = kind, di = di, dj = dj,
          }
          if better(candidate, best) then best = candidate end
        end
        if i < n then
          local equal = ref[i + 1] == text[j + 1]
          consider(equal and 'equal' or 'replace', 1, 1, equal and 0 or 1)
        end
        consider('extra', 0, 1, 1)
        if i < n then consider('missing', 1, 0, 1) end
        dp[i][j] = best
      end
    end
  end

  local spans = {}
  local function append(kind, i, j, ni, nj)
    local last = spans[#spans]
    if last and last.kind == kind then
      last.ref_end, last.text_end = rb[ni], tb[nj]
    else
      spans[#spans + 1] = {
        kind = kind, ref_start = rb[i], ref_end = rb[ni],
        text_start = tb[j], text_end = tb[nj],
      }
    end
  end
  if prefix > 0 then append('equal', 0, 0, prefix, prefix) end
  local i, j = prefix, prefix
  while j < m do
    local step = dp[i][j]
    append(step.kind, i, j, i + step.di, j + step.dj)
    i, j = i + step.di, j + step.dj
  end
  if i < n then append('pending', i, j, n, j) end
  return { spans = spans, coverage = rb[i], pending = reference:sub(rb[i] + 1) }
end

return M
