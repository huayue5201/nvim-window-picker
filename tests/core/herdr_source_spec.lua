local herdr = require('window-picker.sources.herdr')
local client = require('window-picker.herdr.client')

describe('herdr source::', function()
	it('reads respect_zoom from opts, only under scope=tab', function()
		assert.is_false(herdr:new({}, {}).respect_zoom)
		assert.is_true(
			herdr:new({ scope = 'tab', respect_zoom = true }, {}).respect_zoom
		)
		assert.is_false(
			herdr:new({ scope = 'workspace', respect_zoom = true }, {}).respect_zoom
		)
		assert.is_false(
			herdr:new({ scope = 'all', respect_zoom = true }, {}).respect_zoom
		)
	end)

	it('keeps every pane when the tab is not zoomed', function()
		local panes = {
			{ pane_id = 'w:p1', tab_id = 'w:t1' },
			{ pane_id = 'w:p2', tab_id = 'w:t1' },
		}

		assert.equals(panes, herdr._visible_in_zoom(panes, { zoomed = false }))
		assert.equals(panes, herdr._visible_in_zoom(panes, nil))
	end)

	it('drops hidden panes of the zoomed tab only', function()
		local panes = {
			{ pane_id = 'w:p1', tab_id = 'w:t1' },
			{ pane_id = 'w:p2', tab_id = 'w:t1' },
			{ pane_id = 'w:p3', tab_id = 'w:t2' },
		}
		local layout = {
			zoomed = true,
			tab_id = 'w:t1',
			focused_pane_id = 'w:p1',
		}

		local visible = herdr._visible_in_zoom(panes, layout)

		assert.equals(2, #visible)
		assert.equals('w:p1', visible[1].pane_id)
		assert.equals('w:p3', visible[2].pane_id)
	end)

	describe('abort::', function()
		local original = client.pane_layout
		local prev_pane = vim.env.HERDR_PANE_ID

		before_each(function()
			vim.env.HERDR_PANE_ID = 'w:p1' -- luacheck: ignore 122
		end)

		after_each(function()
			client.pane_layout = original
			vim.env.HERDR_PANE_ID = prev_pane -- luacheck: ignore 122
		end)

		it('never aborts when respect_zoom is off', function()
			client.pane_layout = function()
				return { zoomed = true, focused_pane_id = 'w:p2' }
			end

			assert.is_false(herdr:new({}, {}):abort())
		end)

		it('aborts when nvim pane is hidden behind another zoom', function()
			client.pane_layout = function()
				return { zoomed = true, focused_pane_id = 'w:p2' }
			end

			assert.is_true(
				herdr:new({ scope = 'tab', respect_zoom = true }, {}):abort()
			)
		end)

		it('ignores respect_zoom outside scope=tab', function()
			client.pane_layout = function()
				return { zoomed = true, focused_pane_id = 'w:p2' }
			end

			assert.is_false(
				herdr
					:new({ scope = 'workspace', respect_zoom = true }, {})
					:abort()
			)
		end)

		it('does not abort when nvim itself is the zoomed pane', function()
			client.pane_layout = function()
				return { zoomed = true, focused_pane_id = 'w:p1' }
			end

			assert.is_false(
				herdr:new({ scope = 'tab', respect_zoom = true }, {}):abort()
			)
		end)

		it('does not abort when the tab is not zoomed', function()
			client.pane_layout = function()
				return { zoomed = false, focused_pane_id = 'w:p2' }
			end

			assert.is_false(
				herdr:new({ scope = 'tab', respect_zoom = true }, {}):abort()
			)
		end)
	end)
end)
