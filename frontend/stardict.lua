--[[--
Reads StarDict dictionaries in process, for platforms that cannot run sdcv (iOS).

Lookups give what `sdcv --exact-search --json-output` gives for one dictionary: entries whose headword or
synonym is the word byte for byte, in index order, their definitions rendered as sdcv renders them.
Supports .idx and .idx.gz (32 or 64 bit offsets), .syn, .dict and dictzip .dict.dz.

Read in Lua rather than sdcv linked in as a library: no C++ or glib in the iOS build, and the zlib that base
already loads is all it needs.

The index is read on the first lookup in a dictionary and kept for the session: one buffer, scanned with
memchr, the entry starts in an uint32_t array, so that it does not make a Lua string per entry (LuaJIT runs
without JIT on iOS).

@module stardict
]]

local Utf8Proc = require("ffi/utf8proc")
local bit = require("bit")
local ffi = require("ffi")
local C = ffi.C
local logger = require("logger")
local time = require("ui/time")
local util = require("util")

require("ffi/posix_h")

ffi.cdef[[
typedef struct ko_stardict_z_stream {
    const char *next_in;
    unsigned avail_in;
    unsigned long total_in;
    unsigned char *next_out;
    unsigned avail_out;
    unsigned long total_out;
    const char *msg;
    void *state;
    void *zalloc;
    void *zfree;
    void *opaque;
    int data_type;
    unsigned long adler;
    unsigned long reserved;
} ko_stardict_z_stream;
const char *zlibVersion(void);
int inflateInit2_(ko_stardict_z_stream *, int, const char *, int);
int inflate(ko_stardict_z_stream *, int);
int inflateEnd(ko_stardict_z_stream *);
]]

local libz = ffi.loadlib("z", 1)

local Z_OK, Z_STREAM_END, Z_SYNC_FLUSH = 0, 1, 2
local RAW_DEFLATE, GZIP = -15, 31 -- inflateInit2 window bits

local u8p = ffi.typeof("const uint8_t *")

--- Inflates data (a Lua string) into at most out_size bytes; nil when it fails.
local function inflate(data, out_size, window_bits)
    local strm = ffi.new("ko_stardict_z_stream")
    if libz.inflateInit2_(strm, window_bits, libz.zlibVersion(), ffi.sizeof(strm)) ~= Z_OK then return end
    local out = ffi.new("uint8_t[?]", out_size)
    strm.next_in, strm.avail_in = data, #data
    strm.next_out, strm.avail_out = out, out_size
    -- a dictzip chunk ends with a full flush, not the end of the stream
    local ret = libz.inflate(strm, Z_SYNC_FLUSH)
    local len = out_size - strm.avail_out
    libz.inflateEnd(strm)
    if ret ~= Z_OK and ret ~= Z_STREAM_END then return end
    return out, len
end

local function be32(p)
    return ((p[0] * 256 + p[1]) * 256 + p[2]) * 256 + p[3]
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return end
    local data = f:read("*a")
    f:close()
    return data
end

local function lowerAscii(c)
    if c >= 65 and c <= 90 then return c + 32 end
    return c
end

--- sdcv's stardict_strcmp(word, key), the order of .idx and .syn: g_ascii_strcasecmp, then strcmp.
-- word: uint8_t pointer and length (no NUL inside); key: NUL-terminated uint8_t pointer
local function compare(w, wlen, k)
    local tie = 0
    local i = 0
    while true do
        local a = i < wlen and w[i] or 0
        local b = k[i]
        local la, lb = lowerAscii(a), lowerAscii(b)
        if la ~= lb then return la - lb end
        if tie == 0 then tie = a - b end
        if a == 0 then return tie end
        i = i + 1
    end
end

--- An index (.idx or .syn) in a buffer: its entry starts, each a NUL-terminated key then `tail` bytes.
local Index = {}
Index.__index = Index

function Index.new(buf, size, tail, count)
    local starts = ffi.new("uint32_t[?]", math.max(count, 1))
    local n, pos = 0, 0
    while n < count and pos < size do
        local nul = C.memchr(buf + pos, 0, size - pos)
        if nul == nil then break end
        starts[n] = pos
        n = n + 1
        pos = tonumber(ffi.cast(u8p, nul) - buf) + 1 + tail
    end
    return setmetatable({ buf = buf, size = size, starts = starts, n = n }, Index)
end

function Index:key(i)
    return self.buf + self.starts[i]
end

--- Pointer to the bytes after entry i's key.
function Index:tail(i)
    local start = self.starts[i]
    return ffi.cast(u8p, C.memchr(self.buf + start, 0, self.size - start)) + 1
end

--- Entry numbers whose key is word, as sdcv's lookup: all of them, when an index has the key more than once.
function Index:find(word)
    local w, wlen = ffi.cast(u8p, word), #word
    local lo, hi = 0, self.n
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if compare(w, wlen, self:key(mid)) > 0 then lo = mid + 1 else hi = mid end
    end
    local found = {}
    while lo < self.n and compare(w, wlen, self:key(lo)) == 0 do
        table.insert(found, lo)
        lo = lo + 1
    end
    return found
