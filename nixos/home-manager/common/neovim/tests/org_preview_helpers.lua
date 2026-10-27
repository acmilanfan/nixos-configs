local M = {}
function M.load()
  local dir = vim.fn.getcwd() .. "/nixos/home-manager/common/neovim"
  vim.opt.runtimepath:prepend(dir)
  package.path = dir .. "/lua/?.lua;" .. dir .. "/lua/?/init.lua;" .. package.path
  vim.cmd("filetype on") -- -u NONE skips detection; fixtures rely on it for ft=org.
  return dir
end
function M.root(name)
  local root = vim.fn.expand("~/ai/artifacts/nixos-configs/" .. name .. "-") .. vim.fn.getpid()
  vim.fn.mkdir(root, "p")
  return root
end
function M.fixture(root, rel, lines)
  local path = root .. "/" .. rel
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  assert(vim.fn.writefile(lines, path) == 0)
  return path
end
local failures, passed = {}, 0
function M.test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failures[#failures + 1] = name .. ": " .. tostring(err); print("FAIL " .. failures[#failures]) end
end
function M.finish()
  assert(#failures == 0, table.concat(failures, "\n"))
  print(passed .. " preview checks passed")
end
function M.eq(actual, expected)
  assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end
function M.texts(lines) return vim.tbl_map(function(l) return l.text end, lines) end
return M
