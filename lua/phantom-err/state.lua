local M = {}

local buffer_states = {}

function M.is_enabled(bufnr)
  return buffer_states[bufnr] == true
end

function M.set_enabled(bufnr, enabled)
  buffer_states[bufnr] = enabled
end

function M.cleanup(bufnr)
  buffer_states[bufnr] = nil
end

vim.api.nvim_create_autocmd("BufDelete", {
  callback = function(args)
    M.cleanup(args.buf)
  end,
})

return M