--!strict
-- StumpMeshIds (T420): the ONE table of the 96 frustum meshes a stump is
-- made of, uploaded as Model assets (all Approved). Each model holds one
-- MeshPart; SERVER-side StumpMeshes loads it with InsertService:LoadAsset and
-- keeps one template per row. A row is a radius set (R13 or R22: the
-- reference base radius its UVs were made for), a taper (the mesh's top
-- radius over its base radius, in hundredths: 85 = 0.85 ... 100 = 1.00) and
-- a native height (3, 5 or 8 studs). No other file or spec holds an id: they
-- read this table.
-- These are Model ids (LoadAsset), never MeshIds. The inner MeshIds are not
-- readable from this repo and are not recorded.
local StumpMeshIds = {}

export type Row = { name: string, set: string, taper: number, height: number, id: number }

StumpMeshIds.Sets = { "R13", "R22" } :: { string }
StumpMeshIds.Heights = { 3, 5, 8 } :: { number }

StumpMeshIds.Rows = {
	{ name = "StumpTaper085_H3", set = "R13", taper = 85, height = 3, id = 85452239242661 },
	{ name = "StumpTaper085_H5", set = "R13", taper = 85, height = 5, id = 113329107713613 },
	{ name = "StumpTaper085_H8", set = "R13", taper = 85, height = 8, id = 134567315476175 },
	{ name = "StumpTaper086_H3", set = "R13", taper = 86, height = 3, id = 89390487238965 },
	{ name = "StumpTaper086_H5", set = "R13", taper = 86, height = 5, id = 111199898714089 },
	{ name = "StumpTaper086_H8", set = "R13", taper = 86, height = 8, id = 98915788403956 },
	{ name = "StumpTaper087_H3", set = "R13", taper = 87, height = 3, id = 76887341131422 },
	{ name = "StumpTaper087_H5", set = "R13", taper = 87, height = 5, id = 70817794048024 },
	{ name = "StumpTaper087_H8", set = "R13", taper = 87, height = 8, id = 100235501945670 },
	{ name = "StumpTaper088_H3", set = "R13", taper = 88, height = 3, id = 86246819933198 },
	{ name = "StumpTaper088_H5", set = "R13", taper = 88, height = 5, id = 129188146877397 },
	{ name = "StumpTaper088_H8", set = "R13", taper = 88, height = 8, id = 89719720428551 },
	{ name = "StumpTaper089_H3", set = "R13", taper = 89, height = 3, id = 115809173029545 },
	{ name = "StumpTaper089_H5", set = "R13", taper = 89, height = 5, id = 137781140108325 },
	{ name = "StumpTaper089_H8", set = "R13", taper = 89, height = 8, id = 122996751123509 },
	{ name = "StumpTaper090_H3", set = "R13", taper = 90, height = 3, id = 101428820651126 },
	{ name = "StumpTaper090_H5", set = "R13", taper = 90, height = 5, id = 110604449312463 },
	{ name = "StumpTaper090_H8", set = "R13", taper = 90, height = 8, id = 72562548675992 },
	{ name = "StumpTaper091_H3", set = "R13", taper = 91, height = 3, id = 89519117965020 },
	{ name = "StumpTaper091_H5", set = "R13", taper = 91, height = 5, id = 84108444475676 },
	{ name = "StumpTaper091_H8", set = "R13", taper = 91, height = 8, id = 116124949875013 },
	{ name = "StumpTaper092_H3", set = "R13", taper = 92, height = 3, id = 108286612421526 },
	{ name = "StumpTaper092_H5", set = "R13", taper = 92, height = 5, id = 132727742894201 },
	{ name = "StumpTaper092_H8", set = "R13", taper = 92, height = 8, id = 79948924056738 },
	{ name = "StumpTaper093_H3", set = "R13", taper = 93, height = 3, id = 87028968044131 },
	{ name = "StumpTaper093_H5", set = "R13", taper = 93, height = 5, id = 114232018332793 },
	{ name = "StumpTaper093_H8", set = "R13", taper = 93, height = 8, id = 123735449905136 },
	{ name = "StumpTaper094_H3", set = "R13", taper = 94, height = 3, id = 116301019888044 },
	{ name = "StumpTaper094_H5", set = "R13", taper = 94, height = 5, id = 72939621592401 },
	{ name = "StumpTaper094_H8", set = "R13", taper = 94, height = 8, id = 135579236949498 },
	{ name = "StumpTaper095_H3", set = "R13", taper = 95, height = 3, id = 130235897971038 },
	{ name = "StumpTaper095_H5", set = "R13", taper = 95, height = 5, id = 135408840950735 },
	{ name = "StumpTaper095_H8", set = "R13", taper = 95, height = 8, id = 108418240501151 },
	{ name = "StumpTaper096_H3", set = "R13", taper = 96, height = 3, id = 111775957475011 },
	{ name = "StumpTaper096_H5", set = "R13", taper = 96, height = 5, id = 109364103572281 },
	{ name = "StumpTaper096_H8", set = "R13", taper = 96, height = 8, id = 133888388662308 },
	{ name = "StumpTaper097_H3", set = "R13", taper = 97, height = 3, id = 129174751019631 },
	{ name = "StumpTaper097_H5", set = "R13", taper = 97, height = 5, id = 99123509204879 },
	{ name = "StumpTaper097_H8", set = "R13", taper = 97, height = 8, id = 71103002116023 },
	{ name = "StumpTaper098_H3", set = "R13", taper = 98, height = 3, id = 73555716984608 },
	{ name = "StumpTaper098_H5", set = "R13", taper = 98, height = 5, id = 85989682390143 },
	{ name = "StumpTaper098_H8", set = "R13", taper = 98, height = 8, id = 93928365139923 },
	{ name = "StumpTaper099_H3", set = "R13", taper = 99, height = 3, id = 100435581391389 },
	{ name = "StumpTaper099_H5", set = "R13", taper = 99, height = 5, id = 126881190445324 },
	{ name = "StumpTaper099_H8", set = "R13", taper = 99, height = 8, id = 98609181739609 },
	{ name = "StumpTaper100_H3", set = "R13", taper = 100, height = 3, id = 74396634816083 },
	{ name = "StumpTaper100_H5", set = "R13", taper = 100, height = 5, id = 90788299448576 },
	{ name = "StumpTaper100_H8", set = "R13", taper = 100, height = 8, id = 132918654572762 },
	{ name = "StumpTaper085_H3_R22", set = "R22", taper = 85, height = 3, id = 121457065073043 },
	{ name = "StumpTaper085_H5_R22", set = "R22", taper = 85, height = 5, id = 80790846130007 },
	{ name = "StumpTaper085_H8_R22", set = "R22", taper = 85, height = 8, id = 130006319564111 },
	{ name = "StumpTaper086_H3_R22", set = "R22", taper = 86, height = 3, id = 74357887521298 },
	{ name = "StumpTaper086_H5_R22", set = "R22", taper = 86, height = 5, id = 72730607013996 },
	{ name = "StumpTaper086_H8_R22", set = "R22", taper = 86, height = 8, id = 117844145098056 },
	{ name = "StumpTaper087_H3_R22", set = "R22", taper = 87, height = 3, id = 100237541782047 },
	{ name = "StumpTaper087_H5_R22", set = "R22", taper = 87, height = 5, id = 133162068050402 },
	{ name = "StumpTaper087_H8_R22", set = "R22", taper = 87, height = 8, id = 115242465393155 },
	{ name = "StumpTaper088_H3_R22", set = "R22", taper = 88, height = 3, id = 97098358263718 },
	{ name = "StumpTaper088_H5_R22", set = "R22", taper = 88, height = 5, id = 132624090610155 },
	{ name = "StumpTaper088_H8_R22", set = "R22", taper = 88, height = 8, id = 100819124548792 },
	{ name = "StumpTaper089_H3_R22", set = "R22", taper = 89, height = 3, id = 131144624884178 },
	{ name = "StumpTaper089_H5_R22", set = "R22", taper = 89, height = 5, id = 135817472365013 },
	{ name = "StumpTaper089_H8_R22", set = "R22", taper = 89, height = 8, id = 129602696621401 },
	{ name = "StumpTaper090_H3_R22", set = "R22", taper = 90, height = 3, id = 98882035215548 },
	{ name = "StumpTaper090_H5_R22", set = "R22", taper = 90, height = 5, id = 80385300040220 },
	{ name = "StumpTaper090_H8_R22", set = "R22", taper = 90, height = 8, id = 111669457647473 },
	{ name = "StumpTaper091_H3_R22", set = "R22", taper = 91, height = 3, id = 124399863444304 },
	{ name = "StumpTaper091_H5_R22", set = "R22", taper = 91, height = 5, id = 74660790889054 },
	{ name = "StumpTaper091_H8_R22", set = "R22", taper = 91, height = 8, id = 138190035809004 },
	{ name = "StumpTaper092_H3_R22", set = "R22", taper = 92, height = 3, id = 138825753835798 },
	{ name = "StumpTaper092_H5_R22", set = "R22", taper = 92, height = 5, id = 99409811053342 },
	{ name = "StumpTaper092_H8_R22", set = "R22", taper = 92, height = 8, id = 78792859266257 },
	{ name = "StumpTaper093_H3_R22", set = "R22", taper = 93, height = 3, id = 111130362180356 },
	{ name = "StumpTaper093_H5_R22", set = "R22", taper = 93, height = 5, id = 96991959405255 },
	{ name = "StumpTaper093_H8_R22", set = "R22", taper = 93, height = 8, id = 80409164644922 },
	{ name = "StumpTaper094_H3_R22", set = "R22", taper = 94, height = 3, id = 85381860826401 },
	{ name = "StumpTaper094_H5_R22", set = "R22", taper = 94, height = 5, id = 124440444339111 },
	{ name = "StumpTaper094_H8_R22", set = "R22", taper = 94, height = 8, id = 95763014160432 },
	{ name = "StumpTaper095_H3_R22", set = "R22", taper = 95, height = 3, id = 109933451024426 },
	{ name = "StumpTaper095_H5_R22", set = "R22", taper = 95, height = 5, id = 96198302701000 },
	{ name = "StumpTaper095_H8_R22", set = "R22", taper = 95, height = 8, id = 100947728555837 },
	{ name = "StumpTaper096_H3_R22", set = "R22", taper = 96, height = 3, id = 118095685493987 },
	{ name = "StumpTaper096_H5_R22", set = "R22", taper = 96, height = 5, id = 103033634005820 },
	{ name = "StumpTaper096_H8_R22", set = "R22", taper = 96, height = 8, id = 117909986194425 },
	{ name = "StumpTaper097_H3_R22", set = "R22", taper = 97, height = 3, id = 108358413828311 },
	{ name = "StumpTaper097_H5_R22", set = "R22", taper = 97, height = 5, id = 104065751165695 },
	{ name = "StumpTaper097_H8_R22", set = "R22", taper = 97, height = 8, id = 130333821005571 },
	{ name = "StumpTaper098_H3_R22", set = "R22", taper = 98, height = 3, id = 110741020401457 },
	{ name = "StumpTaper098_H5_R22", set = "R22", taper = 98, height = 5, id = 99629736583619 },
	{ name = "StumpTaper098_H8_R22", set = "R22", taper = 98, height = 8, id = 114749980163775 },
	{ name = "StumpTaper099_H3_R22", set = "R22", taper = 99, height = 3, id = 74826489978515 },
	{ name = "StumpTaper099_H5_R22", set = "R22", taper = 99, height = 5, id = 90986580221912 },
	{ name = "StumpTaper099_H8_R22", set = "R22", taper = 99, height = 8, id = 72203321440203 },
	{ name = "StumpTaper100_H3_R22", set = "R22", taper = 100, height = 3, id = 121512153812219 },
	{ name = "StumpTaper100_H5_R22", set = "R22", taper = 100, height = 5, id = 127912423343422 },
	{ name = "StumpTaper100_H8_R22", set = "R22", taper = 100, height = 8, id = 115206746024823 },
} :: { Row }

