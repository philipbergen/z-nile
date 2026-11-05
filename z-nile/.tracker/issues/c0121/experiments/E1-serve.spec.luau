--!strict
-- c0121 experiments E1-E4, run under the real runner (the jail on macOS): can a spec bind net.serve to 127.0.0.1 on a
-- random port, reach it with net.request, see Host and Origin as sent, and run a subprocess in one handler while
-- another answers? And what does the handle report for port 0?
local net = require("@lune/net")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

local function serve(handler: (net.ServeRequest) -> net.ServeResponse): (number, () -> ())
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, handle =
			pcall(net.serve, port, { address = "http://127.0.0.1", handleRequest = handler :: any })
		if ok then
			return port, function()
				(handle :: any).stop()
			end
		end
	end
	error("no free port in 30 tries")
end

return t.spec("c0121 experiments", function(it)
	it("E1 binds 127.0.0.1 on a random port inside the jail and answers net.request", function()
		local port, stop = serve(function(req)
			return { status = 200, body = `{req.method} {req.path}` }
		end)
		local r = net.request(`http://127.0.0.1:{port}/api/state`)
		stop()
		t.expect(r.statusCode).toBe(200)
		t.expect(r.body).toBe("GET /api/state")
	end)

	it(
		"E2 the handler sees Host and Origin exactly as a rebinding page or a foreign site sends them",
		function()
			local seen: { [string]: string } = {}
			local port, stop = serve(function(req)
				seen.host = req.headers.host or ""
				seen.origin = req.headers.origin or ""
				seen.token = req.headers["x-zn-token"] or ""
				return { status = 200, body = "ok" }
			end)
			-- net.request rewrites Host from the URL, so a rebinding request is sent raw over TCP
			local conn = net.tcp.connect("127.0.0.1", port)
			conn:write(
				"POST /api/stop HTTP/1.1\r\nHost: evil.example\r\nOrigin: http://evil.example\r\nX-Zn-Token: abc\r\n"
					.. "Content-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
			)
			local reply = conn:read() or ""
			conn:close()
			stop()
			print("E2 raw reply:", (string.match(reply, "^[^\r\n]*")))
			print("E2 seen", seen.host, seen.origin, seen.token)
			t.expect(seen.host).toBe("evil.example")
			t.expect(seen.origin).toBe("http://evil.example")
			t.expect(seen.token).toBe("abc")
		end
	)

	it("E3 a handler running a subprocess does not block another request", function()
		local port, stop = serve(function(req)
			if req.path == "/slow" then
				process.exec("sleep", { "1" })
			end
			return { status = 200, body = req.path }
		end)
		local slowDone = false
		task.spawn(function()
			net.request(`http://127.0.0.1:{port}/slow`)
			slowDone = true
		end)
		task.wait(0.1)
		local t0 = os.clock()
		local r = net.request(`http://127.0.0.1:{port}/fast`)
		local fast = os.clock() - t0
		print("E3 fast answered while slow pending:", not slowDone, string.format("%.3fs", fast))
		t.expect(r.body).toBe("/fast")
		t.expect(slowDone).toBe(false)
		task.wait(1.2)
		stop()
	end)

	it("E4 port 0 binds but the handle cannot tell which port", function()
		local ok, handle = pcall(net.serve, 0, {
			address = "http://127.0.0.1",
			handleRequest = function()
				return { status = 200 }
			end,
		})
		print("E4 port 0:", ok, if ok then tostring((handle :: any).port) else tostring(handle))
		if ok then
			(handle :: any).stop()
		end
		t.expect(ok).toBe(true)
	end)

	it("E5 a request to a stopped server is refused, so a final case can prove the server is gone", function()
		local port, stop = serve(function()
			return { status = 200 }
		end)
		stop()
		task.wait(0.1)
		local ok = pcall(net.request, `http://127.0.0.1:{port}/`)
		print("E5 request after stop ok?", ok)
		t.expect(ok).toBe(false)
	end)
end)
