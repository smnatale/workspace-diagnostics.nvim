-- lua/workspace-diagnostics/config.lua
-- Default configuration and merge logic

local M = {}

M.defaults = {
	-- Trigger workspace diagnostics automatically on LspAttach
	auto_trigger = true,

	-- File list cache TTL in seconds
	cache_ttl = 300,

	-- Number of files to process per async tick
	chunk_size = 10,

	-- Delay in ms between processing chunks
	chunk_delay = 1,

	-- Show start/complete notifications
	notify_progress = true,

	-- Only run workspace diagnostics for these LSP servers
	allowed_lsps = {
		"ts_ls",
		"eslint",
	},

	-- File extensions to include (must match allowed_lsps filetypes)
	allowed_extensions = {
		".ts",
		".tsx",
		".js",
		".jsx",
	},

	-- Directory patterns to ignore
	ignore_dirs = {
		"/.yarn/",
		"/node_modules/",
		"/dist/",
		"/build/",
	},
}

--- Merge user config with defaults
---@param user_config table|nil
---@return table
function M.merge(user_config)
	user_config = user_config or {}
	local config = vim.tbl_deep_extend("force", {}, M.defaults, user_config)

	-- Convert list configs to lookup tables for faster access
	config._allowed_lsps = {}
	for _, lsp in ipairs(config.allowed_lsps) do
		config._allowed_lsps[lsp] = true
	end

	config._allowed_extensions = {}
	for _, ext in ipairs(config.allowed_extensions) do
		config._allowed_extensions[ext] = true
	end

	return config
end

return M
