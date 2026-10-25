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

    it("should not open a dictionary without a bookname, as sdcv", function()
        local dict, err = StarDict.open(FIXTURES .. "/other/nobook.ifo")
        assert.is_nil(dict)
        assert.are.equal("no bookname", err)
    end)
end)
