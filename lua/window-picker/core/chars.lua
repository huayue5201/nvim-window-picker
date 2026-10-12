local M = {}

---assign a selection char to every target. targets are ordered, chars come
---from `config.chars` (a list of single char strings)
---@param targets table[]
---@param char_list string[]
---@return table[] entries {target=, char=, index=}
function M.assign(targets, char_list)
	local entries = {}

	for i, target in ipairs(targets) do
		local char = char_list[i] or tostring(i)
		entries[i] = { target = target, char = char, index = i }
	end

	return entries
end

---case insensitive lookup of an entry by its char
---@param entries table[]
---@param char string
---@return table|nil
function M.find(entries, char)
	if not char then
		return nil
	end

	local needle = char:lower()

	for _, entry in ipairs(entries) do
		if entry.char:lower() == needle then
			return entry
		end
	end

	return nil
end

return M
