--helper functions specific to dotnet

local M = {}

local uv = vim.loop

local function create_win(bufnr, opts)
	-- First create the window with focus
	local win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = math.floor(vim.o.columns * opts.width_ratio),
		height = math.floor(vim.o.lines * opts.height_ratio),
		row = math.floor(vim.o.lines * opts.row_ratio),
		col = math.floor(vim.o.columns * opts.col_ratio),
		style = "minimal",
		border = opts.border,
	})

	return win
end

local function log_to_file(...)
	local msg = ""
	for i = 1, select("#", ...) do
		local arg = select(i, ...)
		msg = msg .. vim.inspect(arg) .. " "
	end
	msg = os.date("%Y-%m-%d %H:%M:%S") .. ": " .. msg .. "\n"

	local file = io.open(opts.log_path, "a")
	if file then
		file:write(msg)
		file:close()
	else
		vim.notify("Failed to open log file: " .. M.config.log_path, vim.log.levels.ERROR)
	end
end

local function find_csproj_path(start_path)
	local function is_root(path)
		return uv.fs_realpath(path) == uv.fs_realpath(path .. "/..")
	end

	local function scandir(path)
		local handle = uv.fs_scandir(path)
		if not handle then
			return {}
		end
		local entries = {}
		while true do
			local name, type = uv.fs_scandir_next(handle)
			if not name then
				break
			end
			table.insert(entries, { name = name, type = type })
		end
		return entries
	end

	local dir = uv.fs_realpath(start_path)
	while dir do
		for _, entry in ipairs(scandir(dir)) do
			if entry.type == "file" and entry.name:match("%.csproj$") then
				return dir .. "/" .. entry.name
			end
		end
		if is_root(dir) then
			break
		end
		dir = uv.fs_realpath(dir .. "/..")
	end
	return nil
end

function M.get_dll_path()
	local buf_path = vim.api.nvim_buf_get_name(0)
	if buf_path == "" then
		vim.notify("Buffer is empty", vim.log.levels.ERROR)
		return
	end

	local start_dir = vim.fn.fnamemodify(buf_path, ":p:h")
	local csproj = find_csproj_path(start_dir)
	if not csproj then
		vim.notify("No .csproj found in parent directories", vim.log.levels.ERROR)
		return
	end

	local proj_dir = vim.fn.fnamemodify(csproj, ":h")
	local debug_dir = proj_dir .. "/bin/Debug"

	local frameworks = {}
	local handle = uv.fs_scandir(debug_dir)
	if handle then
		while true do
			local name, type = uv.fs_scandir_next(handle)
			if not name then
				break
			end
			if type == "directory" then
				table.insert(frameworks, name)
			end
		end
	end

	if #frameworks == 0 then
		vim.notify("No compiled frameworks found under bin/Debug", vim.log.levels.ERROR)
		return
	end

	local selected_framework = frameworks[1]
	if #frameworks > 1 then
		local choice = vim.fn.inputlist(vim.tbl_extend("force", { "Select target framework:" }, frameworks))
		if type(choice) ~= "number" or choice < 1 or choice > #frameworks then
			vim.notify("Invalid selection", vim.log.levels.ERROR)
			return
		end
		selected_framework = frameworks[choice]
	end

	local proj_name = vim.fn.fnamemodify(csproj, ":t:r")
	local dll_path = string.format("%s/bin/Debug/%s/%s.dll", proj_dir, selected_framework, proj_name)

	if uv.fs_stat(dll_path) then
		return dll_path
	else
		vim.notify("DLL not found: " .. dll_path, vim.log.levels.ERROR)
		return
	end
end

local function get_nearest_test_name()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local col = cursor[2]

	local parser = vim.treesitter.get_parser(bufnr, "c_sharp")
	local tree = parser:parse()[1]
	local root = tree:root()

	-- Get the node directly under the cursor
	local function get_node_at_pos(node, row, col)
		if not node then
			return nil
		end
		if not node:range() then
			return nil
		end

		if node:child_count() == 0 then
			return node
		end

		for child in node:iter_children() do
			local start_row, start_col, end_row, end_col = child:range()
			if
				(row > start_row or (row == start_row and col >= start_col))
				and (row < end_row or (row == end_row and col <= end_col))
			then
				return get_node_at_pos(child, row, col) or child
			end
		end

		return node
	end

	local node = get_node_at_pos(root, row, col)
	local method_node, class_node

	while node do
		if not method_node and (node:type() == "method_declaration" or node:type() == "function_declaration") then
			method_node = node
		elseif not class_node and node:type() == "class_declaration" then
			class_node = node
		end
		if method_node and class_node then
			break
		end
		node = node:parent()
	end

	if not method_node or not class_node then
		vim.notify("Could not find enclosing method/class with Tree-sitter", vim.log.levels.WARN)
		return nil
	end

	local function get_identifier(node)
		for i = 0, node:named_child_count() - 1 do
			local child = node:named_child(i)
			if child:type() == "identifier" then
				return vim.treesitter.get_node_text(child, bufnr)
			end
		end
		return nil
	end

	local function get_namespace()
		-- Get the entire file contents as a string
		local file_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		-- Join the lines into a single string (because the buffer is a list of lines)
		local content = table.concat(file_content, "\n")

		--local namespace_regex = "namespace%s+(.-)%;"
		local namespace_regex = "namespace%s+(.-)[%s;{]"

		local namespace = string.match(content, namespace_regex)

		-- Return the namespace if found, or nil if not found
		if namespace and namespace ~= "" then
			return namespace
		else
			return nil
		end
	end

	local method_name = get_identifier(method_node)
	local class_name = get_identifier(class_node)
	local namespace = get_namespace()

	if method_name and class_name and namespace then
		return namespace .. "." .. class_name .. "." .. method_name
	end

	return nil
