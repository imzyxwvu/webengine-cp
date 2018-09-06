HTTP = require "HTTP"
Tails = require "Tails"
DB = require("lsqlite3").open("config.db")
HTTP.Logger = require "Logger"

CP = Tails("CP"):Handler()

System = { }

function System:Prepare(sql)
    local stmt = DB:prepare(sql)
    if not stmt then error(self[1]:errmsg()) end
    return stmt
end

function System:ReloadConfig()
	self.Sites = {}
	local stmt = self:Prepare[[SELECT hostname, backends FROM sites]]
	for r in stmt:nrows() do
		local backends = { string.match(r.backends, "([^ ]+)") }
		local siteDef = {}
		for i, v in ipairs(backends) do
			local host, port = v:match("([0-9%.]+):?([0-9]*)")
			port = tonumber(port) or 80
			table.insert(siteDef, { host, port })
		end
		self.Sites[r.hostname] = siteDef
	end
	stmt:finalize()

	self.Rules = {}
	stmt = self:Prepare[[SELECT hostname, rule, ip FROM rules]]
	for r in stmt:nrows() do
		table.insert(self.Rules, r)
	end
	stmt:finalize()
end

function System:MatchRule(req)
	for i, rule in ipairs(self.Rules) do
		if rule.hostname == req.headers.host and
		   req.resource:find(rule.rule) and
		   req.peername:find(rule.ip) then
		   	return rule
		end
	end
end

System:ReloadConfig()

HTTP.ListenAll(80, function(req, res)
	HTTP.Logger:saveRequest(req)
	local rule = System:MatchRule(req)
	if rule then
		return res:displayError(403)
	end
	if System.Sites[req.headers.host] then
		local site = System.Sites[req.headers.host]
		local backend = site[math.random(1, #site)]
		HTTP.ForwardRequest(req, res, backend[1], backend[2])
	else
		res:displayError(401)
	end
end)

HTTP.ListenAll(8080, CP)

os.execute("START http://127.0.0.1:8080/")

HTTP.core.run()