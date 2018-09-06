local function prepare_stmt(sql)
	return HTTP.Logger:Prepare(sql)
end

local function htmlFilter(str)
	return str:gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;"})
end

HTTP.Logger:ExecSQL[[
CREATE TABLE IF NOT EXISTS sites(
hostname VARCHAR(120) PRIMARY KEY,
backends TEXT NOT NULL);]]

HTTP.Logger:ExecSQL[[CREATE TABLE IF NOT EXISTS rules(
id INTEGER PRIMARY KEY,
hostname VARCHAR(120) NOT NULL,
rule TEXT NOT NULL,
ip VARCHAR(120) NOT NULL,
operation VARCHAR(120) DEFAULT 'allow');]]

function logs()
	local stmt
	local _logs = {}
	pageBase = "/page/2?base=" .. os.time()
	if params.ip then
		stmt = prepare_stmt[[SELECT * FROM requests WHERE peername = ? ORDER BY id DESC LIMIT 60 OFFSET 0]]
		stmt:bind_values(params.ip)
		pageTitle = "来自 " .. params.ip .. " 的最新请求"
		pageBase = pageBase .. "&ip=" .. params.ip
	elseif params.host then
		stmt = prepare_stmt[[SELECT * FROM requests WHERE hostname = ? ORDER BY id DESC LIMIT 60 OFFSET 0]]
		stmt:bind_values(params.host)
		pageTitle = "对 " .. params.host .. " 的最新请求"
		pageBase = pageBase .. "&host=" .. params.host
	elseif params.xff then
		if params.xff == "spider" then
		    stmt = prepare_stmt[[SELECT * FROM requests WHERE id IN (SELECT req_id FROM meta WHERE m_id = 2049 AND mval LIKE '%Baiduspider%') ORDER BY id DESC LIMIT 60 OFFSET 0]]
		    pageTitle = "来自百度蜘蛛的最新请求"
		    noPagination = true
		else
		    stmt = prepare_stmt[[SELECT * FROM requests WHERE peername = ? OR id IN (SELECT req_id FROM meta WHERE m_id = 2050 AND mval = ?) ORDER BY id DESC LIMIT 60 OFFSET 0]]
		    stmt:bind_values(params.xff, params.xff)
		    pageTitle = "转发自 " .. params.xff .. " 的请求"
		    pageBase = pageBase .. "&xff=" .. params.xff
		end
	else
		stmt = prepare_stmt[[SELECT COUNT(id) FROM requests]]
		if sqlite3.ROW == stmt:step() then
			local count = stmt:get_value(0)
			logCount = "共 " .. count .. [[ 条日志]]
		end
		stmt:finalize()
		stmt = prepare_stmt[[SELECT * FROM requests ORDER BY id DESC LIMIT 60 OFFSET 0]]
		pageTitle = "最新 60 条请求"
	end
	for r in stmt:nrows() do
		_logs[#_logs + 1] = { date = os.date("%y-%m-%d %H:%M:%S", r.ostime), host = r.hostname,
			ip = r.peername, id = r.id, verb = r.method, res = htmlFilter(r.resource) }
	end
	stmt:finalize()
	Requests = _logs
end

function sites()
	Sites = {}
	stmt = prepare_stmt[[SELECT hostname, backends FROM sites]]
	for r in stmt:nrows() do
		table.insert(Sites, { hostname = r.hostname, backends = r.backends })
	end
	stmt:finalize()
end

function save_site()
	stmt = prepare_stmt[[INSERT OR REPLACE INTO sites(hostname, backends) VALUES(?, ?)]]
	stmt:bind_values(params.siteDomain, params.backends)
	stmt:step()
	System:ReloadConfig()
	redirect_to "/sites"
end

function delete_site()
	stmt = prepare_stmt[[DELETE FROM sites WHERE hostname = ?]]
	stmt:bind_values(params.site)
	stmt:step()
	System:ReloadConfig()
	redirect_to "/sites"
end

function rules()
	Rules = {}
	stmt = prepare_stmt[[SELECT id, hostname, rule, ip FROM rules]]
	for r in stmt:nrows() do
		table.insert(Rules, { id = r.id, hostname = r.hostname, rule = r.rule, ip = r.ip })
	end
	stmt:finalize()
end

function delete_rule()
	stmt = prepare_stmt[[DELETE FROM rules WHERE id = ?]]
	stmt:bind_values(tonumber(params.id))
	stmt:step()
	System:ReloadConfig()
	redirect_to "/rules"
