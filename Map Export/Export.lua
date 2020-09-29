require 'Editor/Evaluator/Evaluator'

MapExport = class(Evaluator)

function MapExport:init()
    Evaluator.init(self)
end

function MapExport:clear()
    Evaluator.clear(self)

    self.viewModel =
    {
        [TAG_PROPERTIES] = {},
        [TAG_UNIFORMS] = {},
        [TAG_VERT] = {},
        [TAG_FRAG] = {},
        [TAG_VERT_FUNCS] = {},
        [TAG_FRAG_FUNCS] = {}
    }
end

function MapExport:onExport(name)
	return name.." Maps"
end

function MapExport:onSaveImage(name)
	-- Ignore icon images
	if name:find("Icon@2x") then return nil end

	-- Check if image is actually used
	for _, prop in pairs(self.viewModel[TAG_PROPERTIES]) do
		if name:removeExtension() == prop.default then
			return name
		end
	end

	return nil
end

return MapExport
