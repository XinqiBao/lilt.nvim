local M = {}

-- UTF-8 codepoints, with byte offsets for Neovim extmarks. Prepared English
-- punctuation is one display cell; this is deliberately not a grapheme engine.
local function characters(text)
  local result = {}
  for byte, char in text:gmatch('()([%z\1-\127\194-\244][\128-\191]*)') do
    result[#result + 1] = { text = char, byte = byte - 1 }
  end
  return result
end

function M.line(reference, authored)
  local expected, actual = characters(reference), characters(authored)
  local errors, run = {}, nil
  for i, char in ipairs(actual) do
    local wrong = not expected[i] or char.text ~= expected[i].text
    if wrong and not run then
      run = char.byte
    elseif not wrong and run then
      errors[#errors + 1] = { run, char.byte }
      run = nil
    end
  end
  if run then
    errors[#errors + 1] = { run, #authored }
  end
  local pending = expected[#actual + 1]
  return { errors = errors, pending = pending and reference:sub(pending.byte + 1) or '' }
end

return M
