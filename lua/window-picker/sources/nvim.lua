local DefaultWindowFilter =
	require('window-picker.filters.default-window-filter')

local M = {}

M.name = 'nvim'

---@param opts table|nil source specific options (currently unused)
---@param config table plugin config
function M:new(opts, config)
	return setmetatable({
		opts = opts or {},
		config = config,
		filter = nil,
	}, { __index = self })
end

---@return boolean
function M.available()
	return true
end

---@param window number
---@return string
function M._title(window)
	local buf = vim.api.nvim_win_get_buf(window)
	local name = vim.api.nvim_buf_get_name(buf)
	if name == '' then
		return '[No Name]'
	end

	return vim.fn.fnamemodify(name, ':t')
end

---@param window number
---@return string|nil
function M._detail(window)
	local buf = vim.api.nvim_win_get_buf(window)
	local name = vim.api.nvim_buf_get_name(buf)
	if name == '' then
		return nil
	end

	return vim.fn.fnamemodify(name, ':~:.')
end

---@param windows number[]
---@return number[]
function M:_filter(windows)
	if self.config.filter_func then
		return self.config.filter_func(windows, self.config.filter_rules)
	end

	if not self.filter then
		self.filter = DefaultWindowFilter:new()
	end

	self.filter:set_config(self.config.filter_rules)

	return self.filter:filter_windows(windows)
end

---@param context table
---@return table[] targets
function M:list(context)
	local windows = vim.api.nvim_tabpage_list_wins(0)

	if context and context.select_filter then
		windows = context.select_filter(windows)
	else
		windows = self:_filter(windows)
	end

	local targets = {}
	for _, window in ipairs(windows) do
		targets[#targets + 1] = {
			id = 'nvim:' .. window,
			kind = 'nvim',
			window = window,
			title = M._title(window),
			detail = M._detail(window),
		}
	end

	return targets
end

return M
