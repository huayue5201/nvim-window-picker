local hint = require('window-picker.renderers.hint')

local M = {}

M.name = 'nvim_floating_letter'

---@param config table
function M.new(config)
	return hint.new(config, 'floating-letter-hint')
end

return M