end

-- Modified floating terminal runner that doesn't steal focus
local function run_in_terminal(cmd, opts)
	-- Store the current window
	local current_win = vim.api.nvim_get_current_win()

	-- Create buffer and window
	local bufnr = vim.api.nvim_create_buf(false, true)
	local win = create_win(bufnr, opts)

	-- Run the command in the terminal buffer
	vim.fn.termopen(cmd, {
		on_exit = function(_, exit_code, _)
			vim.schedule(function()
				if exit_code == 0 then
					if vim.api.nvim_win_is_valid(win) then
						vim.api.nvim_win_close(win, true)
					end
					if vim.api.nvim_buf_is_valid(bufnr) then
						vim.api.nvim_buf_delete(bufnr, { force = true })
					end
				else
					-- For failures, keep the window open, retain focus,scroll to the bottom and go into insert mode
					vim.api.nvim_set_current_win(win)
					vim.api.nvim_win_call(win, function()
						vim.cmd("normal! G")
						vim.cmd("startinsert")
					end)
				end
			end)
		end,
	})

	-- Return focus to the original window immediately after creating terminal
	vim.api.nvim_set_current_win(current_win)
end

function M.build_no_restore(opts)
	run_in_terminal("dotnet build --no-restore", opts)
end

function M.restore(opts)
	run_in_terminal("dotnet restore", opts)
end

function M.test_nearest(opts)
	local test_name = get_nearest_test_name()
	if not test_name then
		vim.notify("Could not determine nearest test method.", vim.log.levels.WARN)
		return
	end
	local cmd = "dotnet test --no-restore --filter FullyQualifiedName~" .. test_name
	run_in_terminal(cmd, opts)
end

function M.show_log(opts)
	local log_path = opts.log_path -- Read the log file lines
	local lines = {}
	local file = io.open(opts.log_path, "r")
	if file then
		for line in file:lines() do
			table.insert(lines, line)
		end
		file:close()
	else
		vim.notify("Log file not found: " .. log_path, vim.log.levels.WARN)
		return
	end

	-- Create a new scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = "log"
	create_win(buf)
end

function M.setup(opts)
	-- Modified terminal configuration for bottom placement

	local merged_options = vim.tbl_extend("force", M.config, opts or {})

	vim.api.nvim_create_user_command("DotnetLogs", function()
		M.show_log(merged_options)
	end, { desc = "Open the dbt dotnet.log file in a new buffer" })

	vim.api.nvim_create_user_command("DotnetBuild", function()
		M.build_no_restore(merged_options)
	end, { desc = "Build dotnet project (no restore)" })

	vim.api.nvim_create_user_command("DotnetRestore", function()
		M.restore(merged_options)
	end, { desc = "Restore dotnet project" })

	vim.api.nvim_create_user_command("DotnetTestNearest", function()
		M.test_nearest(merged_options)
	end, { desc = "Test nearest method with dotnet test (no restore)" })

	vim.keymap.set("n", "<leader>db", M.build_no_restore(merged_options), { desc = "[D]otnet [B]uild (no restore)" })
	vim.keymap.set("n", "<leader>dr", M.restore(merged_options), { desc = "[D]otnet [R]estore" })
	vim.keymap.set(
		"n",
		"<leader>dt",
		M.test_nearest(merged_options),
		{ desc = "[D]otnet [T]est nearest method (no restore)" }
	)
end

M.config = {
	width_ratio = 1.0, -- Full width
	height_ratio = 0.25, -- Take up 25% of screen height
	row_ratio = 0.75, -- Position at 75% from top (bottom area)
	col_ratio = 0.0, -- Start from left edge
	border = "rounded",
	log_path = vim.fn.stdpath("log") .. "dbt.log",
}

return M
