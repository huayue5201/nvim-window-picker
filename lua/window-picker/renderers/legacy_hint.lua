local M = {}

M.name = 'legacy_hint'

---adapter for a user supplied hint object passed through `config.hint`. keeps
---the historical custom-hint contract: an object with `set_config`, `draw`
---and `clear`.
---@param config table
---@param hint table
function M.new(config, hint)
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
			if self.hint.clear then
				self.hint:clear()
			end
		end,
	}
end

return M
