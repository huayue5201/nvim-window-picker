local client = require('window-picker.rex.client')

local M = {}

M.name = 'rex'

---@param opts table|nil { scope = 'window'|'session', respect_zoom = boolean }
---@param config table
function M:new(opts, config)
	local o = setmetatable({
		opts = opts or {},
		config = config,
	}, { __index = self })

	o.scope = o.opts.scope or 'window'
	-- respect_zoom only makes sense with scope = 'window': a zoomed window
	-- hides every other block of that window, which is exactly the candidate
	-- set of the window scope.
	o.respect_zoom = o.opts.respect_zoom ~= false and o.scope == 'window'

	return o
end

---the rex source is only usable when nvim itself runs inside a rex block
---@return boolean
function M.available()
	return client.available()
end

---keep the snapshot and the per-block terminal info warm so a pick does not
---pay for the CLI round trips.
---@param opts table|nil { scope = string, cache_ttl = number }
function M.prefetch(opts) -- luacheck: ignore 212
	client.refresh({ min_age = client.prefetch_age })

	if M._armed or not vim.api or not vim.api.nvim_create_autocmd then
		return
	end
	M._armed = true

	local group =
		vim.api.nvim_create_augroup('WindowPickerRex', { clear = true })

	-- CursorHold(I) fires once per idle pause, which is exactly the moment
	-- before a key sequence like <leader>ww gets typed.
	vim.api.nvim_create_autocmd(
		{ 'CursorHold', 'CursorHoldI', 'WinNew', 'TabEnter', 'FocusGained' },
		{
			group = group,
			callback = function()
				client.refresh({ min_age = client.prefetch_age })
			end,
		}
	)
end

---the foreground program of a block, or nil when the cache is cold
---@param block_id string
---@return table|nil
function M._process(block_id)
	return client.cached_process(block_id)
end

---@param block table
---@param process table|nil
---@return string
function M._title(block, process)
	local foreground = process and process.foreground or nil
	if foreground and foreground.name and foreground.name ~= '' then
		return foreground.name
	end

	if block.label and block.label ~= '' then
		return block.label
	end

	return block.block_id
end

---@param process table|nil
---@return string|nil
function M._detail(process)
	local cwd = process and process.foreground and process.foreground.cwd or nil
	if cwd == nil or cwd == '' then
		return nil
	end

	return vim.fn.fnamemodify(cwd, ':~:.')
end

---stop the picker entirely when nvim's own block is hidden behind another
---block's zoom: there is nothing visible left to switch between.
---@param _context table|nil
---@return boolean
function M:abort(_context)
	if not self.respect_zoom then
		return false
	end

	local own = client.block_id()
	local view = client.cached_view() or client.view()
	if view == nil or own == nil then
		return false
	end

	local window = client.window_of(view, own)
	if window == nil or window.zoomed_block_id == nil then
		return false
	end

	return window.zoomed_block_id ~= own
end

---@return table[]
function M:list()
	M.prefetch(self.opts)

	local view, err = client.view()
	if view == nil then
		if err then
			vim.notify(
				'window-picker: rex session.view failed: ' .. err,
				vim.log.levels.WARN
			)
		end
		return {}
	end

	local own = client.block_id()
	local own_window = nil
	if own then
		own_window = client.window_of(view, own)
	end

	local entries = client.blocks(view)

	-- zoom hides every other block of the window; when respect_zoom is on we
	-- only list what is actually on screen.
	if self.respect_zoom and own_window and own_window.zoomed_block_id then
		local visible = {}
		for _, entry in ipairs(entries) do
			if
				entry.window ~= own_window
				or entry.block.block_id == own_window.zoomed_block_id
			then
				visible[#visible + 1] = entry
			end
		end
		entries = visible
	end

	local candidates = {}
	for _, entry in ipairs(entries) do
		local id = entry.block.block_id
		local in_scope = self.scope == 'session'
			or own_window == nil
			or entry.window == own_window
		if id ~= own and in_scope then
			candidates[#candidates + 1] = entry
		end
	end

	-- nearest first: other blocks of the current window, then the rest
	local function rank(entry)
		if own_window ~= nil and entry.window == own_window then
			return 1
		end
		return 2
	end

	table.sort(candidates, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		if a.index ~= b.index then
			return a.index < b.index
		end
		return a.block.block_id < b.block.block_id
	end)

	local targets = {}
	for _, entry in ipairs(candidates) do
		local block_id = entry.block.block_id
		local process = M._process(block_id)
		local detail = M._detail(process)

		-- make it obvious when a target sits in another rex window
		if
			self.scope == 'session'
			and own_window ~= nil
			and entry.window ~= own_window
		then
			local label = entry.window.label or ('window ' .. entry.index)
			detail = detail and (detail .. '  ·  ' .. label) or label
		end

		targets[#targets + 1] = {
			id = 'rex:' .. block_id,
			kind = 'rex',
			title = M._title(entry.block, process),
			detail = detail,
			meta = {
				block = entry.block,
				window = entry.window,
				index = entry.index,
			},
			focus = function(target)
				return client.focus_block(target.meta.block.block_id)
			end,
		}
	end

	return targets
end

return M
