require 'Editor/Evaluator/MSLEvaluator'

-- Templates use lustache for rendering: https://github.com/Olivine-Labs/lustache

local MAIN_TEMPLATE_MANIFEST =
[[

]]

local MAIN_TEMPLATE_SWIFT =
[[import SceneKit
import UIKit
import PlaygroundSupport
import UserModule

public class LiveVC: UIViewController {

    let scene = SCNScene()
    public var sceneView = SCNView(frame: CGRect(x: 0,y: 0,width: 640,height: 1080))

    override public func viewDidLoad() {
        super.viewDidLoad()
        sceneView.scene = scene
        view.addSubview(sceneView)

        sceneView.backgroundColor = #colorLiteral(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        sceneView.showsStatistics = false
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = true

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 12)
        scene.rootNode.addChildNode(cameraNode)

        let geo = SCNSphere(radius: 1.0)
        let node = SCNNode(geometry: geo)
        node.transform = SCNMatrix4MakeRotation(Float.pi * 0.25,1,0,0)
        scene.rootNode.addChildNode(node)

        geo.firstMaterial = {{{name_no_spaces}}}()
    }
}
var vc = LiveVC()
PlaygroundPage.current.liveView = vc
PlaygroundPage.current.needsIndefiniteExecution = true]]

local SHADER_TEMPLATE_SWIFT =
[[

import SceneKit
import UIKit

public final class {{{name_no_spaces}}}Material: SCNMaterial {

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    public override init() {
        super.init()

		let vertShader =
"""
#pragma arguments
{{#uniforms}}
{{{scn_uniform}}}
{{/uniforms}}
#pragma declaration
#pragma body
{
	{{#vert}}
	{{{scn_surface_output}}}
	{{/vert}}
}
"""

        let fragShader =
"""
#pragma arguments
{{#uniforms}}
{{{scn_uniform}}}
{{/uniforms}}
#pragma declaration
constexpr sampler defaultSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
#pragma body

struct Functions
{
   constant commonprofile_node& scn_node;
   constant SCNSceneBuffer& scn_frame;
   thread SCNShaderSurface& _surface;
	{{#uniforms}}
	{{{scn_uniform_function_struct_member}}}
	{{/uniforms}}
	{{#frag_funcs}}
	{{{.}}}
	{{/frag_funcs}}
};
Functions functions
{
	scn_node,
	scn_frame,
	_surface,
	{{#uniforms}}
	{{{scn_uniform_function_struct_init}}},
	{{/uniforms}}
};

{
	{{#frag}}
	{{{scn_surface_output}}}
	{{/frag}}
}
"""
        shaderModifiers = [.vertex: vertShader, .fragment: fragShader]
        //setValue(SCNVector3(1.0, 0.8, 0.6), forKey:"lazerCol")
    }

    //var lazerCol: SCNVector3 = SCNVector3(0.5, 0.8, 0.5) {
    //    didSet {
    //        setValue(lazerCol, forKey:"lazerCol")
    //    }
    //}
}]]

local SceneKitExport = class(MSLEvaluator)

function SceneKitExport:init()
    MSLEvaluator.init(self)
	self:addTemplate("Contents/Chapters/Chapter1.playgroundchapter/Pages/My Playground.playgroundpage/main.swift", MAIN_TEMPLATE_SWIFT)
    self:addTemplate("Contents/UserModules/UserModule.playgroundmodule/Sources/{{name_no_spaces}}Material.swift", SHADER_TEMPLATE_SWIFT)
end

function SceneKitExport:onExport(name)
	return name..".playgroundbook"
end

function SceneKitExport:onSaveImage(name)
	-- Ignore icon images
	if name:find("Icon@2x") then return nil end

	-- Check if image is actually used
	for _, prop in pairs(self.viewModel[TAG_PROPERTIES]) do
		if name:removeExtension() == prop.default then
			return "Resources/" .. name
		end
	end

	return nil
end

function SceneKitExport:clear()
    MSLEvaluator.clear(self)

    self.viewModel =
    {
        [TAG_PROPERTIES] = {},
        [TAG_UNIFORMS] = {},
        [TAG_VERT] = {},
        [TAG_FRAG] = {},
        [TAG_VERT_FUNCS] = {},
        [TAG_FRAG_FUNCS] = {}
    }

	for k,v in pairs(self.model) do
        self.viewModel[k] = v
    end

end

function SceneKitExport:functionCall(name, ...)
    return "functions."..MSLEvaluator.functionCall(self, name, ...)
end


