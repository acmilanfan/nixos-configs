lua << EOF

local telescope = require("telescope")
local telescopeConfig = require("telescope.config")

local vimgrep_arguments = { unpack(telescopeConfig.values.vimgrep_arguments) }
table.insert(vimgrep_arguments, "--hidden")

telescope.setup({
	defaults = {
		vimgrep_arguments = vimgrep_arguments,
		file_ignore_patterns = {
			"node_modules/",
			"vendor/",
			".git/"
		},
		layout_strategy = "vertical",
		layout_config = {
			prompt_position = "top",
			-- mirror = true,
		},
	},
	extensions = {
		["ui-select"] = {
			require("telescope.themes").get_dropdown { }
		},
	},
})

require('telescope').load_extension('orgmode')
require('telescope').load_extension('harpoon')
require("telescope").load_extension("ui-select")
require("telescope").load_extension("refactoring")
require("telescope").load_extension("rest")
pcall(require('telescope').load_extension, 'fzf')

EOF
