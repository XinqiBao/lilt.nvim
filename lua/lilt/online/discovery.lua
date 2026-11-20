local M = {}

local categories = {
  { id = 'explore', label = 'Explore' },
  { id = 'poetry', label = 'Poetry' },
  { id = 'short_stories', label = 'Short stories' },
  { id = 'recent', label = 'Recently listed' },
  { id = 'poets', label = 'Browse poets' },
}

-- Providers are injected; discovering capabilities never starts a request.
function M.categories(providers)
  local rows = {}
  for _, category in ipairs(categories) do
    for _, provider in ipairs(providers) do
      if provider.browse and provider.browse[category.id] then
        rows[#rows + 1] = { id = category.id, label = category.label }
        break
      end
    end
  end
  return rows
end

local Feed = {}
Feed.__index = Feed

-- new(providers, {category=id} | {search=text}) performs no I/O. Unsupported
-- providers remain in sources, so callers can describe discovery coverage.
function M.new(providers, query)
  assert(
    (type(query.category) == 'string' and query.search == nil)
      or (type(query.search) == 'string' and query.category == nil),
    'discovery requires a category or search text'
  )
  local self = setmetatable({ sources = {}, entries = {}, seen = {} }, Feed)
  for _, provider in ipairs(providers) do
    local operation
    if query.search ~= nil and provider.search then
      local search = query.search
      operation = function(cursor, callback)
        return provider.search(search, cursor, callback)
      end
    elseif query.category and provider.browse then
      operation = provider.browse[query.category]
    end
    self.sources[#self.sources + 1] = {
      provider = provider,
      operation = operation,
      status = operation and 'idle' or 'unsupported',
    }
  end
  return self
end

-- Snapshots copy arrays and source records. Wrappers and original provider
-- entries retain identity and are read-only to consumers. No totals are merged.
function Feed:snapshot()
  local snapshot = { entries = {}, sources = {}, loading = false, more = false, retry = false }
  for i, wrapper in ipairs(self.entries) do
    snapshot.entries[i] = wrapper
  end
  for i, source in ipairs(self.sources) do
    snapshot.sources[i] = {
      provider = source.provider,
      status = source.status,
      error = source.error,
      title = source.title,
      empty = source.empty,
    }
    snapshot.loading = snapshot.loading or source.status == 'loading'
    snapshot.more = snapshot.more
      or source.status == 'idle'
      or (source.status == 'ready' and source.cursor ~= nil)
    snapshot.retry = snapshot.retry or source.status == 'error'
  end
  return snapshot
end

local function append(self, provider, entries)
  for _, entry in ipairs(entries) do
    local kind = entry.kind or 'work'
    local identity_provider = kind == 'group' and provider.id or entry.source.provider
    local id = kind == 'group' and entry.id or entry.source.id
    -- Nested keys keep provider/type/identity exact, even when IDs contain
    -- separators. Groups and works may share a provider-local ID.
    local seen_provider = self.seen[identity_provider] or {}
    self.seen[identity_provider] = seen_provider
    local seen_kind = seen_provider[kind] or {}
    seen_provider[kind] = seen_kind
    if not seen_kind[id] then
      seen_kind[id] = true
      self.entries[#self.entries + 1] = { provider = provider, entry = entry }
    end
  end
end

local function run(self, retry, update, done)
  if self.batch then
    self.batch.cancel()
  end
  local batch = { active = true, jobs = {}, remaining = 0 }
  self.batch = batch

  local function cancel()
    if not batch.active then
      return
    end
    batch.active = false
    self.batch = nil
    -- Invalidate every delivery before invoking cancellation, which can itself
    -- synchronously call back or throw. Cursors advance only on success.
    for _, job in ipairs(batch.jobs) do
      if job.pending then
        job.pending, job.cancelled = false, true
        job.source.status = 'idle'
      end
    end
    for _, job in ipairs(batch.jobs) do
      if job.cancelled and job.cancel then
        pcall(job.cancel)
      end
    end
  end
  batch.cancel = cancel

  for _, source in ipairs(self.sources) do
    local eligible = retry and source.status == 'error'
      or (
        not retry
        and (source.status == 'idle' or (source.status == 'ready' and source.cursor ~= nil))
      )
    if eligible then
      batch.jobs[#batch.jobs + 1] = { source = source, pending = true }
      batch.remaining = batch.remaining + 1
      source.status, source.error = 'loading', nil
    end
  end

  local function publish()
    if update then
      update(self:snapshot())
    end
    if batch.active and batch.remaining == 0 then
      batch.active = false
      self.batch = nil
      if done then
        done(self:snapshot())
      end
    end
  end

  publish()
  for _, job in ipairs(batch.jobs) do
    if not batch.active then
      break
    end
    local source = job.source
    local function receive(err, page)
      if not batch.active or not job.pending then
        return
      end
      job.pending = false
      batch.remaining = batch.remaining - 1
      if err then
        source.status, source.error = 'error', err
      else
        append(self, source.provider, page.entries)
        source.status, source.cursor = 'ready', page.next
        source.title, source.empty = page.title, page.empty
      end
      publish()
    end

    -- Defer synchronous delivery until startup returns: observer exceptions
    -- must not be mistaken for provider startup errors. First delivery wins,
    -- including a callback followed by a throw.
    local starting, response = true, nil
    local function callback(err, page)
      if starting then
        response = response or { err = err, page = page }
      else
        receive(err, page)
      end
    end
    local ok, result = pcall(source.operation, source.cursor, callback)
    starting = false
    if ok then
      job.cancel = result
      if job.cancelled and job.cancel then
        pcall(job.cancel)
      end
    end
    if response then
      receive(response.err, response.page)
    elseif not ok then
      receive(tostring(result))
    end
  end
  return cancel
end

-- Each action requests at most one page per eligible source. Updates include
-- initial loading state and each settled response; done runs once even for an
-- empty batch. Completed rows append immediately in page order, without waiting
-- for peers. A new action cancels the previous batch. Cancellation is silent,
-- preserves rows/cursors, and makes pending sources resumable through load.
function Feed:load(update, done)
  return run(self, false, update, done)
end

-- Failed sources are retried at their unchanged cursor; load skips failures.
function Feed:retry(update, done)
  return run(self, true, update, done)
end

return M
