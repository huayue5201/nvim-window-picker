local client = require('window-picker.herdr.client')

local M = {}

M.name = 'herdr'

---@param opts table|nil { scope = 'workspace'|'tab'|'all' }
---@param config table
function M:new(opts, config)
	local o = setmetatable({
		opts = opts or {},
		config = config,
	}, { __index = self })

	o.scope = o.opts.scope or 'workspace'

	return o
end

---the herdr source is only usable when nvim itself runs inside a herdr pane
---@return boolean
function M.available()
	return vim.env.HERDR_ENV == '1'
end

---@param pane table
---@return string
function M._title(pane)
	if pane.label and pane.label ~= '' then
		return pane.label
	end

	if pane.terminal_title_stripped and pane.terminal_title_stripped ~= '' then
		return pane.terminal_title_stripped
	end

	if pane.terminal_title and pane.terminal_title ~= '' then
		return pane.terminal_title
	end

	if pane.agent and pane.agent ~= '' then
		return pane.agent
	end

	local base = vim.fn.fnamemodify(pane.cwd or '', ':t')
	if base ~= '' then
		return base
	end

	return pane.pane_id
end

---@param pane table
---@return string|nil
function M._detail(pane)
	local cwd = pane.foreground_cwd or pane.cwd
	if not cwd or cwd == '' then
		return nil
	end

	return vim.fn.fnamemodify(cwd, ':~:.')
end

---@param pane table
---@param workspace_id string|nil
---@param tab_id string|nil
---@return boolean
function M:_in_scope(pane, workspace_id, tab_id)
	if self.scope == 'all' then
		return true
	end

	if self.scope == 'tab' then
		return pane.tab_id == tab_id
	end

	return pane.workspace_id == workspace_id
end

---@return table[]
function M:list()
	local panes, err = client.pane_list({})
	if not panes then
		if err then
			vim.notify(
				'window-picker: herdr pane list failed: ' .. err,
				vim.log.levels.WARN
			)
		end
		return {}
	end

	local current_pane = vim.env.HERDR_PANE_ID
	local workspace_id = vim.env.HERDR_WORKSPACE_ID
	local tab_id = vim.env.HERDR_TAB_ID

	local candidates = {}
	for _, pane in ipairs(panes) do
		if
			pane.pane_id ~= current_pane
			and self:_in_scope(pane, workspace_id, tab_id)
		then
			candidates[#candidates + 1] = pane
		end
	end

	-- nearest first: current tab, then current workspace, then the rest
	local function rank(pane)
		if pane.tab_id == tab_id then
			return 1
		end
		if pane.workspace_id == workspace_id then
			return 2
		end
		return 3
	end

	table.sort(candidates, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a.pane_id < b.pane_id
	end)

	local targets = {}
	for _, pane in ipairs(candidates) do
		targets[#targets + 1] = {
			id = 'herdr:' .. pane.pane_id,
			kind = 'herdr',
			title = M._title(pane),
			detail = M._detail(pane),
			meta = pane,
			focus = function(target)
				return client.pane_focus(target.meta.pane_id)
			end,
		}
	end

	return targets
end

return M
