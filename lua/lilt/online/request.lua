local limit = 12 * 1024 * 1024

local function clean(value)
  return type(value) == 'string' and vim.trim(value:gsub('%c', ' ')) or ''
end

-- One bounded request, with an owned temporary file. All completions run on the
-- main loop; cancellation suppresses delivery even if the process already exited.
local function request(url, callback)
  local path, process, cancelled = vim.fn.tempname(), nil, false
  local function cleanup()
    vim.fn.delete(path)
  end
  local cancel = function()
    cancelled = true
    if process then
      process:kill(15)
    end
    cleanup()
  end
  local ok, err = pcall(function()
    if vim.fn.executable('curl') ~= 1 then
      error('Lilt: online discovery requires curl on PATH', 0)
    end
    process = vim.system({
      'curl',
      '--disable',
      '--fail',
      '--silent',
      '--show-error',
      '--location',
      '--proto',
      '=https',
      '--proto-redir',
      '=https',
      '--max-redirs',
      '3',
      '--connect-timeout',
      '10',
      '--max-time',
      '45',
      '--max-filesize',
      tostring(limit),
      '--user-agent',
      'lilt.nvim (https://github.com/XinqiBao/lilt.nvim)',
      '--output',
      path,
      '--url',
      url,
    }, {}, function(result)
      vim.schedule(function()
        if cancelled then
          cleanup()
          return
        end
        if result.code ~= 0 then
          cleanup()
          callback('Lilt: online request failed: ' .. clean(result.stderr), nil)
          return
        end
        local stat = vim.uv.fs_stat(path)
        if not stat or stat.size > limit then
          cleanup()
          callback('Lilt: online response is missing or exceeds 12 MiB', nil)
          return
        end
        -- The consumer must read the file before returning.
        local delivered, delivery_error = pcall(callback, nil, path)
        cleanup()
        if not delivered then
          vim.notify(tostring(delivery_error), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
  if not ok then
    cleanup()
    vim.schedule(function()
      if not cancelled then
        callback(tostring(err), nil)
      end
    end)
  end
  return cancel
end

return request
