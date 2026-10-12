local hint = require('window-picker.renderers.hint')

local M = {}

M.name = 'nvim_floating_big_letter'

---@param config table
function M.new(config)
	return hint.new(config, 'floating-big-letter-hint')
end

return M
