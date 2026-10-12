local M = {}

---build a renderer adapter around one of the bundled hint classes in
---`window-picker.hints.*`. the adapter maps generic targets (with
---`target.window`) onto the nvim window based hint interface.
---@param config table plugin config
---@param hint_file string module name under window-picker.hints
---@return table renderer
function M.new(config, hint_file)
	local hint = require('window-picker.hints.' .. hint_file):new()

	if hint.set_config then
		hint:set_config(config)
	end

	return {
		config = config,
		hint = hint,

		---@param target table
		---@return boolean
		supports = function(_, target)
			return target.kind == 'nvim'
		end,

		---@param entries table[]
		draw = function(self, entries)
			local windows, chars = {}, {}
			for i, entry in ipairs(entries) do
				windows[i] = entry.target.window
				chars[i] = entry.char
			end

			self.hint.chars = chars
			self.hint:draw(windows)
		end,

		clear = function(self)
			self.hint:clear()
		end,
	}
end

return M