end

function save_rule()
	stmt = prepare_stmt[[INSERT INTO rules(hostname, rule, ip) VALUES(?, ?, ?)]]
	stmt:bind_values(params.siteDomain, params.rule, params.forIP)
	stmt:step()
	System:ReloadConfig()
	redirect_to "/rules"
end

function detail()
	local logid = assert(tonumber(params.id), "no log ID specified")
	local stmt = prepare_stmt[[SELECT ostime, hostname, method, resource, peername FROM requests WHERE id = ?]]
	stmt:bind_values(logid)
	if sqlite3.ROW ~= stmt:step() then
		stmt:finalize()
		error("no such log item")
	end
	logId = logid
	local host, method, resource, peername = stmt:get_value(1), stmt:get_value(2), stmt:get_value(3), stmt:get_value(4)
	logMeta = os.date("%y-%m-%d %H:%M:%S ", stmt:get_value(0)) .. host
	peerName = peername
	reqRes = method .. " " .. htmlFilter(resource)
	stmt:finalize()
	pageTitle = ("日志 #%d 详情"):format(logid)

	stmt = prepare_stmt[[SELECT m_id, mval FROM meta WHERE req_id == ?]]
	stmt:bind_values(logid)
	for id, val in stmt:urows() do
		if id == 0x801 then
			reqUA = val:gsub("^M/", "Mozilla/")
		elseif id == 0x802 then
			forFor = val
		elseif id == 0x803 then
			reqRef = val
		end
	end
	stmt:finalize()
end

function paged()
	local base = tonumber(params.base) or os.time()
	local page = tonumber(params.page) or 1
	local offset = (page - 1) * 30
	local stmt
	local _logs, _navbar, nlog, limit = {}, {}, 0, "base=" .. tostring(base)
	if params.ip then
		if params.ip == "current" then
			stmt = prepare_stmt[[SELECT * FROM requests WHERE peername = ? AND ostime <= ? ORDER BY id DESC LIMIT 30 OFFSET ?]]
			stmt:bind_values(request.peername, base, offset)
			pageTitle = "来自当前 IP 地址的请求"
			limit = limit .. "&ip=current"
		else
			stmt = prepare_stmt[[SELECT * FROM requests WHERE peername = ? AND ostime <= ? ORDER BY id DESC LIMIT 30 OFFSET ?]]
			stmt:bind_values(params.ip, base, offset)
			pageTitle = "来自 " ..  params.ip .. " 的请求"
			limit = limit .. "&ip=" ..  params.ip
		end
	elseif params.host then
		stmt = prepare_stmt[[SELECT * FROM requests WHERE hostname = ? AND ostime <= ? ORDER BY id DESC LIMIT 30 OFFSET ?]]
		stmt:bind_values(params.host, base, offset)
		pageTitle = "对 " .. params.host .. " 的请求"
		limit = limit .. "&host=" .. params.host
	elseif params.xff then
		stmt = prepare_stmt[[SELECT * FROM requests WHERE peername = ? OR id IN (SELECT req_id FROM meta WHERE m_id = 2050 AND mval = ?) AND ostime <= ? ORDER BY id DESC LIMIT 30 OFFSET ?]]
		stmt:bind_values(params.xff, params.xff, base, offset)
		pageTitle = "转发自 " .. params.xff .. " 的请求"
		limit = limit .. "&xff=" .. params.xff
	else
		stmt = prepare_stmt[[SELECT * FROM requests WHERE peername != ? AND ostime <= ? ORDER BY id DESC LIMIT 30 OFFSET ?]]
		stmt:bind_values(request.peername, base, offset)
		pageTitle = "截止 " .. os.date("%m月%d日 %H:%M", base) .. " 的请求"
	end
	for r in stmt:nrows() do
		_logs[#_logs + 1] = { date = os.date("%y-%m-%d %H:%M:%S", r.ostime), host = r.hostname,
			ip = r.peername, id = r.id, verb = r.method, res = htmlFilter(r.resource) }
		nlog = nlog + 1
	end
	stmt:finalize()
	if page > 1 then _navbar[#_navbar + 1] = ([[<a href="/page/%d?%s">&lt; 上一页</a>]]):format(page - 1, limit) end
	if nlog == 30 then _navbar[#_navbar + 1] = ([[<a href="/page/%d?%s">下一页 &gt;</a>]]):format(page + 1, limit) end
	Navigate = table.concat(_navbar, " | ")
	Requests, pageNo = _logs, page
end

