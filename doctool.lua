#!/usr/bin/env lua

local function parse_section(delim)
	return function(S, str, pos, header)
		local end_section = str:find('\n'..delim..' ', pos) or #str
		local title, short = header:match("^([^%[]+)%s*%[([^%]]+)%]%s*$")
		if not title then title, short = header, '' end
		S[#S+1] = {type = 'section', title, short, #delim, str:sub(pos, end_section-1)}
		return end_section + 1
	end
end

local function parse_parameters(F, str, pos)
	local end_block = str:find('\n#### ', pos) or #str
	F[#F+1] = {type = 'parameters', str:sub(pos, end_block-1)}
	return end_block+1
end

local function parse_returns(F, str, pos)
	local end_block = str:find('\n#### ', pos) or #str
	F[#F+1] = {type = 'returns', str:sub(pos, end_block-1)}
	return end_block+1
end

local function parse_example(F, str, pos)
	local end_block = str:find('\n#### ', pos) or #str
	F[#F+1] = {type = 'example', str:sub(pos, end_block-1)}
	return end_block+1
end

local function parse_sketch(F, str, pos)
	local end_block = str:find('\n#### ', pos) or #str
	F[#F+1] = {type = 'sketch', str:sub(pos, end_block-1)}
	return end_block+1
end

local function parse_function(M, str, pos, header)
	local name, params, short_desc = header:match("^%s*function%s([^%(]+)(%b())%s+(%b[])")
	if not (name and params and short_desc) then
		name, params, short_desc = header:match("^%s*function%s([^{]+)(%b{})%s+(%b[])")
	end
	assert(name and params and short_desc, "Line `"..header.."' has invalid formatting")
	local has_table_args = params:sub(1,1) == '{'
	params = params:sub(2,-2)
	short_desc = short_desc:sub(2,-2)

	-- shadow str with content of function
	local end_function = str:find('\n### ', pos) or #str
	str, pos = str:sub(pos, end_function), 1

	local hashpos = str:find('\n#### ', pos) or #str
	local long_desc = str:sub(pos, hashpos-1)

	local F = {}
	pos = hashpos + 1
	while pos <= #str do
		local endhash = str:find(' ', pos)+1
		local endline = str:find('\n', endhash)-1
		local line = str:sub(endhash, endline)

		local processor = line:match("^%S+%s*$")
		assert(processor, "Invalid format for function `" .. name .. "' in line `" .. line .. "'")
		if processor:sub(-1,-1) == ':' then processor = processor:sub(1,-2) end
		processor = processor:lower()
		pos = (({
			['parameters'] = parse_parameters,
			['returns']    = parse_returns,
			['example']    = parse_example,
			['sketch']     = parse_sketch,
		})[processor] or parse_section("####"))(F, str, endline+1, line)
	end

	M[#M+1] = {type = 'function',
		has_table_args = has_table_args,
		name,
		params,
		short_desc,
		long_desc,
		F
	}
	return end_function + 1
end

local function parse_module(S, str, pos, header)
	local title, short_desc = header:match("^%s*[mM]odule ([^%[]+)%s+%[([^%]]+)%]")
	assert(title and short_desc, "Line `"..header.."' has invalid formatting")

	-- shadow str with content of the module
	local end_module = str:find('\n## ', pos) or #str
	str, pos = str:sub(pos, end_module), 1

	-- parse module info
	local long_desc_end = str:find('\n### ', pos) or #str
	local long_desc = str:sub(pos, long_desc_end)

	local M = {}
	pos = long_desc_end + 1
	while pos <= #str do
		local endhash = str:find(' ', pos)+1
		local endline = str:find('\n', endhash)-1
		local line = str:sub(endhash, endline)

		local processor = line:match("^%S+"):lower()
		pos = (({
			['function'] = parse_function,
			-- TODO: more stuff?
		})[processor] or parse_section('###'))(M, str, endline+1, line)
	end

	S[#S+1] = {type = 'module',
		title,
		short_desc,
		long_desc,
		M
	}
	return end_module + 1
end

local function parse(str)
	local S = {
		{type = 'title', assert(str:match("^#%s(.-)%s\n"), "Invalid markup: Missing title")}
	}

	local hashpos = str:find('##')
	while hashpos <= #str do
		local endhash = str:find(' ', hashpos)+1
		local endline = str:find('\n', hashpos)-1
		local line = str:sub(endhash, endline)

		local processor = line:match("^%S+"):lower()
		hashpos = (({
			['module'] = parse_module,
			-- TODO: more stuff?
		})[processor] or parse_section('##'))(S, str, endline+1, line)
	end

	return S
end

-- main --
local path, theme = ...
if not path then
	print("Usage: doctool.lua file.md [theme] > out.html")
	return
end

if not theme then theme = 'theme-default.lua' end

local f = assert(io.open(path, 'r'))
str = f:read('*a')
f:close()

local theme = setmetatable(dofile(theme), {__index = function(_,k)
	error("Unhandled item: " .. k, 2)
end}) -- the 'interpreter'

local doctree = theme.preprocess(parse(str))

-- build page
local out = {}
for _,info in ipairs(doctree) do
	out[#out+1] = theme[info.type](info)
end
out = theme.postprocess(table.concat(out))

print(out)
