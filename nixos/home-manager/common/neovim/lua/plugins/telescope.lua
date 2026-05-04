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
			".git/",
		},
		layout_strategy = "vertical",
		layout_config = {
			prompt_position = "top",
			-- mirror = true,
		},
	},
	extensions = {
		["ui-select"] = {
			require("telescope.themes").get_dropdown({}),
		},
	},
})

pcall(telescope.load_extension, "orgmode")
pcall(telescope.load_extension, "harpoon")
pcall(telescope.load_extension, "ui-select")
pcall(telescope.load_extension, "refactoring")
pcall(telescope.load_extension, "rest")
pcall(telescope.load_extension, "fzf")
