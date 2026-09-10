local cmd = require("cmd")
local file = require("file")
local json = require("json")
local strings = require("strings")

local function find_ssh_crypt()
	local home = os.getenv("HOME")
	local data_dir = os.getenv("MISE_DATA_DIR") or file.join_path(home, ".local/share/mise")
	local installs = file.join_path(data_dir, "installs")
	local path = file.join_path(installs, "pipx-ssh-crypt/latest/bin/ssh-crypt")
	if file.exists(path) then
		return path
	end

	local find = "find " .. installs .. " -name ssh-crypt -type f -perm +111"
	local exec = strings.split(cmd.exec(find), "\n")
	if #exec > 1 then
		return exec[#exec - 1]
	end

	local ok, path = pcall(cmd.exec, "which ssh-crypt")
	if ok then
		path = strings.trim_space(path)
		local shims = file.join_path(data_dir, "shims") .. "/"
		if not strings.has_prefix(path, shims) then
			return path
		end
	end

	error("Unable to find ssh-crypt executable outside the mise shims directory")
end

local function read_secrets_file(exec, path, kvs)
	if not file.exists(path) then
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