end

local StarDict = {}
StarDict.__index = StarDict

local opened = {} -- by .ifo path

local function parseIfo(content)
    local ifo = {}
    for k, v in content:gmatch("([%w_]+)=([^\r\n]*)") do
        ifo[k] = v
    end
    return ifo
end

--- Opens the dictionary of an .ifo file; nil and a reason when it is not usable (sdcv needs a bookname).
function StarDict.open(ifo_file)
    if opened[ifo_file] then return opened[ifo_file] end
    local content = readFile(ifo_file)
    if not content then return nil, "unreadable .ifo" end
    local ifo = parseIfo(content)
    if not ifo.bookname then return nil, "no bookname" end
    local base = ifo_file:gsub("%.ifo$", "")
    local dict = setmetatable({
        name = ifo.bookname,
        base = base,
        wordcount = tonumber(ifo.wordcount) or 0,
        synwordcount = tonumber(ifo.synwordcount) or 0,
        idxfilesize = tonumber(ifo.idxfilesize),
        offset_bytes = ifo.idxoffsetbits == "64" and 8 or 4,
        sametypesequence = ifo.sametypesequence ~= "" and ifo.sametypesequence or nil,
    }, StarDict)
    if util.fileExists(base .. ".dict.dz") then -- sdcv prefers it too
        dict.dz_file = base .. ".dict.dz"
    elseif util.fileExists(base .. ".dict") then
        dict.dict_file = base .. ".dict"
    else
        return nil, "no .dict or .dict.dz"
    end
    opened[ifo_file] = dict
    return dict
end

