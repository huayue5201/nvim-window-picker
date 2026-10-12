local M = {}

M.name = 'floating_list'

local ns = vim.api.nvim_create_namespace('window-picker-floating-list')

---@param config table
function M.new(config)
	return setmetatable({
		config = config,
		win = nil,
		buf = nil,
	}, { __index = M })
end

---fallback renderer: accepts anything the nvim hint renderers cannot draw, so
---it must never reject a target
---@param _ table
---@return boolean
function M.supports()
	return true
end

---@param entries table[]
function M:draw(entries)
	local lines = {}

	for _, entry in ipairs(entries) do
		local target = entry.target
		local line = ('%s  %s'):format(entry.char, target.title or target.id)
		if
			target.detail
			and target.detail ~= ''
			and target.detail ~= target.title
		then
			line = line .. '  ' .. target.detail
		end
		lines[#lines + 1] = line
	end

	local width = 24
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end
	width = math.min(width + 2, math.max(vim.o.columns - 4, 10))
	local height = math.max(math.min(#lines, vim.o.lines - 4), 1)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	for i in ipairs(lines) do
		local char_len = #entries[i].char
		vim.api.nvim_buf_add_highlight(buf, ns, 'Title', i - 1, 0, char_len)
	end

	local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
	local col = math.max(0, math.floor((vim.o.columns - width) / 2))

	local win = vim.api.nvim_open_win(buf, false, {
		relative = 'editor',
		row = row,
		col = col,
		width = width,
		height = height,
		style = 'minimal',
		border = 'rounded',
		title = ' Pick ',
		title_pos = 'center',
		focusable = false,
		noautocmd = true,
		zindex = 250,
	})

	self.win = win
	self.buf = buf
end

function M:clear()
	if self.win and vim.api.nvim_win_is_valid(self.win) then
		vim.api.nvim_win_close(self.win, true)
	end

	if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
		vim.api.nvim_buf_delete(self.buf, { force = true })
	end

	self.win = nil
	self.buf = nil
end

return M