local SURFACE_OUTPUTS =
{
    [TAG_INPUT_DIFFUSE] = function(self) return string.format("_surface.diffuse = float4(%s, 1.0);", self.code) end,
    [TAG_INPUT_EMISSION] = function(self) return string.format("_surface.emission = float4(%s, 0.0);", self.code) end,
    [TAG_INPUT_NORMAL] = function(self)
		return string.format(
[[{\n"
"  		_surface._normalTS = %s;\n"
"		float3x3 ts2vs = float3x3(_surface.tangent, _surface.bitangent, _surface.normal);\n"
"		_surface.normal.rgb = normalize(ts2vs * _surface._normalTS.xyz);\n"
"}]], self.code)
	end,
    [TAG_INPUT_OPACITY] = function(self) return string.format("_surface.transparent = float4(%s);", self.code) end,
    [TAG_INPUT_ROUGHNESS] = function(self) return string.format("_surface.roughness = %s;", self.code) end,
    [TAG_INPUT_METALNESS] = function(self) return string.format("_surface.metalness = %s;", self.code) end,
    [TAG_INPUT_OCCLUSION] = function(self) return string.format("_surface.ambientOcclusion = %s;", self.code) end,
	[TAG_INPUT_VERTEX_OFFSET] = function(self) return string.format("_geometry.position.xyz += %s;", self.code) end
}

local SCN_RENDER_QUEUE_MAP =
{
    [RENDER_QUEUE_SOLID] = "Geometry",
    [RENDER_QUEUE_TRANSPARENT] = "Transparent"
}

local SCN_RENDER_TYPE_MAP =
{
    [RENDER_QUEUE_SOLID] = "Opaque",
    [RENDER_QUEUE_TRANSPARENT] = "Transparent"
}

local SCN_BLEND_MAP =
{
    [BLEND_MODE_NORMAL] = {"SrcAlpha", "OneMinusSrcAlpha"},
    [BLEND_MODE_ADDITIVE] = {"One", "One"},
    [BLEND_MODE_MULTIPLY] = {"DstColor", "Zero"},
}

-- Model can be used to render template tags with custom lua code
-- Tags, such as uniforms and properties, contain data that must be processed into strings
SceneKitExport.model =
{
    scn_uniform = function(self)
		local default = {0.0, 0.0, 0.0, 0.0}

		if self.type == FLOAT then
			default = string.format('%.2f', default[1])
		elseif self.type == VEC2 then
			default = string.format('float2(%.2f, %.2f)', default[1], default[2])
		elseif self.type == VEC3 then
			default = string.format('float3(%.2f, %.2f, %.2f)', default[1], default[2], default[3])
		elseif self.type == VEC4 then
			default = string.format('float4(%.2f, %.2f, %.2f, %.2f)', default[1], default[2], default[3], default[4])
		else
			return string.format("texture2d<float> %s;", self.name)
		end

        return string.format("%s %s = %s;", self.value_type, self.name, default)
    end,

	scn_uniform_function_struct_member = function(self)
		return string.format("%s %s;", self.value_type, self.name)
	end,

	scn_uniform_function_struct_init = function(self)
		return string.format("%s", self.name)
	end,


    -- Convert fragment/surface outputs into shader code
    scn_surface_output = function(self)
		if type(self) == 'string' then
            return self
        elseif SURFACE_OUTPUTS[self.input_name] then
			return SURFACE_OUTPUTS[self.input_name](self)
        end
    end,

    scn_property_header = function(self)
        local valueType = nil
		local mode = "assign"
        if self.type == TEXTURE2D then
            valueType = "SCNMaterialProperty*"
			mode = "strong"
        elseif self.type == FLOAT then
            valueType = "CGFloat"
        elseif self.type == VEC2 then
            valueType = "CGPoint"
        elseif self.type == VEC3 then
            valueType = "SCNVector3"
        elseif self.type == VEC4 then
            valueType = "SCNVector4"
        end

        local name = self.uniform_name:gsub("_", "")

        return string.format("@property(nonatomic, %s) %s %s", mode, valueType, name)
    end,

	scn_property_declare = function(self)
        local viewModel = {}
		viewModel.uniform_name = self.uniform_name

        if self.type == TEXTURE2D then
            viewModel.value_type = "SCNMaterialProperty*"
        elseif self.type == FLOAT then
            viewModel.value_type = "CGFloat"
        elseif self.type == VEC2 then
            viewModel.value_type = "CGPoint"
        elseif self.type == VEC3 then
            viewModel.value_type = "SCNVector3"
        elseif self.type == VEC4 then
            viewModel.value_type = "SCNVector4"
        end

        local template = "{{{value_type}}} {{{uniform_name}}};"
        return lustache:render(template, viewModel)
    end,

    scn_property_source = function(self)
        local viewModel = {}

        if self.type == TEXTURE2D then
            viewModel.value_type = "SCNMaterialProperty*"
            viewModel.wrapper = "value"
			viewModel.texture = true
        elseif self.type == FLOAT then
            viewModel.value_type = "CGFloat"
            viewModel.wrapper = "[NSNumber numberWithFloat:value]"
        elseif self.type == VEC2 then
            viewModel.value_type = "CGPoint"
            viewModel.wrapper = "[NSValue valueWithPoint:NSMakePoint(value.x, value.y)]"
        elseif self.type == VEC3 then
            viewModel.value_type = "SCNVector3"
            viewModel.wrapper = "[NSValue valueWithSCNVector3:value]"
        elseif self.type == VEC4 then
            viewModel.value_type = "SCNVector4"
            viewModel.wrapper = "[NSValue valueWithSCNVector4:value]"
        end

        viewModel.setter_name = self.uniform_name:gsub("_", ""):titlecase()
        viewModel.uniform_name = self.uniform_name

        local template =
[[
- (void) set{{{setter_name}}}:({{{value_type}}})value
{
	self->{{{uniform_name}}} = value;
	[self setValue:{{{wrapper}}} forKey:@"{{{uniform_name}}}"];
}

- ({{{value_type}}}) get{{{setter_name}}}
{
	return self->{{{uniform_name}}};
}
]]
        return lustache:render(template, viewModel)
    end,

    scn_property_init = function(self)
        local viewModel = {}

        if self.type == TEXTURE2D then
            viewModel.value = string.format('[SCNMaterialProperty materialPropertyWithContents:@"%s.png"]', self.default)
			viewModel.texture = true
        elseif self.type == FLOAT then
            viewModel.value = string.format("%f", self.default)
        elseif self.type == VEC2 then
            viewModel.value = string.format("CGPointMake(%f, %f)", self.default[1], self.default[2])
        elseif self.type == VEC3 then
            viewModel.value = string.format("SCNVector3Make(%f, %f, %f)", self.default[1], self.default[2], self.default[3])
        elseif self.type == VEC4 then
            viewModel.value = string.format("SCNVector4Make(%f, %f, %f, %f)", self.default[1], self.default[2], self.default[3], self.default[4])
        end

        viewModel.property_name = self.uniform_name:gsub("_", "")
		viewModel.uniform_name = self.uniform_name

        local template =
[[{{#texture}}
self->{{{uniform_name}}} = {{{value}}};
self->{{{uniform_name}}}.wrapS = SCNWrapModeRepeat;
self->{{{uniform_name}}}.wrapT = SCNWrapModeRepeat;
[self setValue:self->{{{uniform_name}}} forKey:@"{{{uniform_name}}}"];
{{/texture}}
{{^texture}}
self.{{{property_name}}} = {{{value}}};
{{/texture}}
]]
        return lustache:render(template, viewModel)
    end
}

-- Lookup tables for various shader syntax
local SCN_TEXCOORD =
{
    [TAG_VERT] = {"_geometry.texcoords[0]", "_geometry.texcoords[1]"},
    [TAG_FRAG] = {"_surface.diffuseTexcoord", "_surface.diffuseTexcoord"}
}

local SCN_COLOR =
{
    [TAG_VERT] = "_geometry.color",
    [TAG_FRAG] = "in.vertexColor"
}

local SCN_POSITION =
{
    [TAG_VERT] =
    {
        [OBJECT_SPACE] = "_geometry.position.xyz",
        [VIEW_SPACE] = "(scn_node.modelViewTransform * _geometry.position).xyz",
        [WORLD_SPACE] = "(scn_node.modelTransform * _geometry.position).xyz",
        [TANGENT_SPACE] = "???"
-- [[
-- {
-- 	vec3 bitangent = _geometry.tangent.w * cross(_geometry.tangent, _geometry.normal);
-- 	vec3 ts2vs = mat3(_geometry.tangent, bitangent, _geometry.normal);
-- }
-- ]]
    },

    [TAG_FRAG] =
    {
        [OBJECT_SPACE] = "(scn_node.inverseModelTransform * vec4(_surface.position, 1.0)).xyz",
        [VIEW_SPACE] = "(scn_frame.viewTransform * scn_node.inverseModelTransform * vec4(_surface.position, 1.0)).xyz",
        [WORLD_SPACE] = "_surface.position",
        [TANGENT_SPACE] = "???",
    }
}

local SCN_NORMAL =
{
    [TAG_VERT] =
    {
        [OBJECT_SPACE] = "_geometry.normal",
        [VIEW_SPACE] = "(scn_node.modelViewTransform * vec4(_geometry.normal, 0.0)).xyz",
        [WORLD_SPACE] = "(scn_node.modelTransform * vec4(_geometry.normal, 0.0)).xyz",
        [TANGENT_SPACE] = "???",
    },

    [TAG_FRAG] =
    {
		[OBJECT_SPACE] = "(scn_node.normalTransform * vec4(_surface.normal, 0.0)).xyz",
        [VIEW_SPACE] = "(scn_frame.viewTransform * scn_node.normalTransform * vec4(_surface.normal, 0.0)).xyz",
        [WORLD_SPACE] = "(vec4(_surface.geometryNormal, 0.0) * scn_node.normalTransform).xyz",
        [TANGENT_SPACE] = "???",
    }
}

local SCN_VIEW_DIR =
{
    [TAG_VERT] =
    {
        [OBJECT_SPACE] = "???",
        [VIEW_SPACE] = "???",
        [WORLD_SPACE] = "???",
        [TANGENT_SPACE] = "???",
    },

    [TAG_FRAG] =
    {
        [OBJECT_SPACE] = "???",
        [VIEW_SPACE] = "_surface.view",
        [WORLD_SPACE] = "???",
        [TANGENT_SPACE] = "???",
    }
}


-- Exporters require syntax for various primitive elements to be defined
SceneKitExport.syntax =
{
    uv = function(self, index)
		return SCN_TEXCOORD[self:tag()][index or 1]
	end,

    color = function(self, index) return SCN_COLOR[self:tag()] end,

    position = function(self, space)
        return SCN_POSITION[self:tag()][space]
    end,

	normal = function(self, space)
		return SCN_NORMAL[self:tag()][space]
	end,

	viewDir = function(self, space)
		return SCN_VIEW_DIR[self:tag()][space]
	end,

    texture2D = function(self, sampler, uv)
        return string.format("%s.sample(defaultSampler, %s)", sampler, uv)
    end,

    texture2DLod = function(self, sampler, uv, lod)
        return string.format("%s.sample(defaultSampler, %s, level(%s))", sampler, uv, lod or "0.0")
    end,
    --
    -- textureSize = function(self, tex)
    --     return "vec2(0.0, 0.0)"
    -- end,
    --
    -- cameraPosition = function(self)
    --     return "_WorldSpaceCameraPos.xyz"
    -- end,
    --
    -- sceneDepth = function(self, screenPos)
    --     return string.format("LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, %s/%s))", screenPos, self:screenPos():gsub(".xy", ".w"))
    -- end,
    --
    -- depth = function(self)
    --     if self:tag() == TAG_SURF or self:tag() == TAG_FRAG then
    --         return "IN.eyeDepth"
    --     else
    --         return "o.eyeDepth"
    --     end
    -- end,
    --
    -- frontFacing = function(self)
    --     if self:tag() == TAG_SURF or self:tag() == TAG_SURF then
    --         return "(facing == 1.0)"
    --     else
    --         return "false"
    --     end
    -- end,
    --
    -- screenPos = function(self)
    --     if self:tag() == TAG_SURF or self:tag() == TAG_FRAG then
    --         return "IN.screenPos.xy"
    --     else
    --         return "(o.screenPos.xy)"
    --     end
    -- end,
    --
    -- sceneColor = function(self, screenPos)
    --     return string.format("tex2D(_BackgroundTexture, %s/%s)", screenPos, self:screenPos():gsub(".xy", ".w"))
    -- end,
    --
    -- -- TODO implement instanceID functionality
    -- instanceID = function(self)
    --     return "0.0"
    -- end,
    --
    -- -- TODO implement vertexID functionality
    -- vertexID = function(self)
    --     return "0.0"
    -- end,
    --
    -- -- TODO implement barycentric functionality
    -- barycentric = function(self)
    --     return "vec3(0.0, 0.0, 0.0)"
    -- end,
    --
    -- parallax = function(self, uv)
    --     local tangentViewDir = self:viewDir(TANGENT_SPACE)
    --     return string.format("parallax(%s, %s)", uv, tangentViewDir)
    -- end
}

return SceneKitExport
