local M = {}

function M.escape_pattern(text)
	return text:gsub('([^%w])', '%%%1')
end

function M.tbl_filter(tbl, filter_func)
	return vim.tbl_filter(filter_func, tbl)
end

function M.tbl_any(tbl, match_func)
	for _, i in ipairs(tbl) do
		if match_func(i) then
			return true
		end
	end

	return false
end

function M.get_user_input_char(handle_mouse_click)
	local ok, c = pcall(vim.fn.getchar)

	if not ok then
		return
	end

	while type(c) ~= 'number' do
		local ok2, translated_key = pcall(vim.fn.keytrans, c)
		if ok2 and handle_mouse_click and translated_key == '<LeftMouse>' then
			return translated_key
		end

		c = vim.fn.getchar()
	end

	return vim.fn.nr2char(c)
end

function M.clear_prompt()
	vim.api.nvim_command('normal :esc<CR>')
end

return M
