local client = require('window-picker.ghostty.client')

local uv = vim.uv or vim.loop

local M = {}

M.name = 'ghostty'

---@param opts table|nil { scope = 'window'|'tab'|'all', cache_ttl = number }
---@param config table
function M:new(opts, config)
	local o = setmetatable({
		opts = opts or {},
		config = config,
	}, { __index = self })

	o.scope = o.opts.scope or 'all'

	return o
end

---snapshot options handed to the ghostty client
function M:_read_opts()
	return {
		scope = self.scope,
		ttl = self.opts and self.opts.cache_ttl or nil,
	}
end

local armed = false

---keep the client's snapshot cache warm so the next pick does not pay for the
---apple-script round trip. cheap to call repeatedly: refreshes are debounced
---and coalesced inside the client.
---@param opts table|nil { scope = 'tab'|'window'|'all', cache_ttl = number }
function M.prefetch(opts)
	opts = opts or {}
	local read_opts = { scope = opts.scope or 'all', ttl = opts.cache_ttl }
	local prefetch_opts = {
		scope = read_opts.scope,
		min_age = client.prefetch_age,
	}

	client.refresh(prefetch_opts)

	if armed or not vim.api or not vim.api.nvim_create_autocmd then
		return
	end
	armed = true

	local group = vim.api.nvim_create_augroup('WindowPickerGhostty', {
		clear = true,
	})

	-- CursorHold(I) fires once per idle pause, which is exactly the moment
	-- before a key sequence like <leader>ww gets typed.
	vim.api.nvim_create_autocmd(
		{ 'CursorHold', 'CursorHoldI', 'WinNew', 'TabEnter', 'FocusGained' },
		{
			group = group,
			callback = function()
				client.refresh(prefetch_opts)
			end,
		}
	)
end

---the ghostty source is only usable when ghostty is scriptable, which is
---macOS only (the GTK build ships no scripting dictionary)
---@return boolean
function M.available()
	return client.available()
end

---@param dir string|nil
---@return string|nil
local function normalize_dir(dir)
	if not dir or dir == '' then
		return nil
	end

	local real = uv.fs_realpath(dir)
	return real or dir
end

---titles nvim itself may currently set on the terminal title. used only as a
---tiebreaker between surfaces that share the cwd.
---@return string[]
local function own_titles()
	local titles = {}

	if vim.o.titlestring ~= '' then
		local ok, expanded = pcall(vim.fn.expand, vim.o.titlestring)
		if ok and type(expanded) == 'string' and expanded ~= '' then
			titles[#titles + 1] = expanded
		end
	end

	titles[#titles + 1] = 'nvim'

	return titles
end

---best effort detection of the terminal surface nvim runs in.
---
---ghostty does not export a surface id to the processes it runs, so:
---1. when ghostty is frontmost, the focused terminal of the selected tab of the
---   front window is the surface the keystroke came from, i.e. nvim's terminal;
---2. otherwise match on the process cwd, breaking ties with the terminal title;
---3. when that is still ambiguous nil is returned.
---@param terminals table[]
---@return table|nil
function M._current(terminals, opts)
	local front = client.current_surface(opts)
	if front then
		for _, terminal in ipairs(terminals) do
			if terminal.terminal_id == front.terminal_id then
				return terminal
			end
		end
	end

	local cwd = normalize_dir(uv.cwd())
	if not cwd then
		return nil
	end

	local matches = {}
	for _, terminal in ipairs(terminals) do
		if normalize_dir(terminal.cwd) == cwd then
			matches[#matches + 1] = terminal
		end
	end

	if #matches == 1 then
		return matches[1]
	end

	if #matches == 0 then
		return nil
	end

	local titles = own_titles()
	local by_title = {}
	for _, terminal in ipairs(matches) do
		for _, title in ipairs(titles) do
			if terminal.title == title then
				by_title[#by_title + 1] = terminal
				break
			end
		end
	end

	if #by_title == 1 then
		return by_title[1]
	end

	return nil
end

---@param terminal table
---@param current table|nil
---@return boolean
function M:_in_scope(terminal, current)
	if self.scope == 'all' then
		return true
	end

	-- a narrower scope must not leak other tabs/windows in, so an unknown
	-- current surface means nothing is in scope
	if not current then
		return false
	end

	if self.scope == 'tab' then
		return terminal.tab_id == current.tab_id
	end

	return terminal.window_id == current.window_id
end

---@param terminal table
---@return string
function M._title(terminal)
	if terminal.title and terminal.title ~= '' then
		return terminal.title
	end

	if terminal.tab_title and terminal.tab_title ~= '' then
		return terminal.tab_title
	end

	if terminal.window_name and terminal.window_name ~= '' then
		return terminal.window_name
	end

	local base = vim.fn.fnamemodify(terminal.cwd or '', ':t')
	if base ~= '' then
		return base
	end

	return terminal.terminal_id
end

---@param terminal table
---@return string|nil
function M._detail(terminal)
	if not terminal.cwd or terminal.cwd == '' then
		return nil
	end

	return vim.fn.fnamemodify(terminal.cwd, ':~:.')
end

---@return table[]
function M:list()
	M.prefetch(self.opts)

	local read_opts = self:_read_opts()
	local terminals, err = client.list_terminals(read_opts)
	if not terminals then
		if err then
			vim.notify(
				'window-picker: ghostty terminal list failed: ' .. err,
				vim.log.levels.WARN
			)
		end
		return {}
	end

	local current = M._current(terminals, read_opts)

	if not current and self.scope ~= 'all' then
		vim.notify(
			'window-picker: ghostty cannot tell which terminal nvim runs in, '
				.. 'scope = "'
				.. self.scope
				.. '" matches nothing',
			vim.log.levels.WARN
		)
		return {}
	end

	-- nearest first: current tab, then current window, then the rest
	local function rank(terminal)
		if current then
			if terminal.tab_id == current.tab_id then
				return 1
			end
			if terminal.window_id == current.window_id then
				return 2
			end
		end
		return 3
	end

	local candidates = {}
	for _, terminal in ipairs(terminals) do
		if
			self:_in_scope(terminal, current)
			and (not current or terminal.terminal_id ~= current.terminal_id)
		then
			candidates[#candidates + 1] = terminal
		end
	end

	table.sort(candidates, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a.terminal_id < b.terminal_id
	end)

	local targets = {}
	for _, terminal in ipairs(candidates) do
		targets[#targets + 1] = {
			id = 'ghostty:' .. terminal.terminal_id,
			kind = 'ghostty',
			title = M._title(terminal),
			detail = M._detail(terminal),
			meta = terminal,
			focus = function(target)
				return client.focus_terminal(target.meta.terminal_id)
			end,
		}
	end

	return targets
end

return M