--- Reads the .idx (and .syn) on the first lookup.
function StarDict:loadIndex()
    if self.idx then return end
    local start_time = time.now()
    local data = readFile(self.base .. ".idx")
    local buf, size
    if data then
        buf, size = ffi.cast(u8p, data), #data
        self.idx_data = data -- buf points into it
    else
        local gz = readFile(self.base .. ".idx.gz")
        if gz and self.idxfilesize then
            local out
            out, size = inflate(gz, self.idxfilesize, GZIP)
            self.idx_data = out -- buf points into it
            buf = out and ffi.cast(u8p, out)
        end
    end
    if not buf then error("no readable .idx or .idx.gz") end
    self.idx = Index.new(buf, size, self.offset_bytes + 4, self.wordcount)
    local syn = self.synwordcount > 0 and readFile(self.base .. ".syn")
    if syn then
        self.syn_data = syn
        self.syn = Index.new(ffi.cast(u8p, syn), #syn, 4, self.synwordcount)
    end
    logger.dbg("stardict: indexed", self.name, self.idx.n, "words", self.syn and self.syn.n or 0, "synonyms in",
        time.to_ms(time.since(start_time)), "ms")
end

--- The dictzip header: chunk length, and each chunk's compressed size and offset.
function StarDict:loadDictzip()
    if self.dz then return end
    local f = assert(io.open(self.dz_file, "rb"))
    local head = f:read(65536 + 12) or ""
    local p = ffi.cast(u8p, head)
    if #head < 12 or p[0] ~= 0x1f or p[1] ~= 0x8b or bit.band(p[3], 4) == 0 then
        f:close()
        error("not a dictzip file") -- ponytail: plain gzip .dict.dz (no random access chunks) is not supported
    end
    local flags = p[3]
    local xlen = p[10] + p[11] * 256
    local pos, extra_end = 12, 12 + xlen
    local chunk_len, count, sizes
    while pos + 4 <= extra_end do -- subfields: id (2), length (2, LE), data
        local len = p[pos + 2] + p[pos + 3] * 256
        if p[pos] == 82 and p[pos + 1] == 65 then -- "RA": version (2), chunk length (2), count (2), sizes (2 each)
            chunk_len = p[pos + 6] + p[pos + 7] * 256
            count = p[pos + 8] + p[pos + 9] * 256
            sizes = {}
            for i = 0, count - 1 do
                sizes[i] = p[pos + 10 + 2 * i] + p[pos + 11 + 2 * i] * 256
            end
        end
        pos = pos + 4 + len
    end
    if not chunk_len then
        f:close()
        error("dictzip header without chunks")
    end
    pos = extra_end
    if bit.band(flags, 8) ~= 0 then pos = head:find("\0", pos + 1, true) end -- name
    if bit.band(flags, 16) ~= 0 then pos = head:find("\0", pos + 1, true) end -- comment
    if bit.band(flags, 2) ~= 0 then pos = pos + 2 end -- header crc
    local offsets, offset = {}, pos
    for i = 0, count - 1 do
        offsets[i] = offset
        offset = offset + sizes[i]
    end
    f:close()
    self.dz = { chunk_len = chunk_len, sizes = sizes, offsets = offsets }
end

--- size bytes of the uncompressed dictionary at offset.
function StarDict:readData(offset, size)
    if self.dict_file then
        local f = assert(io.open(self.dict_file, "rb"))
        f:seek("set", offset)
        local data = f:read(size)
        f:close()
        return data or ""
    end
    self:loadDictzip()
    local dz = self.dz
    local first, last = math.floor(offset / dz.chunk_len), math.floor((offset + size - 1) / dz.chunk_len)
    local f = assert(io.open(self.dz_file, "rb"))
    local parts = {}
    for c = first, last do
        f:seek("set", dz.offsets[c])
        local out, len = inflate(f:read(dz.sizes[c]) or "", dz.chunk_len, RAW_DEFLATE)
        if not out then
            f:close()
            error("corrupt dictzip chunk " .. c)
        end
        table.insert(parts, ffi.string(out, len))
    end
    f:close()
    local skip = offset - first * dz.chunk_len
    return table.concat(parts):sub(skip + 1, skip + size)
end

--- sdcv's xdxf2text, without colors: <k> headwords dropped, <tr> as [...], other tags dropped, entities decoded.
local ENTITIES = { gt = ">", lt = "<", amp = "&", quot = '"', apos = "'" }
local function xdxfToText(s)
    s = s:gsub("<k>.-</k>", ""):gsub("<tr>", "["):gsub("</tr>", "]"):gsub("<[^>]*>", "")
    return (s:gsub("&(%a+);", function(e) return ENTITIES[e] end))
end

--- An entry's data as sdcv's parse_data renders it: "\n" then the text of each text field.
function StarDict:render(data)
    local fields = {} -- { type, value }
    local pos, len = 1, #data
    local seq = self.sametypesequence
    local i = 0
    while pos <= len do
        i = i + 1
        local t
        if seq then
            t = seq:sub(i, i)
            if t == "" then break end
        else
            t = data:sub(pos, pos)
            pos = pos + 1
        end
        local value
        if seq and i == #seq then -- the last field of a sametypesequence has no terminator or size
            value, pos = data:sub(pos), len + 1
        elseif t:match("%l") then
            local nul = data:find("\0", pos, true) or len + 1
            value, pos = data:sub(pos, nul - 1), nul + 1
        else
            local size = pos + 3 <= len and be32(ffi.cast(u8p, data) + pos - 1) or 0
            value, pos = data:sub(pos + 4, pos + 3 + size), pos + 4 + size
        end
        table.insert(fields, { t, value })
    end
    local out = {}
    for _, field in ipairs(fields) do
        local t, v = field[1], field[2]
        if v ~= "" then
            if t == "h" or t == "w" or t == "m" or t == "l" then
                table.insert(out, "\n" .. v)
            elseif t == "g" or t == "x" then
                table.insert(out, "\n" .. xdxfToText(v))
            elseif t == "t" then
                table.insert(out, "\n[" .. v .. "]")
            elseif t == "k" or t == "y" then
                table.insert(out, v)
            end
        end
    end
    return table.concat(out)
end

--- Entry numbers for word: its .syn and .idx entries, in index order (sdcv's Dict::Lookup).
function StarDict:find(word)
    local set = {}
    for _, i in ipairs(self.idx:find(word)) do set[i] = true end
    if self.syn then
        for _, s in ipairs(self.syn:find(word)) do set[be32(self.syn:tail(s))] = true end
    end
    local found = {}
    for i in pairs(set) do table.insert(found, i) end
    table.sort(found)
    return found
end

--- Entries for word, as { word = headword, definition = text }.
-- similar: when the word has none, try its case variants, as sdcv does without --exact-search
-- (ponytail: sdcv's English suffix stripping and edit distance matches are not done)
function StarDict:lookup(word, similar)
    self:loadIndex()
    local found = self:find(word)
    if #found == 0 and similar then
        local first = word:match("^" .. util.UTF8_CHAR_PATTERN) or ""
        local variants = {
            Utf8Proc.lowercase_dumb(word),
            Utf8Proc.uppercase_dumb(word),
            Utf8Proc.uppercase_dumb(first) .. Utf8Proc.lowercase_dumb(word:sub(#first + 1)),
        }
        for _, variant in ipairs(variants) do
            if variant ~= word then
                found = self:find(variant)
                if #found > 0 then break end
            end
        end
    end
    local entries = {}
    for _, i in ipairs(found) do
        local tail = self.idx:tail(i)
        local offset = be32(tail)
        if self.offset_bytes == 8 then
            offset = offset * 2^32 + be32(tail + 4)
        end
        local size = be32(tail + self.offset_bytes)
        table.insert(entries, {
            word = ffi.string(self.idx:key(i)),
            definition = self:render(self:readData(offset, size)),
        })
    end
    return entries
end

return StarDict
