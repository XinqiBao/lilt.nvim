local compare = require('lilt.compare')
local checks = 0
local function eq(actual, expected, label)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), label .. '\nexpected: ' .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual))
end

local function describe(reference, text)
  local result, description = compare.line(reference, text), {}
  for _, span in ipairs(result.spans) do
    description[#description + 1] = {
      span.kind, reference:sub(span.ref_start + 1, span.ref_end),
      text:sub(span.text_start + 1, span.text_end),
    }
  end
  return description
end
for _, case in ipairs({
  { 'beautiful', 'beautiful', { {'equal','beautiful','beautiful'} } },
  { 'beautiful', 'beau', { {'equal','beau','beau'}, {'pending','tiful',''} } },
  { 'beautiful', 'beat', { {'equal','bea','bea'}, {'missing','u',''}, {'equal','t','t'}, {'pending','iful',''} } },
  { 'beautiful', 'beatiful', { {'equal','bea','bea'}, {'missing','u',''}, {'equal','tiful','tiful'} } },
  { 'beautiful', 'beauutiful', { {'equal','beau','beau'}, {'extra','','u'}, {'equal','tiful','tiful'} } },
  { 'cold', 'bold', { {'replace','c','b'}, {'equal','old','old'} } },
  { 'abcdef', 'abXdeYf', { {'equal','ab','ab'}, {'replace','c','X'}, {'equal','de','de'}, {'extra','','Y'}, {'equal','f','f'} } },
  { 'abc', 'ax', { {'equal','a','a'}, {'replace','b','x'}, {'pending','c',''} } },
  { 'abc', 'bc', { {'missing','a',''}, {'equal','bc','bc'} } },
  { 'abc', 'abc!', { {'equal','abc','abc'}, {'extra','','!'} } },
  { 'a—b', 'ab', { {'equal','a','a'}, {'missing','—',''}, {'equal','b','b'} } },
  { 'abc', 'ac', { {'equal','a','a'}, {'missing','b',''}, {'equal','c','c'} } },
  { 'abc', 'abbc', { {'equal','ab','ab'}, {'extra','','b'}, {'equal','c','c'} } },
  { 'aaa', 'aa', { {'equal','aa','aa'}, {'pending','a',''} } },
  { 'go go', 'go', { {'equal','go','go'}, {'pending',' go',''} } },
  { '', '', {} }, { '', 'x', { {'extra','','x'} } },
  { 'abc', '', { {'pending','abc',''} } },
  { 'a b', 'ab', { {'equal','a','a'}, {'missing',' ',''}, {'equal','b','b'} } },
  { '“a—b', '“x—b', { {'equal','“','“'}, {'replace','a','x'}, {'equal','—b','—b'} } },
  { '“It’s…', '“It’', { {'equal','“It’','“It’'}, {'pending','s…',''} } },
  { '“It’s… — yes.”', '“It’s… — yes.”', { {'equal','“It’s… — yes.”','“It’s… — yes.”'} } },
}) do
  eq(describe(case[1], case[2]), case[3], case[1] .. ' / ' .. case[2])
end
local unicode = compare.line('“a—b', '“x—b')
eq(unicode.spans[2], { kind='replace', ref_start=3, ref_end=4, text_start=3, text_end=4 }, 'byte offsets after curly quote')
eq(unicode.spans[3].ref_end, 8, 'multibyte dash exclusive end')
eq(compare.line('a—b', 'ab').spans[2], {
  kind='missing', ref_start=1, ref_end=4, text_start=1, text_end=1,
}, 'multibyte omission has zero authored width')
eq(compare.line('ab', 'a—b').spans[2], {
  kind='extra', ref_start=1, ref_end=1, text_start=1, text_end=4,
}, 'multibyte extra has zero reference width')
eq(compare.line('“It’s…', '“It’').coverage, #'“It’', 'pending byte boundary')
-- Ambiguous unfinished words are derived from present text, never typing history.
local repeated = {
  {'equal','little ','little '}, {'replace','l','b'}, {'equal','i','i'},
  {'replace','tt','rd'}, {'pending','le bird',''},
}
eq(describe('little little bird', 'little bird'), repeated, 'minimal prefix edits can beat a whole-word omission')
eq(compare.line('little little bird', 'little bird'), compare.line('little little bird', 'little bird'), 'deterministic complete alignment')
print(('Lilt comparison: %d assertions passed on %s'):format(checks, tostring(vim.version())))
vim.cmd('qa!')
