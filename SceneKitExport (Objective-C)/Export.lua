require 'Editor/Evaluator/GLSLEvaluator'

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

@interface {{name_no_spaces}} : SCNMaterial

@end

NS_ASSUME_NONNULL_END]]

local SHADER_TEMPLATE_M =
[[//
//  {{name_no_spaces}}.m
//  Shade Custom Material Export for SceneKit
//
//  Created by John Millard on 28/1/20.
//  Copyright © 2020 John Millard. All rights reserved.
//

#import "{{name_no_spaces}}.h"

@implementation {{name_no_spaces}}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.lightingModelName = SCNLightingModelPhysicallyBased;

        self.shaderModifiers =
        @{SCNShaderModifierEntryPointSurface :
		@""
		{{#uniforms}}
		"{{{scn_uniform}}}"
		{{/uniforms}}
		""
		{{#frag}}
        "{{{scn_surface_output}}}"
		{{/frag}}
        };
    }
    return self;
}

@end]]

local SceneKitExport = class(GLSLEvaluator)

function SceneKitExport:init()
    GLSLEvaluator.init(self)
	self:addTemplate("{{name_no_spaces}}Material.h", SHADER_TEMPLATE_H)
    self:addTemplate("{{name_no_spaces}}Material.m", SHADER_TEMPLATE_M)
end

function SceneKitExport:clear()
    GLSLEvaluator.clear(self)

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
    [TAG_INPUT_DIFFUSE] = "diffuse",
    [TAG_INPUT_EMISSION] = "emission",
    [TAG_INPUT_NORMAL] = "_normalTS",
    [TAG_INPUT_OPACITY] = "transparent",
    [TAG_INPUT_ROUGHNESS] = "roughness",
    [TAG_INPUT_METALNESS] = "metalness",
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
			default = string.format('vec2(%.2f, %.2f)', default[1], default[2])
		elseif self.type == VEC3 then
			default = string.format('vec3(%.2f, %.2f, %.2f)', default[1], default[2], default[3])
		elseif self.type == VEC4 then
			default = string.format('vec4(%.2f, %.2f, %.2f, %.2f)', default[1], default[2], default[3], default[4])
		end

        return string.format("uniform %s %s = ;", self.value_type, self.name)
    end,

    -- Convert fragment/surface outputs into shader code
    scn_surface_output = function(self)
		if type(self) == 'string' then
            return self
        elseif SURFACE_OUTPUTS[self.input_name] then
            return string.format("_surface.%s = %s;", SURFACE_OUTPUTS[self.input_name], self.code)
        end
    end,

}

-- Lookup tables for various shader syntax
local SCN_TEXCOORD =
{
    [TAG_VERT] = "_geometry.texcoords",
    [TAG_FRAG] = "_geometry.texcoords"
}

local SCN_COLOR =
{
    [TAG_VERT] = "_geometry.color",
    [TAG_FRAG] = "_geometry.color"
}

local SCN_POSITION =
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
        [OBJECT_SPACE] = "scn_node.inverseModelTransform * vec4(_surface.position, 1.0)",
        [VIEW_SPACE] = "???",
        [WORLD_SPACE] = "???",
        [TANGENT_SPACE] = "???",
    }
}

local SCN_NORMAL =
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
        -- [OBJECT_SPACE] *special-case*
        [VIEW_SPACE] = "???",
        -- [WORLD_SPACE] *special-case*
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
        [VIEW_SPACE] = "???",
        [WORLD_SPACE] = "???",
        [TANGENT_SPACE] = "???",
    }
}


-- Exporters require syntax for various primitive elements to be defined
SceneKitExport.syntax =
{
    uv = function(self, index)
		return SCN_TEXCOORD[self:tag()]..string.format("[%d]", (index and index or 1) - 1)
	end,

    color = function(self, index) return SCN_COLOR[self:tag()] end,

    position = function(self, space)
        return SCN_POSITION[self:tag()][space]
    end,
    --
    -- normal = function(self, space)
    --
    --     -- Exception for object/world space normals in surface shader (due to special behaviour when writing custom normals)
    --     if space == OBJECT_SPACE and self:tag() == TAG_FRAG then
    --         return string.format("normalize( mul( float4(%s , 0.0 ), unity_WorldToObject ).xyz )", self:normal(WORLD_SPACE))
    --     elseif space == WORLD_SPACE and self:tag() == TAG_FRAG then
    --         if self.viewModel[TAG_WRITE_NORMAL] then
    --             return "WorldNormalVector(IN, float3(0, 0, 1))"
    --         else
    --             return "normalize(IN.worldNormal)"
    --         end
    --     end
    --
    --     return UNITY_NORMAL[self:tag()][space]
    -- end,
    --
    -- viewDir = function(self, space)
    --     if space == WORLD_SPACE and self:tag() == TAG_FRAG then
    --         self.viewModel[TAG_READ_WORLD_POS] = true
    --     end
    --
    --     return UNITY_VIEW_DIR[self:tag()][space]
    -- end,
    --
    -- texture2D = function(self, sampler, uv)
    --     return string.format("tex2D(%s, %s)", sampler, uv)
    -- end,
    --
    -- texture2DLod = function(self, sampler, uv, lod)
    --     return string.format("tex2DLod(%s, %s)", sampler, uv)
    -- end,
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
