-- Rex control-API client for the window-picker `rex` source.
--
-- Rex exposes its state over the CLI (`rex api call <method>`), which talks to
-- the Rex server on a unix socket. One call costs roughly 25-40ms, so every
-- request here is cached and the expensive per-block ones (terminal process
-- info) are refreshed asynchronously, off the key path.

local M = {}

local uv = vim.uv or vim.loop

---cache lifetimes in milliseconds
M.view_ttl = 1000
M.process_ttl = 3000

---how stale a cached view may be before `refresh()` bothers the server again
M.prefetch_age = 400

---@return string
function M.bin()
	local bin = vim.env.REX_BIN
	if bin ~= nil and bin ~= '' then
		return bin
	end

	local dir = vim.env.REX_BIN_DIR
	if dir ~= nil and dir ~= '' then
		return dir .. '/rex'
	end

	return 'rex'
end

---@return string|nil
function M.session_id()
	local id = vim.env.REX_SESSION
	return (id ~= nil and id ~= '') and id or nil
end

---the block this nvim runs in
---@return string|nil
function M.block_id()
	local id = vim.env.REX_BLOCK
	return (id ~= nil and id ~= '') and id or nil
end

---@return boolean
function M.available()
	return M.session_id() ~= nil
		and M.block_id() ~= nil
		and vim.fn.executable(M.bin()) == 1
end

---@return number milliseconds, monotonic
local function now()
	return uv.hrtime() / 1e6
end

