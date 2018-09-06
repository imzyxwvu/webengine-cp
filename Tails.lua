local function doWithEnv(file, env)
	if setfenv then
		local chunk = assert(loadfile(file))
		setfenv(chunk, env)
		return chunk()
	else
		return assert(loadfile(file, "bt", env))()
	end
end

function package.preload.ViewEngine()
    local VE = {}

    function VE.Prepare(template, output)
	    assert(type(template) == "string", "template must be a string")
	    local function fetchPath(str)
		    local path = {}
		    for p in str:gmatch("([^%.]+)") do path[#path + 1] = p end
		    return path
	    end
	    local current, inside, result, stack = 1, false, output or { _ZyVE_tpl = true }, {}
	    while true do
		    if inside then
			    local l, r = template:find("@>", current, true)
			    assert(l and r, "close tag not found")
			    local instruction = template:sub(current, l - 1)
			    if instruction:find("^%!") then
				    local cmd, arg = instruction:match("^%!([a-z]+)%s+([A-Za-z0-9_%.%%]+)%s*$")
				    if cmd == "include" then
					    error("not implemented")
				    elseif cmd == "if" then
					    result[#result + 1] = { 3, fetchPath(arg) }
					    stack[#stack + 1] = { "if", result[#result] }
				    elseif cmd == "ifnot" then
					    result[#result + 1] = { 3, fetchPath(arg), reverse = true }
					    stack[#stack + 1] = { "if", result[#result] }
				    elseif cmd == "ifnb" then
					    result[#result + 1] = { 3, fetchPath(arg), nblank = true }
					    stack[#stack + 1] = { "if", result[#result] }
				    elseif cmd == "each" then
					    local ek, ev = arg:match("^([A-Za-z0-9_]+)%%([A-Za-z0-9_%.]+)$")
					    assert(ek and ev, "bad each instruction")
					    result[#result + 1] = { 4, fetchPath(ev), ekey = ek }
					    stack[#stack + 1] = { "each", result[#result] }
				    else error("not implemented command") end
			    else
				    instruction = instruction:match("^%s*([A-Za-z0-9_%.]+)%s*$")
				    if instruction then
					    if instruction == "end" then
						    assert(#stack > 0, "nothing to end in the stack")
						    stack[#stack][2].last = #result
						    stack[#stack] = nil
					    elseif instruction == "else" then
						    assert(#stack > 0, "stack is empty")
						    assert(stack[#stack][1] == "if", "else requires an if")
						    assert(not stack[#stack][2].otherwise, "trying else twice")
						    stack[#stack][2].otherwise = #result
					    else
						    result[#result + 1] = { 2, fetchPath(instruction) }
					    end
				    end
			    end
			    current, inside = r + 1, false
		    else
			    local l, r = template:find("<@", current, true)
			    if l and r then
				    local chunk = template:sub(current, l - 1)
				    result[#result + 1] = { 1, chunk }
				    current, inside = r + 1, true
			    else
				    if current <= #template then
					    local chunk = template:sub(current, -1)
					    result[#result + 1] = { 1, chunk }
				    end
				    break
			    end
		    end
	    end
	    assert(#stack == 0, "expected end instruction")
	    return result
    end

    local function fetchValue(data, stack, path)
	    local current = data
	    for i, v in ipairs(path) do
		    assert(type(current) == "table", "only tables can be indexed")
		    if current[v] then
			    current = current[v]
		    elseif v == "_" then
			    current = VE.Global
		    elseif i == 1 then
			    local got = false
			    for i = #stack, 1, -1 do
				    if stack[i][3] == 4 and stack[i][6] == v then
					    current, got = stack[i][7], true
					    break
				    end
			    end
			    if not got then return nil end
		    else return nil end
	    end
	    return current
    end

    function VE.Render(template, data)
	    local ptr, result, stack = 1, {}, {}
	    while template[ptr] do
		    if template[ptr][1] == 1 then
			    result[#result + 1] = template[ptr][2]
		    elseif template[ptr][1] == 2 then
			    local value = fetchValue(data, stack, template[ptr][2])
			    if value then
				    local t = type(value)
				    if t == "function" then value = value(); t = type(value) end
				    if t == "number" then value = tostring(value)
				    elseif t ~= "string" then
					    error("expected string: " .. table.concat(template[ptr][2], "."))
				    end
				    result[#result + 1] = value
			    else
				    error("value not found: " .. table.concat(template[ptr][2], "."))
			    end
		    elseif template[ptr][1] == 3 then
			    local value = fetchValue(data, stack, template[ptr][2])
			    if template[ptr].notblank then
				    assert(type(value) == "table")
				    value = value[1]
			    end
			    if template[ptr].reverse then value = not value end
			    if value then
				    if template[ptr].otherwise then
					    stack[#stack + 1] = { ptr, template[ptr].otherwise, 3,
						    template[ptr].last }
				    end
			    else
				    ptr = template[ptr].otherwise or template[ptr].last
			    end
		    elseif template[ptr][1] == 4 then
			    local value = fetchValue(data, stack, template[ptr][2])
			    assert(type(value) == "table", "expected a table for an each")
			    if value[1] then
				    stack[#stack + 1] = { ptr, template[ptr].last, 4,
					    value, 1, template[ptr].ekey, value[1] }
			    else ptr = template[ptr].last end
		    else error("multiple ZyVE versions detected") end
		    if #stack > 0 then
			    local jump = stack[#stack]
			    if ptr == jump[2] then
				    if jump[3] == 4 then
					    jump[5] = jump[5] + 1 -- next index
					    jump[7] = jump[4][jump[5]]
					    if jump[7] then
						    ptr = jump[1] -- continue each
					    else
						    stack[#stack] = nil -- clean stack
					    end
				    elseif jump[3] == 3 then
					    ptr = jump[4] -- jumps out if
					    stack[#stack] = nil -- clean stack
				    end
			    end
		    end
		    ptr = ptr + 1
	    end
	    assert(#stack == 0, "a bug in ViewEngine.Render")
	    return table.concat(result)
    end

    function VE.Wrap(tpl)
	    local render, prepared = VE.Render, VE.Prepare(tpl)
	    return function(data)
		    return render(prepared, data)
	    end
    end

    return VE
end

local corunning, lfs = coroutine.running, lfs
local viewEngine = require "ViewEngine"
local TailsApp_Methods = {}

local function urlEncode()
	return str:gsub("([&=%%%?;])", function(c)
        return ("%%%02X"):format(c:byte(1, 1))
    end)
end

function TailsApp_Methods:LoadView(vn)
	local fp = assert(io.open(self.viewDir .. vn, "rb"))
	return viewEngine.Prepare(fp:read("*a"))
end

function TailsApp_Methods:Dispatch(req, res)
	local path = {}
	for p in req.resource:gmatch("([^/\\]+)") do path[#path + 1] = p end
	local dispatchto, arguments
	for i, route in ipairs(self.routes) do
		if route.method == req.method and #route.match == #path then
			arguments = {}
			for ii, m in ipairs(route.match) do
				if m.match then
					if m.match ~= path[ii] then
						arguments = nil
						break
					end
				else
					arguments[m[1]] = path[ii]
				end
			end
			if arguments then
				dispatchto = route
				break
			end
		end
	end
	if dispatchto then
		local query = {}
		for p in req.query:gmatch("([^&]+)") do
			local k, v = p:match("^([^=%s]+)=(.*)$")
			if k and v then query[k] = HTTP.UrlDecode(v) end
		end
		query.action = arguments.action or dispatchto.action or "index"
		assert(query.action ~= "_before", "disabled action")
		if not self.actions[query.action] then return nil end
		local post, env, methods = {}, {}, { TAILS_ROOT = self.base }
		if req.method == "POST" and req.headers["content-type"] then
			local contentLength = tonumber(req.headers["content-length"])
			if req.headers["content-type"]:find("application/x-www-form-urlencoded", 1, true) then
				if contentLength and contentLength < 0x20000 then
					for p in req.post:gmatch("([^&]+)") do
						local k, v = p:match("^([^=%s]+)=(.*)$")
						if k and v then post[k] = HTTP.UrlDecode(v) end
					end
				end
			else
				local boundary = req.headers["content-type"]:
					match("^multipart/form-data;%s+boundary=([^;]+)$")
				if boundary and contentLength and contentLength < 0x200000 then
					local postdata = req.reader:Get(contentLength)
					for key, block in pairs(parseMultipart(postdata)) do
						post[key] = block
					end
				else
					error("please use multipart protocol to upload")
				end
			end
		end
		methods.request = req
		methods.params = setmetatable({}, {
			__index = function(self, k)
				return post[k] or arguments[k] or query[k]
			end,
			__newindex = function() error("params are read-only") end
		})
		local cookies, pendingCookies = {}, {}
		if req.headers.cookie then
			req.headers.cookie:gsub("[^%;]+", function(str)
				local key, value = str:match("([^%=%s]+)%=(.+)$")
				if key and value then cookies[key] = value end
			end)
		end
		methods.cookies = setmetatable({}, {
			__index = function(self, k)
				return cookies[k]
			end,
			__newindex = function(self, k, c)
				assert(type(k) == "string", "cookie key must be a string")
				local t_c = type(c)
				if t_c == "table" then
					assert(type(c[1]) == "string", "cookie value must be a string")
					rawset(cookies, k, c[1])
					pendingCookies[k] = c
				elseif t_c == "string" then
					rawset(cookies, k, c)
					pendingCookies[k] = { c }
				elseif t_c == "number" then
					c = tostring(c)
					rawset(cookies, k, c)
					pendingCookies[k] = { c }
				elseif t_c == "nil" then
					rawset(cookies, k, nil)
					pendingCookies[k] = { "" }
				else
					error("unacceptable cookie type")
				end
			end
		})
		local function prepareSetCookies()
			local _setcookie = {}
			for k, v in pairs(pendingCookies) do
				_setcookie[#_setcookie + 1] = ("%s=%s; path=%s"):
					format(k, urlEncode(v[1]), v.path or "/")
				if v.expires then
					_setcookie[#_setcookie] = _setcookie[#_setcookie] ..
						os.date("; expires=!%A, %d-%b-%Y %H:%M:%S GMT", v.expires)
				end
			end
			if #_setcookie > 0 then return _setcookie end
		end
		function methods.permit(values, ...)
			local permitted = {}
			for i, v in ipairs{...} do permitted[v] = values[v] end
			return permitted
		end
		function methods.redirect_to(location)
			res:writeHeader(302, {
				Location = location,
				["Content-Length"] = 0,
				["Set-Cookie"] = prepareSetCookies()
			})
		end
		function methods.render(view)
			local result = viewEngine.Render(self:LoadView(
				("%s.html"):format(view)
			), env)
			res:writeHeader(200, {
				["Content-Length"] = #result,
				["Set-Cookie"] = prepareSetCookies()
			})
			res:rawWrite(result)
		end
		self.envs[corunning()] = setmetatable({}, {
			__index = function(self, k)
				return methods[k] or env[k]
			end,
			__newindex = function(self, k, v)
				assert(not methods[k], "can't overwrite system methods")
				env[k] = v
			end
		})
		if self.actions._before then self.actions._before() end
		if not res.headerSent then self.actions[query.action]() end
		if not res.headerSent then methods.render(query.action) end
	end
end

function TailsApp_Methods:Handler()
	local vhost = { documentRoot = self.base .. "/public" }
	return function(req, res)
		self:Dispatch(req, res)
		if not res.headerSent then
			return HTTP.HandleRequest(req, res, vhost)
		end
	end
end

TailsApp_Methods.__index = TailsApp_Methods

function Tails(basePath)
	assert(HTTP, "please make sure WebEngine loaded first")
	local app = { base = basePath, actions = {}, views = {}, routes = {} }
	local appPrepare = true
	app.envs = setmetatable({}, { __mode = "k" })
	local env = setmetatable({}, {
		__newindex = function(self, k, v)
			if appPrepare then
				assert(type(v) == "function", "assignment to an undefined varible")
				app.actions[k] = v
			else
				assert(app.envs[corunning()], "not in a request")[k] = v
			end
		end,
		__index = function(self, k)
			if appPrepare then
				if _G[k] then
					return _G[k]
				else
                    error("undefined varible: " .. k)
                end
			else
				local env = assert(app.envs[corunning()], "not in a request")
				return env[k] or app.actions[k] or _G[k]
			end
		end
	})
	assert(not doWithEnv(basePath .. "/application.lua", env),
	       "application.lua should return nil")
	appPrepare = false
	local currentRoute
	local function commitCurrentRoute()
		app.routes[#app.routes + 1] = currentRoute
	end
	local function makeRoute(method, route)
		assert(type(route) == "string", "bad argument")
		commitCurrentRoute()
		currentRoute = { method = method, match = {} }
		for p in route:gmatch("([^/\\]+)") do
			if p:find"^:" then
				currentRoute.match[#currentRoute.match + 1] = { p:sub(2, -1) }
			else
				currentRoute.match[#currentRoute.match + 1] = { match = p }
			end
		end
	end
	local function modifyRoute(action)
		assert(type(action) == "string", "bad argument")
		assert(currentRoute, "define a route first")
		currentRoute.action = action
	end
	assert(not doWithEnv(basePath .. "/routes.lua", setmetatable({}, {
		__index = {
			get = function(route) return makeRoute("GET", route) end,
			post = function(route) return makeRoute("POST", route) end,
			delete = function(route) return makeRoute("DELETE", route) end,
			with = function(val) return modifyRoute(val) end
		},
		__newindex = function()
			error("out of this file's scope")
		end
	})), "routes.lua should return nil")
	commitCurrentRoute()
	app.viewDir = basePath .. "/views/"
	return setmetatable(app, TailsApp_Methods)
end

return Tails