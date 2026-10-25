local http = require("socket.http")
local socket = require("socket")
local socketutil = require("socketutil")
local url = require("socket.url")

local OPDSClient = {}
OPDSClient.__index = OPDSClient

local redirect_codes = {
    [301] = true,
    [302] = true,
    [303] = true,
    [307] = true,
    [308] = true,
}

local default_ports = {
    http = 80,
    https = 443,
}

local function isIdempotentRequest(method)
    return method == nil or method == "GET" or method == "HEAD"
end

local function origin(u)
    local parsed = url.parse(u or "")
    if not parsed or not parsed.scheme or not parsed.host or parsed.host == "" then return end
    local scheme = parsed.scheme:lower()
    if not default_ports[scheme] then return end
    if parsed.port == "" then parsed.port = nil end
    local port = parsed.port and tonumber(parsed.port) or default_ports[scheme]
    if parsed.port and not parsed.port:match("^%d+$") then return end
    if not port or port < 1 or port > 65535 then return end
    return { scheme = scheme, host = parsed.host:lower(), port = port }
end

--- Whether two HTTP(S) URLs have the same scheme, host and effective port.
-- Invalid origins never receive credentials, even when both URLs are identical.
function OPDSClient.isSameOrigin(left_url, right_url)
    local left, right = origin(left_url), origin(right_url)
    return left ~= nil and right ~= nil
        and left.scheme == right.scheme
        and left.host == right.host
        and left.port == right.port
end

local function isHttpsDowngrade(from_url, to_url)
    return (url.parse(from_url).scheme or ""):lower() == "https"
        and (url.parse(to_url).scheme or ""):lower() == "http"
end

function OPDSClient:new(options)
    return setmetatable(options, self)
end

function OPDSClient:request(request)
    local request_url = request.url
    local original_headers = request.headers or {}

    for _ = 1, 5 do
        local headers = {}
        for name, value in pairs(original_headers) do
            if name:lower() ~= "cookie" then headers[name] = value end
        end
        local cookies = self.cookie_jar:headerFor(request_url)
        if cookies then headers.Cookie = cookies end

        local same_origin = OPDSClient.isSameOrigin(request_url, request.url)
        -- like Basic auth, auth_headers (e.g. Cloudflare Access tokens) only go to the original origin
        if same_origin then
            for name, value in pairs(request.auth_headers or {}) do headers[name] = value end
        end
        local function makeRequest()
            return socket.skip(1, http.request {
                url = request_url,
                method = request.method,
                headers = headers,
                sink = request.sink,
                user = same_origin and request.username or nil,
                password = same_origin and request.password or nil,
                redirect = false,
                response_headers = function(response_code)
                    return redirect_codes[response_code]
                end,
            })
        end

        local code, response_headers, status = makeRequest()
        if code == socketutil.SSL_HANDSHAKE_CODE and isIdempotentRequest(request.method) then
            code, response_headers, status = makeRequest()
        end
        self.cookie_jar:store(request_url, response_headers)

        if not redirect_codes[code] or not response_headers or not response_headers.location then
            return code, response_headers, status
        end

        local redirected_url = url.absolute(request_url, response_headers.location)
        if isHttpsDowngrade(request_url, redirected_url) then
            return code, response_headers, status
        end
        request_url = redirected_url
    end

    return nil, nil, "Too many redirects"
end

return OPDSClient