-- Key 1..96: set-major (R13 then R22), then taper, then height (3, 5, 8).
-- Key = (setIndex - 1) * 48 + (ratioIndex - 1) * 3 + heightIndex, ratioIndex
-- 1..16 being StumpLogic.Ratios (0.85 ... 1.00).
function StumpMeshIds.Key(set: string, ratioIndex: number, height: number): number?
	local setIndex = table.find(StumpMeshIds.Sets, set)
	local heightIndex = table.find(StumpMeshIds.Heights, height)
	if not setIndex or not heightIndex then
		return nil
	end
	return (setIndex - 1) * 48 + (ratioIndex - 1) * 3 + heightIndex
end

function StumpMeshIds.Row(key: number): Row?
	local setIndex = (key - 1) // 48 + 1
	local rest = (key - 1) % 48
	local ratioIndex = rest // 3 + 1
	local set = StumpMeshIds.Sets[setIndex]
	local height = StumpMeshIds.Heights[rest % 3 + 1]
	for _, row in ipairs(StumpMeshIds.Rows) do
		if row.set == set and row.taper == 84 + ratioIndex and row.height == height then
			return row
		end
	end
	return nil
end

-- The model id for a set, taper (ratioIndex 1..16) and native height (3, 5, 8).
function StumpMeshIds.IdFor(set: string, ratioIndex: number, height: number): number?
	local key = StumpMeshIds.Key(set, ratioIndex, height)
	local row = if key then StumpMeshIds.Row(key) else nil
	return if row then row.id else nil
end

return StumpMeshIds
