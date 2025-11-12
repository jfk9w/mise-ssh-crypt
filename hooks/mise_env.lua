local cmd = require("cmd")
local file = require("file")
local json = require("json")
local strings = require("strings")

local function find_ssh_crypt()
	local ok, path = pcall(cmd.exec, "which ssh-crypt")
	if ok then
		return strings.trim_space(path)
	end

	local home = os.getenv("HOME")
	local installs = file.join_path(home, ".local/share/mise/installs")
	path = file.join_path(installs, "pipx-ssh-crypt/latest/bin/ssh-crypt")
	ok, _ = pcall(cmd.exec, "stat " .. path)
	if ok then
		return path
	end

	local find = "find " .. installs .. " -name ssh-crypt -type f -perm +111"
	local exec = strings.split(cmd.exec(find), "\n")
	if #exec == 1 then
		error("Unable to find ssh-crypt executable")
	end

	return exec[#exec - 1]
end

local function read_secrets_file(exec, path, kvs)
	local ok, _ = pcall(cmd.exec, "stat " .. path)
	if not ok then
		return {}
	end

	local data =
		cmd.exec([[cat ]] .. path .. [[ | sed -e 's/: "/: E"/' | ]] .. exec() .. [[ -t jsonc | sed -e 's/\\/\\\\/']])

	local values = json.decode(data)
	for key, value in pairs(values) do
		kvs[key] = value
	end
end

local function walk_parents(exec, name, kvs)
	local dir = "/"
	for _, element in ipairs(strings.split(os.getenv("PWD"), "/")) do
		dir = file.join_path(dir, element)
		local path = file.join_path(dir, name)
		read_secrets_file(exec, path, kvs)
	end
end

function PLUGIN:MiseEnv(ctx)
	local path = ctx.options.path or ".secrets.json"
	local exec = ctx.options.exec
	local fn = function()
		if not exec then
			exec = find_ssh_crypt()
		end

		return exec
	end

	local kvs = {}
	if strings.has_prefix(path, "/") then
		read_secrets_file(fn, path, kvs)
	else
		walk_parents(fn, path, kvs)
	end

	local env = {}
	for key, value in pairs(kvs) do
		table.insert(env, { key = key, value = value })
	end

	return env
end
