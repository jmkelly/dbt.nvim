local dbt = require("dbt")

local M = {
	opts = dbt.opts,
}

M.setup = function(opts)
	require("dbt").setup(opts)
end

return M
