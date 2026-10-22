local ghostty = require('window-picker.sources.ghostty')
local client = require('window-picker.ghostty.client')

local uv = vim.uv or vim.loop

local cwd = uv.cwd()

local function terminal(overrides)
	return vim.tbl_deep_extend('force', {
		terminal_id = 'term',
		title = 'nvim',
		cwd = cwd,
		tab_id = 'tab-1',
		window_id = 'win-1',
	}, overrides or {})
end

describe('ghostty source::', function()
	local real_current_surface = client.current_surface

	before_each(function()
		client.current_surface = function()
			return nil
		end
	end)

	after_each(function()
		client.current_surface = real_current_surface
	end)

	it(
		'prefers the focused terminal of the frontmost ghostty window',
		function()
			local self = terminal({ tab_id = 'tab-9', window_id = 'win-9' })
			local sibling = terminal({ terminal_id = 'sibling' })

			client.current_surface = function()
				return {
					window_id = 'win-9',
					tab_id = 'tab-9',
					terminal_id = 'term',
				}
			end

			assert.equals(self, ghostty._current({ sibling, self }))
		end
	)

	it('falls back to cwd when ghostty is not frontmost', function()
		local self = terminal()

		client.current_surface = function()
			return { window_id = 'x', tab_id = 'x', terminal_id = 'not-listed' }
		end

		assert.equals(self, ghostty._current({ self }))
	end)

	it('defaults to scope=all', function()
		assert.equals('all', ghostty:new({}, {}).scope)
		assert.equals('tab', ghostty:new({ scope = 'tab' }, {}).scope)
	end)

	it('detects its own terminal by cwd', function()
		local self = terminal()

		assert.equals(self, ghostty._current({ self }))
	end)

	it('breaks a cwd tie with the terminal title', function()
		local self = terminal()
		local sibling = terminal({
			terminal_id = 'sibling',
			title = '~/somewhere',
		})

		assert.equals(self, ghostty._current({ sibling, self }))
	end)

	it('gives up when several terminals share cwd and title', function()
		local a = terminal({ terminal_id = 'a' })
		local b = terminal({ terminal_id = 'b' })

		assert.is_nil(ghostty._current({ a, b }))
	end)

	it('ignores terminals with another cwd', function()
		local other = terminal({ cwd = '/tmp/some-other-dir' })

		assert.is_nil(ghostty._current({ other }))
	end)

	it('filters by scope once the current terminal is known', function()
		local self = terminal()
		local same_tab = terminal({ terminal_id = 'same-tab' })
		local same_win =
			terminal({ terminal_id = 'same-win', tab_id = 'tab-2' })
		local far = terminal({
			terminal_id = 'far',
			tab_id = 'tab-3',
			window_id = 'win-2',
		})

		local tab = ghostty:new({ scope = 'tab' }, {})
		assert.is_true(tab:_in_scope(same_tab, self))
		assert.is_false(tab:_in_scope(same_win, self))
		assert.is_false(tab:_in_scope(far, self))

		local win = ghostty:new({ scope = 'window' }, {})
		assert.is_true(win:_in_scope(same_win, self))
		assert.is_false(win:_in_scope(far, self))

		local all = ghostty:new({}, {})
		assert.is_true(all:_in_scope(far, nil))

		-- an unknown current surface must not leak other tabs/windows in
		assert.is_false(tab:_in_scope(same_tab, nil))
		assert.is_false(win:_in_scope(same_win, nil))
	end)

	it('falls back through title, tab, window and cwd for the title', function()
		assert.equals('x', ghostty._title({ title = 'x' }))
		assert.equals('t', ghostty._title({ title = '', tab_title = 't' }))
		assert.equals(
			'w',
			ghostty._title({ tab_title = '', window_name = 'w' })
		)
		assert.equals('dir', ghostty._title({ cwd = '/tmp/dir' }))
		assert.equals('id', ghostty._title({ terminal_id = 'id' }))
	end)

	it('shortens the cwd for the detail', function()
		assert.equals(
			'~/tmp',
			ghostty._detail({ cwd = vim.fn.expand('~') .. '/tmp' })
		)
		assert.is_nil(ghostty._detail({ cwd = '' }))
	end)

	describe('list::', function()
		local original = client.list_terminals

		after_each(function()
			client.list_terminals = original
		end)

		it('excludes nvim itself and ranks near terminals first', function()
			local self = terminal()
			local same_tab = terminal({
				terminal_id = 'same-tab',
				title = 'shell',
			})
			local far = terminal({
				terminal_id = 'far',
				title = 'far',
				cwd = '/tmp/some-other-dir',
				tab_id = 'tab-3',
				window_id = 'win-2',
			})

			client.list_terminals = function()
				return { far, same_tab, self }
			end

			local targets = ghostty:new({}, {}):list()

			assert.equals(2, #targets)
			assert.equals('ghostty:same-tab', targets[1].id)
			assert.equals('ghostty:far', targets[2].id)
			assert.equals('shell', targets[1].title)
			assert.equals('ghostty', targets[1].kind)
			assert.equals(same_tab, targets[1].meta)
		end)

		it('applies the tab scope', function()
			local self = terminal()
			local same_tab = terminal({ terminal_id = 'same-tab' })
			local other_tab = terminal({
				terminal_id = 'other-tab',
				tab_id = 'tab-2',
			})

			client.list_terminals = function()
				return { self, same_tab, other_tab }
			end
			client.current_surface = function()
				return {
					window_id = self.window_id,
					tab_id = self.tab_id,
					terminal_id = self.terminal_id,
				}
			end

			local targets = ghostty:new({ scope = 'tab' }, {}):list()

			assert.equals(1, #targets)
			assert.equals('ghostty:same-tab', targets[1].id)
		end)

		it('lists nothing when the current terminal is unknown', function()
			local a = terminal({ terminal_id = 'a', cwd = '/tmp/one' })
			local b = terminal({ terminal_id = 'b', cwd = '/tmp/two' })

			client.list_terminals = function()
				return { a, b }
			end

			local targets = ghostty:new({ scope = 'tab' }, {}):list()

			assert.equals(0, #targets)
		end)

		it('returns no target when the list fails', function()
			client.list_terminals = function()
				return nil, 'boom'
			end

			local targets = ghostty:new({}, {}):list()

			assert.equals(0, #targets)
		end)
	end)
end)

describe('ghostty client::', function()
	it('parses a record', function()
		local record = table.concat({
			'win-1',
			'window',
			'tab-1',
			'tab',
			'2',
			'true',
			'term-1',
			'nvim',
			'/tmp',
		}, string.char(31))

		assert.same({
			window_id = 'win-1',
			window_name = 'window',
			tab_id = 'tab-1',
			tab_title = 'tab',
			tab_index = 2,
			tab_selected = true,
			terminal_id = 'term-1',
			title = 'nvim',
			cwd = '/tmp',
		}, client._parse(record))
	end)

	it('ignores malformed records', function()
		assert.is_nil(client._parse('too' .. string.char(31) .. 'short'))
	end)
end)

describe('ghostty client snapshot::', function()
	local us = string.char(31)
	local rs = string.char(30)

	local function record(fields)
		return table.concat(fields, us)
	end

	local real_run = client._run

	after_each(function()
		client._run = real_run
		client._clear_cache()
	end)

	it('parses terminals and the current surface marker', function()
		local out = table.concat({
			record({ 'cur', 'win-1', 'tab-1', 'term-1' }),
			record({
				'win-1',
				'window',
				'tab-1',
				'tab',
				'1',
				'true',
				'term-1',
				'nvim',
				'/tmp',
			}),
		}, rs)

		local terminals, current = client._parse_snapshot(out)

		assert.equals(1, #terminals)
		assert.equals('term-1', terminals[1].terminal_id)
		assert.same({
			window_id = 'win-1',
			tab_id = 'tab-1',
			terminal_id = 'term-1',
		}, current)
	end)

	it('has no current surface when the marker is missing', function()
		local terminals, current = client._parse_snapshot('')

		assert.equals(0, #terminals)
		assert.is_nil(current)
	end)

	it('serves repeated reads from the cache', function()
		local calls = 0
		client._run = function()
			calls = calls + 1
			return table.concat({
				record({ 'cur', 'win-1', 'tab-1', 'term-1' }),
				record({
					'win-1',
					'window',
					'tab-1',
					'tab',
					'1',
					'true',
					'term-9',
					'other',
					'/tmp',
				}),
			}, rs)
		end

		local first = client.list_terminals({ scope = 'tab' })
		local second = client.list_terminals({ scope = 'tab' })

		assert.equals(1, calls)
		assert.equals(1, #first)
		assert.same(first, second)
	end)
end)
