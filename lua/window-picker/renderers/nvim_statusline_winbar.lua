local hint = require('window-picker.renderers.hint')

local M = {}

M.name = 'nvim_statusline_winbar'

---@param config table
function M.new(config)
	return hint.new(config, 'statusline-winbar-hint')
end

return M
