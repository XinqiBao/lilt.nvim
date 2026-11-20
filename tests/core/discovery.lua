local discovery = require('lilt.online.discovery')

local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    label .. '\nexpected: ' .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual)
  )
end

local function work(provider, id, title)
  return {
    kind = 'work',
    title = title or 'Same title',
    source = { provider = provider.id, id = id },
  }
end

local function fake(id, categories, searchable)
  local provider = { id = id, name = id, browse = {}, calls = {} }
  local function request(cursor, callback, search)
    local call = { cursor = cursor, callback = callback, search = search, cancelled = 0 }
    provider.calls[#provider.calls + 1] = call
    return function()
      call.cancelled = call.cancelled + 1
      if call.on_cancel then
        call.on_cancel()
      end
    end
  end
  for _, category in ipairs(categories or {}) do
    provider.browse[category] = request
  end
  if searchable then
    provider.search = function(search, cursor, callback)
      return request(cursor, callback, search)
    end
  end
  return provider
end

local function statuses(feed)
  local result = {}
  for _, source in ipairs(feed:snapshot().sources) do
    result[#result + 1] = source.status
  end
  return result
end

-- Capability discovery and feed creation are pure, with fixed category order.
local a = fake('a', { 'recent', 'poetry', 'explore' }, true)
local b = fake('b', { 'poets', 'explore', 'short_stories' })
local unsupported = { id = 'prepare-only', name = 'Prepare only' }
eq(discovery.categories({ a, unsupported, b }), {
  { id = 'explore', label = 'Explore' },
  { id = 'poetry', label = 'Poetry' },
  { id = 'short_stories', label = 'Short stories' },
  { id = 'recent', label = 'Recently listed' },
  { id = 'poets', label = 'Browse poets' },
}, 'supported categories retain vocabulary order without duplicates')
eq(discovery.categories({ unsupported }), {}, 'no invented capabilities')
local feed = discovery.new({ a, b, unsupported }, { category = 'explore' })
eq(statuses(feed), { 'idle', 'idle', 'unsupported' }, 'initial coverage')
eq({ #a.calls, #b.calls }, { 0, 0 }, 'creation starts no requests')
assert(
  feed:snapshot().more and not feed:snapshot().loading and not feed:snapshot().retry,
  'idle feed can load'
)

-- Start all peers, publish fast results immediately, retain page order and
-- snapshots, and never reorder existing wrappers when a slow peer completes.
local updates, finished = {}, {}
local cancel = feed:load(function(snapshot)
  updates[#updates + 1] = snapshot
end, function(snapshot)
  finished[#finished + 1] = snapshot
end)
eq({ #a.calls, #b.calls }, { 1, 1 }, 'requests start without waiting for peers')
eq(statuses(feed), { 'loading', 'loading', 'unsupported' }, 'active coverage')
local b1, b2 = work(b, '1'), work(b, '2')
local cursor_b = { opaque = { 'page two' } }
b.calls[1].callback(
  nil,
  { entries = { b2, b1 }, next = cursor_b, title = 'B catalog', count = 999 }
)
local progressive = feed:snapshot()
assert(
  progressive.loading and progressive.more and #finished == 0,
  'fast results do not finish slow peers'
)
eq(
  { progressive.entries[1].entry, progressive.entries[2].entry },
  { b2, b1 },
  'provider page order'
)
local wrapper = progressive.entries[1]
assert(wrapper.provider == b and wrapper.entry == b2, 'original module and entry identity')
eq(progressive.sources[2].title, 'B catalog', 'source title is retained')
assert(progressive.count == nil, 'incompatible counts are not aggregated')
local a1 = work(a, '1')
a.calls[1].callback(nil, { entries = { a1 } })
assert(#finished == 1 and not finished[1].loading, 'batch settles once after every peer')
assert(
  feed:snapshot().entries[1] == wrapper and #feed:snapshot().entries == 3,
  'slow peer appends without reordering'
)
assert(
  #progressive.entries == 2 and progressive.sources[1].status == 'loading',
  'snapshot isolation'
)
assert(updates[1].loading and #updates[1].entries == 0, 'initial progress is retained')
a.calls[1].callback('late duplicate')
b.calls[1].callback(nil, { entries = { work(b, 'late') } })
eq(#feed:snapshot().entries, 3, 'duplicate callbacks cannot deliver twice')
cancel()
eq({ a.calls[1].cancelled, b.calls[1].cancelled }, { 0, 0 }, 'finished cancel is inert')

-- Exact identities alone deduplicate; title equality, group IDs, source IDs,
-- and punctuation in IDs must not cause accidental merging.
feed:load(nil, function()
  finished[#finished + 1] = true
end)
eq({ #a.calls, #b.calls }, { 1, 2 }, 'only ready continuations load')
assert(b.calls[2].cursor == cursor_b, 'continuations stay opaque and source-local')
local group = { kind = 'group', id = '1', label = 'Same title', query = { exact = true } }
b.calls[2].callback(
  nil,
  { entries = { work(b, '2', 'Changed metadata'), group, group, work(b, '3') } }
)
local entries = feed:snapshot().entries
assert(
  #entries == 5 and entries[1] == wrapper and entries[1].entry.title == 'Same title',
  'duplicates preserve original wrappers and metadata'
)
assert(
  entries[4].entry == group and not feed:snapshot().more,
  'group identity differs from work identity'
)

local separator_a, separator_b = fake('a/b', { 'explore' }), fake('a', { 'explore' })
local exact = discovery.new({ separator_a, separator_b }, { category = 'explore' })
exact:load()
separator_a.calls[1].callback(nil, { entries = { work(separator_a, 'c') } })
separator_b.calls[1].callback(nil, { entries = { work(separator_b, 'b/c') } })
eq(#exact:snapshot().entries, 2, 'identity separators cannot collide')

-- Search calls only searchable providers; empty continuations consume one
-- request per action rather than automatically fetching until nonempty.
local search = discovery.new({ a, b, unsupported }, { search = '  exact words  ' })
eq(statuses(search), { 'idle', 'unsupported', 'unsupported' }, 'search coverage')
search:load()
assert(
  a.calls[2].search == '  exact words  ' and a.calls[2].cursor == nil,
  'search text is passed unchanged'
)
local empty_cursor = false -- Opaque does not imply a truthy table or URL.
a.calls[2].callback(nil, { entries = {}, next = empty_cursor, empty = 'No eligible works' })
assert(
  search:snapshot().more and not search:snapshot().retry and #a.calls == 2,
  'empty page does not fetch automatically'
)
eq(search:snapshot().sources[1].empty, 'No eligible works', 'honest empty context')
search:load()
assert(a.calls[3].cursor == empty_cursor, 'false continuation remains opaque')
a.calls[3].callback(nil, { entries = {} })
local no_op = 0
search:load(nil, function(snapshot)
  no_op = no_op + 1
  assert(not snapshot.more and not snapshot.loading, 'exhausted feed is settled')
end)
assert(no_op == 1 and #a.calls == 3, 'exhausted actions still finish once')

-- Failures preserve successful peers and the failed cursor. Load skips errors;
-- retry never advances a healthy source, including an empty successful source.
a, b = fake('a', { 'explore' }), fake('b', { 'explore' })
feed = discovery.new({ a, b }, { category = 'explore' })
feed:load()
local cursor_a = { 'private a cursor' }
a.calls[1].callback(nil, { entries = { work(a, '1') }, next = cursor_a })
b.calls[1].callback('offline')
assert(
  feed:snapshot().retry and feed:snapshot().more and #feed:snapshot().entries == 1,
  'partial success retains retry and continuation'
)
eq(feed:snapshot().sources[2].error, 'offline', 'per-source failure')
feed:load()
assert(
  #a.calls == 2 and #b.calls == 1 and a.calls[2].cursor == cursor_a,
  'load skips failed sources'
)
a.calls[2].callback('next page failed')
feed:retry()
assert(
  #a.calls == 3 and #b.calls == 2 and a.calls[3].cursor == cursor_a,
  'retry preserves failed cursor'
)
a.calls[3].callback(nil, { entries = { work(a, '2') } })
b.calls[2].callback('still offline')
feed:retry()
assert(#a.calls == 3 and #b.calls == 3, 'retry selects only remaining failures')
b.calls[3].callback(nil, { entries = {} })
assert(
  not feed:snapshot().more and not feed:snapshot().retry and #feed:snapshot().entries == 2,
  'successful retries clear errors'
)

-- Cancellation invalidates every pending callback before invoking provider
-- cancellation, tolerates a throwing cancel, and resumes unchanged cursors.
a, b = fake('a', { 'explore' }), fake('b', { 'explore' })
feed = discovery.new({ a, b }, { category = 'explore' })
local delivered, done = 0, 0
cancel = feed:load(function()
  delivered = delivered + 1
end, function()
  done = done + 1
end)
a.calls[1].callback(nil, { entries = { work(a, '1') }, next = cursor_a })
local before_cancel = delivered
b.calls[1].on_cancel = function()
  b.calls[1].callback(nil, { entries = { work(b, 'stale') } })
  error('cancel failed')
end
cancel()
cancel()
b.calls[1].callback('late failure')
eq(
  { delivered, done, b.calls[1].cancelled },
  { before_cancel, 0, 1 },
  'cancel is silent and idempotent'
)
eq(statuses(feed), { 'ready', 'idle' }, 'pending sources become resumable')
assert(
  not feed:snapshot().loading and feed:snapshot().more and #feed:snapshot().entries == 1,
  'cancel retains successful rows and resumability'
)
feed:load()
assert(
  a.calls[2].cursor == cursor_a and b.calls[2].cursor == nil,
  'resume keeps independent cursors'
)
a.calls[2].callback(nil, { entries = {}, next = cursor_a })
b.calls[2].callback(nil, { entries = {} })
cancel = feed:load()
assert(a.calls[3].cursor == cursor_a, 'empty response retains its advertised continuation')
cancel()
feed:load()
assert(a.calls[4].cursor == cursor_a, 'cancelled continuation resumes the same token')
a.calls[3].callback(nil, { entries = { work(a, 'old next page') } })
a.calls[4].callback(nil, { entries = { work(a, '2') } })
assert(#feed:snapshot().entries == 2, 'late cancelled pages never append')

-- Replacing an active action suppresses its observers and makes the pending
-- sources eligible again. Old cancellation handles cannot cancel a newer batch.
a, b = fake('a', { 'explore' }), fake('b', { 'explore' })
feed = discovery.new({ a, b }, { category = 'explore' })
done = 0
cancel = feed:load(nil, function()
  done = done + 1
end)
local replacement_done = 0
feed:load(nil, function()
  replacement_done = replacement_done + 1
end)
cancel()
eq(
  { a.calls[1].cancelled, b.calls[1].cancelled },
  { 1, 1 },
  'replacement cancels both pending peers'
)
a.calls[1].callback(nil, { entries = { work(a, 'stale') } })
a.calls[2].callback(nil, { entries = { work(a, 'current') } })
b.calls[2].callback(nil, { entries = {} })
eq({ done, replacement_done, #feed:snapshot().entries }, { 0, 1, 1 }, 'only replacement delivers')

-- A synchronous update may navigate away before later providers start. Every
-- source must still leave loading, and no old completion may reach observers.
local immediate = { id = 'immediate', name = 'Immediate', browse = {} }
immediate.browse.explore = function(_, callback)
  callback(nil, { entries = { work(immediate, '1') } })
  return function() end
end
local unstarted = fake('unstarted', { 'explore' })
feed = discovery.new({ immediate, unstarted }, { category = 'explore' })
done = 0
feed:load(function(snapshot)
  if #snapshot.entries > 0 then
    -- retry has no eligible failures; replacing the active batch cancels its
    -- pending sources but does not load them in the new action.
    feed:retry()
  end
end, function()
  done = done + 1
end)
eq(statuses(feed), { 'ready', 'idle' }, 'reentrant cancellation restores unstarted peers')
assert(
  done == 0 and #unstarted.calls == 0,
  'navigation during synchronous delivery suppresses remaining work'
)

-- Synchronous callbacks, callback-then-throw and startup throws settle once
-- without obscuring healthy peers. The coordinator itself has no vim/UI use.
local sync = { id = 'sync', name = 'Sync', browse = {} }
sync.browse.explore = function(_, callback)
  callback(nil, { entries = { work(sync, '1') } })
  callback('duplicate')
  error('throw after delivery')
end
local throws = { id = 'throws', name = 'Throws', browse = {} }
throws.browse.explore = function()
  error('startup failure')
end
local slow = fake('slow', { 'explore' })
local chunk = assert(loadfile('lua/lilt/online/discovery.lua'), 'load isolated coordinator')
local pure = setfenv(chunk, {
  assert = assert,
  ipairs = ipairs,
  type = type,
  setmetatable = setmetatable,
  pcall = pcall,
  tostring = tostring,
})()
feed = pure.new({ sync, throws, slow }, { category = 'explore' })
done = 0
feed:load(nil, function()
  done = done + 1
end)
local pure_snapshot = feed:snapshot()
eq(statuses(feed), { 'ready', 'error', 'loading' }, 'synchronous startup isolation')
assert(#pure_snapshot.entries == 1 and done == 0, 'synchronous success is usable while peer loads')
assert(
  feed:snapshot().sources[2].error:find('startup failure', 1, true),
  'startup throws become source errors'
)
slow.calls[1].callback(nil, { entries = { work(slow, '1') } })
assert(done == 1 and #feed:snapshot().entries == 2, 'healthy peers survive startup failures')

local empty = discovery.new({}, { category = 'explore' })
done = 0
empty:load(nil, function(snapshot)
  done = done + 1
  assert(
    not snapshot.loading and not snapshot.more and not snapshot.retry,
    'empty registry has no operations'
  )
end)
assert(done == 1, 'empty registry settles')

print('Lilt discovery: capabilities, progressive feeds, identity, retries and cancellation passed')
vim.cmd('qa!')
