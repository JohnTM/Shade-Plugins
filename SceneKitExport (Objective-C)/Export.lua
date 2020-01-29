require 'Editor/Evaluator/MSLEvaluator'

-- Templates use lustache for rendering: https://github.com/Olivine-Labs/lustache

local SHADER_TEMPLATE_H =
[[//
//  {{name_no_spaces}}.h
//  Shade Custom Material Export for SceneKit
//
//  Created by John Millard on 28/1/20.
//  Copyright © 2020 John Millard. All rights reserved.
//

#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface {{name_no_spaces}}Material : SCNMaterial

@end

NS_ASSUME_NONNULL_END]]

local SHADER_TEMPLATE_M =
[[//
//  {{name_no_spaces}}Material.m
//  Shade Custom Material Export for SceneKit
//
//  Created by John Millard on 28/1/20.
//  Copyright © 2020 John Millard. All rights reserved.
//

#import "{{name_no_spaces}}Material.h"

@implementation {{name_no_spaces}}Material

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.lightingModelName = SCNLightingModelPhysicallyBased;

        self.shaderModifiers =
        @{SCNShaderModifierEntryPointSurface :
		@""
		"#pragma arguments"
		{{#uniforms}}
		"{{{scn_uniform}}}"
		{{/uniforms}}

		"#pragma body"

		constexpr sampler defaultSampler(filter::linear, mip_filter::linear);

		{
			{{#frag}}
	        "{{{scn_surface_output}}}"
			{{/frag}}
		}
        };
    }
    return self;
}

@end]]

local SceneKitExport = class(MSLEvaluator)

function SceneKitExport:init()
    MSLEvaluator.init(self)
	self:addTemplate("{{name_no_spaces}}Material.h", SHADER_TEMPLATE_H)
    self:addTemplate("{{name_no_spaces}}Material.m", SHADER_TEMPLATE_M)
end

function SceneKitExport:onSaveImage(name)
	-- Ignore icon images
	if name:find("Icon@2x") then return nil end

	return "/Images/" .. name
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

local SURFACE_OUTPUTS =
{
    [TAG_INPUT_DIFFUSE] = function(self) return string.format("diffuse = float4(%s, 1.0)", self.code) end,
    [TAG_INPUT_EMISSION] = function(self) return string.format("emission = float4(%s, 0.0)", self.code) end,
    [TAG_INPUT_NORMAL] = function(self) return string.format("_normalTS = %s", self.code) end,
    [TAG_INPUT_OPACITY] = function(self) return string.format("transparent = float4(%s)", self.code) end,
    [TAG_INPUT_ROUGHNESS] = function(self) return string.format("roughness = %s", self.code) end,
    [TAG_INPUT_METALNESS] = function(self) return string.format("metalness = %s", self.code) end,
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
		local default = nil

		if self.type == FLOAT then
			default = string.format('%.2f', default)
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

    -- Convert fragment/surface outputs into shader code
    scn_surface_output = function(self)
		if type(self) == 'string' then
            return self
        elseif SURFACE_OUTPUTS[self.input_name] then
			return "_surface." .. SURFACE_OUTPUTS[self.input_name](self) .. ";"
        end
    end,

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
        return string.format("%s.sample(defaultSampler, %s, level(%s))", sampler, uv, lod)
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