---@param method string
---@param args table|nil
---@return string[]|nil argv
---@return string|nil error
local function argv(method, args)
	local sid = M.session_id()
	if sid == nil then
		return nil, 'REX_SESSION is not set'
	end

	local a = { M.bin(), 'api', 'call', '-s', sid, method }
	if args ~= nil then
		local ok, encoded = pcall(vim.json.encode, args)
		if not ok then
			return nil, 'could not encode arguments'
		end
		a[#a + 1] = encoded
	end

	return a
end

---@param res vim.SystemCompleted
---@return table|nil result
---@return string|nil error
local function decode(res)
	if res.code ~= 0 then
		local stderr = res.stderr and vim.trim(res.stderr) or ''
		if stderr ~= '' then
			return nil, stderr
		end
		return nil, 'rex exited with code ' .. tostring(res.code)
	end

	if res.stdout == nil or res.stdout == '' then
		return {}
	end

	local ok, decoded = pcall(vim.json.decode, res.stdout)
	if not ok then
		return nil, 'invalid rex reply'
	end

	return decoded
end

---call a server method and wait for its reply.
---@param method string
---@param args table|nil
---@param timeout integer|nil milliseconds
---@return table|nil result
---@return string|nil error
function M.call(method, args, timeout)
	local a, err = argv(method, args)
	if a == nil then
		return nil, err
	end

	local ok, res = pcall(function()
		return vim.system(a, { text = true, timeout = timeout or 800 }):wait()
	end)
	if not ok or res == nil then
		return nil, 'rex call failed: ' .. tostring(res)
	end

	return decode(res)
end

---call a server method without blocking. `cb` runs in the main loop.
---@param method string
---@param args table|nil
---@param cb fun(result: table|nil, err: string|nil)
function M.call_async(method, args, cb)
	local a, err = argv(method, args)
	if a == nil then
		vim.schedule(function()
			cb(nil, err)
		end)
		return
	end

	local function on_exit(res)
		vim.schedule(function()
			cb(decode(res))
		end)
	end

	local ok = pcall(vim.system, a, { text = true, timeout = 2000 }, on_exit)
	if not ok then
		vim.schedule(function()
			cb(nil, 'could not spawn ' .. M.bin())
		end)
	end
end

---@type { at: number, view: table }|nil
local view_cache = nil
local view_pending = false
---@type table<string, { at: number, info: table }>
local process_cache = {}

---cached snapshot, no server round trip. may be nil or stale.
---@return table|nil
function M.cached_view()
	return view_cache and view_cache.view or nil
end

---snapshot of the session (windows, layouts, blocks), from cache when fresh.
---@param ttl integer|nil milliseconds; defaults to `M.view_ttl`
---@return table|nil view
---@return string|nil error
function M.view(ttl)
	if view_cache and now() - view_cache.at < (ttl or M.view_ttl) then
		return view_cache.view
	end

	local view, err = M.call('session.view', { session_id = M.session_id() })
	if view == nil then
		return nil, err
	end

	view_cache = { at = now(), view = view }
	return view
end

---every block of a view, paired with the window it lives in.
---@param view table
---@return table[] entries { block = table, window = table, index = integer }
function M.blocks(view)
	local entries = {}

	for index, window in ipairs(view.windows or {}) do
		local seen = {}
		for _, layer in ipairs(window.layers or {}) do
			for _, block in ipairs(layer.blocks or {}) do
				if block.block_id and not seen[block.block_id] then
					seen[block.block_id] = true
					entries[#entries + 1] = {
						block = block,
						window = window,
						index = index,
					}
				end
			end
		end
	end

	return entries
end

---the window holding a block
---@param view table
---@param block_id string
---@return table|nil window
---@return integer|nil index
function M.window_of(view, block_id)
	for index, window in ipairs(view.windows or {}) do
		if window.focused_block_id == block_id then
			return window, index
		end
		for _, layer in ipairs(window.layers or {}) do
			for _, block in ipairs(layer.blocks or {}) do
				if block.block_id == block_id then
					return window, index
				end
			end
		end
	end

	return nil
end

---cached terminal info (foreground program, cwd) for a block.
---@param block_id string
---@return table|nil
function M.cached_process(block_id)
	local entry = process_cache[block_id]
	return entry and entry.info or nil
end

---@param block_id string
---@param cb fun(info: table|nil)
local function fetch_process(block_id, cb)
	M.call_async('block.method', {
		session_id = M.session_id(),
		block_id = block_id,
		method = 'process',
	}, function(result)
		if result == nil then
			cb(nil)
			return
		end
		process_cache[block_id] = { at = now(), info = result }
		cb(result)
	end)
end

local refresh_seq = 0

---warm the caches in the background: a stale session snapshot plus the
---terminal info of every block in it. cheap to call repeatedly.
---@param opts table|nil { min_age = number }
function M.refresh(opts)
	if not M.available() then
		return
	end

	local min_age = (opts or {}).min_age or M.prefetch_age
	if view_cache and now() - view_cache.at < min_age then
		return
	end
	if view_pending then
		return
	end

	refresh_seq = refresh_seq + 1
	local seq = refresh_seq
	view_pending = true

	local function on_view(view, err)
		view_pending = false
		if view == nil then
			if err then
				vim.notify(
					'window-picker: rex session.view failed: ' .. err,
					vim.log.levels.WARN
				)
			end
			return
		end

		view_cache = { at = now(), view = view }

		-- the picker usually opens right after; only the newest refresh is useful
		if seq ~= refresh_seq then
			return
		end

		for _, entry in ipairs(M.blocks(view)) do
			local id = entry.block.block_id
			local cached = process_cache[id]
			if cached == nil or now() - cached.at > M.process_ttl then
				fetch_process(id, function() end)
			end
		end
	end

	M.call_async('session.view', { session_id = M.session_id() }, on_view)
end

---focus a block, switching to its window when needed.
---@param block_id string
---@return boolean focused
---@return string|nil error
function M.focus_block(block_id)
	local result, err = M.call('session.focus_block', {
		session_id = M.session_id(),
		block_id = block_id,
	})
	if result == nil then
		return false, err
	end

	return true
end

---test seam: drop every cached value
function M.reset()
	view_cache = nil
	process_cache = {}
end

return M
