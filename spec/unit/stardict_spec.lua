describe("StarDict module", function()
    local StarDict
    local FIXTURES = "spec/front/unit/fixtures/stardict"

    setup(function()
        require("commonrequire")
        StarDict = require("stardict")
    end)

    local function lookup(dict, word, similar)
        local out = {}
        for i, entry in ipairs(dict:lookup(word, similar)) do
            out[i] = { entry.word, entry.definition }
        end
        return out
    end

    describe("with a dictzip dictionary of one type, with synonyms", function()
        local demo
        setup(function()
            demo = assert(StarDict.open(FIXTURES .. "/demo/demo.ifo"))
        end)

        it("should be named by its bookname", function()
            assert.are.equal("Demo", demo.name)
        end)

        it("should find a word byte for byte, its definition read across dictzip chunks", function()
            -- 46 bytes in 32 byte chunks
            assert.are.same({ { "apple", "\nn. a round fruit of a tree of the rose family" } }, lookup(demo, "apple"))
            assert.are.same({ { "Apple", "\nn. the company" } }, lookup(demo, "Apple"))
            assert.are.same({ { "zebra", "\nn. a striped animal" } }, lookup(demo, "zebra"))
            assert.are.same({ { "经典", "\nn. 具有典范性、权威性的著作" } }, lookup(demo, "经典"))
        end)

        it("should find every entry of a headword, in index order", function()
            assert.are.same({
                { "run", "\nv. to move swiftly on foot" },
                { "run", "\nn. an act of running" },
            }, lookup(demo, "run"))
        end)

        it("should find the entry of a synonym under its headword", function()
            assert.are.same({ { "run", "\nv. to move swiftly on foot" } }, lookup(demo, "ran"))
            assert.are.same({ { "run", "\nv. to move swiftly on foot" } }, lookup(demo, "runs"))
        end)

        it("should find nothing for other words, or other cases unless asked for similar words", function()
            assert.are.same({}, lookup(demo, "nothing"))
            assert.are.same({}, lookup(demo, "a"))
            assert.are.same({}, lookup(demo, "zzz"))
            assert.are.same({}, lookup(demo, "APPLE"))
            -- as sdcv without --exact-search: lowercase first
            assert.are.same({ { "apple", "\nn. a round fruit of a tree of the rose family" } }, lookup(demo, "APPLE", true))
            assert.are.same({ { "zebra", "\nn. a striped animal" } }, lookup(demo, "ZEBRA", true))
        end)
    end)

    describe("with typed fields, 64 bit offsets, a gzipped index and a plain .dict", function()
        local other
        setup(function()
            other = assert(StarDict.open(FIXTURES .. "/other/other.ifo"))
        end)

        it("should render the fields as sdcv: phonetic in brackets, XDXF as text, binary fields skipped", function()
            assert.are.same({ { "apple", "\n[ˈæpl]\na fruit\n[x] <b>" } }, lookup(other, "apple"))
            assert.are.same({ { "pear", "\nanother fruit" } }, lookup(other, "pear"))
        end)
    end)

    describe("with corrupt or truncated files", function()
        local dir
        setup(function()
            dir = require("datastorage"):getDataDir() .. "/stardict_spec"
            require("util").makePath(dir)
        end)
        teardown(function()
            require("ffi/util").purgeDir(dir)
        end)

        local function be32(n)
            return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
        end
        local function le16(n)
            return string.char(n % 256, math.floor(n / 256))
        end
        local function entry(word, offset, size)
            return word .. "\0" .. be32(offset) .. be32(size)
        end
        -- writes name's files (by extension) and opens it
        local function open(name, files)
            for ext, content in pairs(files) do
                local f = assert(io.open(dir .. "/" .. name .. ext, "wb"))
                f:write(content)
                f:close()
            end
            return assert(StarDict.open(dir .. "/" .. name .. ".ifo"))
        end
        local function ifo(fields)
            return "StarDict's dict ifo file\nversion=3.0.0\nbookname=Bad\nsametypesequence=m\n" .. fields
        end

        it("should skip a synonym pointing past the index", function()
            local dict = open("badsyn", {
                [".ifo"] = ifo("wordcount=1\nsynwordcount=1\n"),
                [".idx"] = entry("a", 0, 1),
                [".dict"] = "x",
                [".syn"] = "ran\0\127\255\255\255",
            })
            assert.are.same({}, lookup(dict, "ran"))
            assert.are.same({ { "a", "\nx" } }, lookup(dict, "a"))
        end)

        it("should drop an index entry truncated in its offset and size", function()
            local dict = open("cutidx", {
                [".ifo"] = ifo("wordcount=2\n"),
                [".idx"] = entry("a", 0, 1) .. "b\0\0\0\0",
                [".dict"] = "xy",
            })
            assert.are.same({}, lookup(dict, "b"))
            assert.are.same({ { "a", "\nx" } }, lookup(dict, "a"))
        end)

        it("should fail on a dictzip header longer than the file, or with more chunks than its RA field holds", function()
            local gzip = "\31\139\8\4\0\0\0\0\2\3"
            local dict = open("cutdz", {
                [".ifo"] = ifo("wordcount=1\n"),
                [".idx"] = entry("a", 0, 1),
                [".dict.dz"] = gzip .. le16(65535) .. "RA",
            })
            assert.has_error(function() dict:lookup("a") end)
            local ra = le16(1) .. le16(32) .. le16(100) -- 100 chunks, no sizes
            dict = open("baddz", {
                [".ifo"] = ifo("wordcount=1\n"),
                [".idx"] = entry("a", 0, 1),
                [".dict.dz"] = gzip .. le16(4 + #ra) .. "RA" .. le16(#ra) .. ra,
            })
            assert.has_error(function() dict:lookup("a") end)
        end)
    end)

    it("should not open a dictionary without a bookname, as sdcv", function()
        local dict, err = StarDict.open(FIXTURES .. "/other/nobook.ifo")
        assert.is_nil(dict)
        assert.are.equal("no bookname", err)
    end)
end)
