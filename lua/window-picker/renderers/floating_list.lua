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

---@param position string
---@param width number
---@param height number
---@param offset_x number
---@param offset_y number
---@return number row
---@return number col
local function position_window(position, width, height, offset_x, offset_y)
	local editor_height = vim.o.lines - vim.o.cmdheight

	local row
	if position:match('^top') then
		row = offset_y
	elseif position:match('^bottom') then
		row = editor_height - height - offset_y
	else
		row = math.floor((editor_height - height) / 2) + offset_y
	end

	local col
	if position:match('left$') then
		col = offset_x
	elseif position == 'center' then
		col = math.floor((vim.o.columns - width) / 2) + offset_x
	else
		col = vim.o.columns - width - offset_x
	end

	return math.max(row, 0), math.max(col, 0)
end

---build one line per entry: `<info> <label>`, info left aligned, label right
---aligned. also returns the byte columns of every label so they can be
---highlighted without re-deriving them.
---@param entries table[]
---@param padding number
---@return string[] lines
---@return table[] labels { row = number, start_col = number, end_col = number }
local function build_lines(entries, padding)
	local infos, info_width = {}, 0

	for i, entry in ipairs(entries) do
		local target = entry.target
		local info = target.title or target.id
		if
			target.detail
			and target.detail ~= ''
			and target.detail ~= target.title
		then
			info = info .. '  ' .. target.detail
		end
		infos[i] = info
		info_width = math.max(info_width, vim.fn.strdisplaywidth(info))
	end

	local lines, labels = {}, {}
	local side = (' '):rep(padding)

	for i, entry in ipairs(entries) do
		local info = infos[i]
		local gap = info_width - vim.fn.strdisplaywidth(info)
		local line = side .. info .. (' '):rep(gap + padding)

		local start_col = #line
		line = line .. entry.char .. side
		lines[i] = line
		labels[i] = {
			row = i - 1,
			start_col = start_col,
			end_col = start_col + #entry.char,
		}
	end

	return lines, labels
end

---@param entries table[]
function M:draw(entries)
	local ui = self.config.picker_config.floating_list

	local lines, labels = build_lines(entries, ui.label_padding)

	local width = 1
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end

	local max_height = math.max(vim.o.lines - vim.o.cmdheight - 1, 1)
	local height = math.max(math.min(#lines, max_height), 1)
	local row, col =
		position_window(ui.position, width, height, ui.offset_x, ui.offset_y)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	local label_hl = ui.label_hl
	for _, label in ipairs(labels) do
		vim.api.nvim_buf_add_highlight(
			buf,
			ns,
			label_hl,
			label.row,
			label.start_col,
			label.end_col
		)
	end

	local win = vim.api.nvim_open_win(buf, false, {
		relative = 'editor',
		row = row,
		col = col,
		width = width,
		height = height,
		style = 'minimal',
		border = ui.border,
		focusable = false,
		noautocmd = true,
		zindex = 250,
	})

	vim.wo[win].winhighlight = 'Normal:' .. ui.window_bg

	self.win = win
	self.buf = buf

	-- floating windows are not flushed to the terminal on their own; without
	-- this redraw the list can stay invisible until the next screen update
	-- (it then only flashes when a key is pressed). the hint renderers redraw
	-- too, but they are not used for non-nvim targets.
	vim.cmd.redraw()
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
