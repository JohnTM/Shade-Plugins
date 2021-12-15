require 'Editor/Evaluator/HLSLEvaluator'

-- Templates use lustache for rendering: https://github.com/Olivine-Labs/lustache
local template =
[[
Shader "Shade/{{{name}}}"
{
    // Made with Shade Pro by Two Lives Left
    Properties
    {
    {{#properties}}
        {{{unity_property}}}
    {{/properties}}
    }

    SubShader
    {
        {{#grab_pass}}
        // Grab the screen behind the object into _BackgroundTexture
        GrabPass
        {
            "_BackgroundTexture"
        }
        {{/grab_pass}}

        Tags { "Queue"="{{unity_render_queue}}" "RenderType"="{{unity_render_type}}" "RenderPipeline" = "UniversalRenderPipeline" }
        {{#blend_enabled}}
        {{unity_blend}}
        {{/blend_enabled}}
        {{unity_depth_write}}
        LOD 200

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

            {{#grab_pass}}

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            float4 sceneColor(float2 screenPos)
            {
                return SampleSceneColor(screenPos);
            }

            {{/grab_pass}}
            {{#read_depth_texture}}

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            real sceneDepth(float2 screenPos)
            {
                #if UNITY_REVERSED_Z
                    real depth = SampleSceneDepth(screenPos);
                #else
                    // Adjust z to match NDC for OpenGL
                    real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(screenPos));
                #endif
                return LinearEyeDepth(depth, _ZBufferParams);
            }

            {{/read_depth_texture}}

            // To make the Unity shader SRP Batcher compatible, declare all
            // properties related to a Material in a a single CBUFFER block with
            // the name UnityPerMaterial.
            CBUFFER_START(UnityPerMaterial)
                {{#uniforms}}
                {{{unity_uniform}}}
                {{/uniforms}}
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv0          : TEXCOORD0;
                float2 uv1          : TEXCOORD1;
                float4 color        : COLOR0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv0          : TEXCOORD0;
                float2 uv1          : TEXCOORD1;
                float4 positionWSAndFogFactor   : TEXCOORD2; // xyz: positionWS, w: vertex fog factor
                float4 color        : COLOR0;
                half3  normalWS     : TEXCOORD3;
                half3 tangentWS     : TEXCOORD4;
                half3 bitangentWS   : TEXCOORD5;
    #ifdef _MAIN_LIGHT_SHADOWS
                float4 shadowCoord  : TEXCOORD6; // compute shadow coord per-vertex for the main light
    #endif
            };

            {{#vert_funcs}}
            {{{.}}}
            {{/vert_funcs}}
            {{#frag_funcs}}
            {{{.}}}
            {{/frag_funcs}}

            Varyings vert(Attributes input)
            {
                Varyings output;

                // VertexPositionInputs contains position in multiple spaces (world, view, homogeneous clip space)
                // Our compiler will strip all unused references (say you don't use view space).
                // Therefore there is more flexibility at no additional cost with this struct.
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

                // Similar to VertexPositionInputs, VertexNormalInputs will contain normal, tangent and bitangent
                // in world space. If not used it will be stripped.
                VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                // Computes fog factor per-vertex.
                float fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                output.positionCS = vertexInput.positionCS;
                output.positionWSAndFogFactor = float4(vertexInput.positionWS, fogFactor);
                output.normalWS = vertexNormalInput.normalWS;
                output.tangentWS = vertexNormalInput.tangentWS;
                output.bitangentWS = vertexNormalInput.bitangentWS;
                output.uv0 = input.uv0;
                output.uv1 = input.uv1;
                output.color = input.color;

    #ifdef _MAIN_LIGHT_SHADOWS
                // shadow coord for the main light is computed in vertex.
                // If cascades are enabled, LWRP will resolve shadows in screen space
                // and this coord will be the uv coord of the screen space shadow texture.
                // Otherwise LWRP will resolve shadows in light space (no depth pre-pass and shadow collect pass)
                // In this case shadowCoord will be the position in light space.
                output.shadowCoord = GetShadowCoord(vertexInput);
    #endif

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float3 positionWS = input.positionWSAndFogFactor.xyz;
                half3 viewDirectionWS = SafeNormalize(GetCameraPositionWS() - positionWS);
                half3x3 tangentToWorld = half3x3(input.tangentWS, input.bitangentWS, input.normalWS);

                SurfaceData surfaceData;

                {{#frag}}
                {{{unity_surface_output}}}
                {{/frag}}

                {{#write_normal}}
                half3 normalWS = TransformTangentToWorld(surfaceData.normalTS, tangentToWorld);
                {{/#write_normal}}
                {{^write_normal}}
                half3 normalWS = input.normalWS;
                {{/#write_normal}}
                normalWS = normalize(normalWS);

    {{#physical}}
    #ifdef LIGHTMAP_ON
                // Normal is required in case Directional lightmaps are baked
                half3 bakedGI = SampleLightmap(input.uvLM, normalWS);
    #else
                // Samples SH fully per-pixel. SampleSHVertex and SampleSHPixel functions
                // are also defined in case you want to sample some terms per-vertex.
                half3 bakedGI = SampleSH(normalWS);
    #endif

                // BRDFData holds energy conserving diffuse and specular material reflections and its roughness.
                // It's easy to plugin your own shading fuction. You just need replace LightingPhysicallyBased function
                // below with your own.
                BRDFData brdfData;
                InitializeBRDFData(surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.alpha, brdfData);

                // Light struct is provide by LWRP to abstract light shader variables.
                // It contains light direction, color, distanceAttenuation and shadowAttenuation.
                // LWRP take different shading approaches depending on light and platform.
                // You should never reference light shader variables in your shader, instead use the GetLight
                // funcitons to fill this Light struct.
    #ifdef _MAIN_LIGHT_SHADOWS
                // Main light is the brightest directional light.
                // It is shaded outside the light loop and it has a specific set of variables and shading path
                // so we can be as fast as possible in the case when there's only a single directional light
                // You can pass optionally a shadowCoord (computed per-vertex). If so, shadowAttenuation will be
                // computed.
                Light mainLight = GetMainLight(input.shadowCoord);
    #else
                Light mainLight = GetMainLight();
    #endif

                // Mix diffuse GI with environment reflections.
                half3 color = GlobalIllumination(brdfData, bakedGI, surfaceData.occlusion, normalWS, viewDirectionWS);

                // LightingPhysicallyBased computes direct light contribution.
                color += LightingPhysicallyBased(brdfData, mainLight, normalWS, viewDirectionWS);

                // Additional lights loop
    #ifdef _ADDITIONAL_LIGHTS

                // Returns the amount of lights affecting the object being renderer.
                // These lights are culled per-object in the forward renderer
                int additionalLightsCount = GetAdditionalLightsCount();
                for (int i = 0; i < additionalLightsCount; ++i)
                {
                    // Similar to GetMainLight, but it takes a for-loop index. This figures out the
                    // per-object light index and samples the light buffer accordingly to initialized the
                    // Light struct. If _ADDITIONAL_LIGHT_SHADOWS is defined it will also compute shadows.
                    Light light = GetAdditionalLight(i, positionWS);

                    // Same functions used to shade the main light.
                    color += LightingPhysicallyBased(brdfData, light, normalWS, viewDirectionWS);
                }
    #endif
    {{/physical}}
    {{#unlit}}
                half3 color = surfaceData.albedo;
    {{/unlit}}
    {{#custom}}
                half3 color = surfaceData.albedo; // TODO: custom lighting model
    {{/custom}}

                // Emission
                color += surfaceData.emission;

                float fogFactor = input.positionWSAndFogFactor.w;

                // Mix the pixel color with fogColor. You can optionaly use MixFogColor to override the fogColor
                // with a custom one.
                color = MixFog(color, fogFactor);
                return half4(color, surfaceData.alpha);
            }
            ENDHLSL
        }

        // Used for rendering shadowmaps
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"

        // Used for depth prepass
        // If shadows cascade are enabled we need to perform a depth prepass.
        // We also need to use a depth prepass in some cases camera require depth texture
        // (e.g, MSAA is enabled and we can't resolve with Texture2DMS
        UsePass "Universal Render Pipeline/Lit/DepthOnly"

        // Used for Baking GI. This pass is stripped from build.
        UsePass "Universal Render Pipeline/Lit/Meta"
    }
}
]]

UnityExport = class(HLSLEvaluator)

function UnityExport:init()
    HLSLEvaluator.init(self)
    self.requiresGraphJSON = true
    self:addTemplate('Unity.shader', template)
    self:addTemplate('Graph.json', '{{{graph_json}}}')
end

function UnityExport:onExport(name)
	return name
end

function UnityExport:clear()
    HLSLEvaluator.clear(self)

    self.viewModel =
    {
        [TAG_PROPERTIES] = {},
        [TAG_UNIFORMS] = {},
        [TAG_VERT] = {},
        [TAG_FRAG] = {},
        [TAG_VERT_FUNCS] = {},
        [TAG_FRAG_FUNCS] = {},
        [TAG_LIGHTING_FUNC] = {},
    }

    for k,v in pairs(self.model) do
        self.viewModel[k] = v
    end
end

function UnityExport:onSaveImage(name)
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

function UnityExport:addUniform(name, valueType, precision)
    -- Unity already has a time value defined by default
    if name == "time" then
        return "_time"
    end

    return HLSLEvaluator.addUniform(self, name, valueType, precision)
end

function UnityExport:addProperty(name, valueType, default, options)
    -- Unity already has a time value defined by default
    if name == "time" then
        return
    end

    HLSLEvaluator.addProperty(self, name, valueType, default, options)
end

local SURFACE_OUTPUTS =
{
    [TAG_INPUT_DIFFUSE] = "albedo",
    [TAG_INPUT_METALNESS] = "metallic",
    [TAG_INPUT_SMOOTHNESS] = "smoothness",
    [TAG_INPUT_NORMAL] = "normalTS",
    [TAG_INPUT_EMISSION] = "emission",
    [TAG_INPUT_OCCLUSION] = "occlusion",
    [TAG_INPUT_OPACITY] = "alpha",
}

local UNITY_RENDER_QUEUE_MAP =
{
    [RENDER_QUEUE_SOLID] = "Geometry",
    [RENDER_QUEUE_TRANSPARENT] = "Transparent"
}

local UNITY_RENDER_TYPE_MAP =
{
    [RENDER_QUEUE_SOLID] = "Opaque",
    [RENDER_QUEUE_TRANSPARENT] = "Transparent"
}

local UNITY_BLEND_MAP =
{
    [BLEND_MODE_NORMAL] = {"SrcAlpha", "OneMinusSrcAlpha"},
    [BLEND_MODE_ADDITIVE] = {"One", "One"},
    [BLEND_MODE_MULTIPLY] = {"DstColor", "Zero"},
}

-- Model can be used to render template tags with custom lua code
-- Tags, such as uniforms and properties, contain data that must be processed into strings
UnityExport.model =
{
    -- Convert property data into unity property string
    unity_property = function(self)

        local valueType = nil
        local default = nil
        local name = self.name
        local uniformName = self.uniform_name
        local control = self.options and self.options.control
        local default = self.default

        if default and type(default) == 'table' then
            local x, y, z, w = default[1] or 0, default[2] or 0, default[3] or 0, default[4] or 0
            default = string.format('(%s, %s, %s, %s)', x, y, z, w)
        elseif default and type(default) == 'number' then
            default = string.format('%.2f', default)
        end

        if self.type == TEXTURE2D then
            valueType = "2D"
            default = '"white" {}'
        elseif self.type == FLOAT then
            if control == INPUT_CONTROL_NUMBER or control == nil then
                valueType = "Float"
                default = default or "0.0"
            elseif control == INPUT_CONTROL_SLIDER then
                valueType = string.format("Range (%.2f, %.2f)", min or 0.0, max or 1.0)
                default = default or "0.0"
            end
        elseif self.type == VEC2 or self.type == VEC3 or self.type == VEC4 then
            if control == INPUT_CONTROL_COLOR then
                valueType = "Color"
            else
                valueType = "Vector"
            end
        end

        local code = string.format('%s  ("%s", %s)%s',
            uniformName, name, valueType, (default and (" = "..default)) or "")

        if valueType == "2D" then
            code = "[NoScaleOffset] "..code
        end

        return code
    end,

    unity_uniform = function(self)
        return string.format("uniform %s %s;", self.value_type, self.name)
    end,

    -- Convert vertex outputs into shader code
    unity_vertex_output = function(self)
        if type(self) == 'string' then
            return self
        elseif self.input_name == TAG_INPUT_VERTEX_OFFSET then
            return string.format("v.vertex.xyz += %s;", self.code)
        end
    end,

    -- Convert fragment/surface outputs into shader code
    unity_surface_output = function(self)
        if type(self) == 'string' then
            return self
        elseif SURFACE_OUTPUTS[self.input_name] then
            return string.format("surfaceData.%s = %s;", SURFACE_OUTPUTS[self.input_name], self.code)
        end
    end,

    -- Convert render queue into appropriate unity shader tags
    unity_render_queue = function(self)
        return UNITY_RENDER_QUEUE_MAP[self[TAG_RENDER_QUEUE]]
    end,

    unity_render_type = function(self)
        return UNITY_RENDER_TYPE_MAP[self[TAG_RENDER_QUEUE]]
    end,

    unity_depth_write = function(self)
        if self[TAG_DEPTH_WRITE] then
            return "ZWrite On"
        else
            return "ZWrite Off"
        end
    end,

    unity_blend = function(self)
        local blendOps = UNITY_BLEND_MAP[self[TAG_BLEND_MODE]]
        return string.format("Blend %s %s", blendOps[1], blendOps[2])
    end,

    unity_lighting = function(self)
        if type(self) == 'string' then
            return self
        else
            return string.format("float4 outgoingLight = float4(%s, s.Alpha);", self.code)
        end
    end
}

-- Lookup tables for various shader syntax
local UNITY_TEXCOORD =
{
    [TAG_VERT] = "input.uv0",
    [TAG_FRAG] = "input.uv0",
    [TAG_LIGHTING_FUNC] = "???"
}

local UNITY_COLOR =
{
    [TAG_VERT] = "input.color",
    [TAG_FRAG] = "input.color",
    [TAG_LIGHTING_FUNC] = "???"
}

local UNITY_POSITION =
{
    [TAG_VERT] =
    {
        [OBJECT_SPACE] = "input.positionOS",
        [VIEW_SPACE] = "vertexInputs.positionVS",
        [WORLD_SPACE] = "vertexInputs.positionWS",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 0.0)",
        [CLIP_SPACE] = "vertexInputs.positionCS",
    },

    [TAG_FRAG] =
    {
        [OBJECT_SPACE] = "TransformWorldToObject(input.positionWSAndFogFactor.xyz)",
        [VIEW_SPACE] = "TransformWorldToView(input.positionWSAndFogFactor.xyz)",
        [WORLD_SPACE] = "input.positionWSAndFogFactor.xyz",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 0.0)", -- TODO,
        [CLIP_SPACE] = "input.positionCS",
    },

    [TAG_LIGHTING_FUNC] =
    {
        [OBJECT_SPACE] = "s.IN.objectPos",
        [VIEW_SPACE] = "s.IN.viewPos",
        [WORLD_SPACE] = "s.IN.worldPos",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 0.0)", -- TODO
    }
}

local UNITY_NORMAL =
{
    [TAG_VERT] =
    {
        [OBJECT_SPACE] = "input.normalOS",
        [VIEW_SPACE] = "TransformWorldToViewDir(vertexNormalInput.normalWS)",
        [WORLD_SPACE] = "vertexNormalInput.normalWS",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 1.0)",
    },

    [TAG_FRAG] =
    {
        [OBJECT_SPACE] = "TransformWorldToObjectNormal(input.normalWS)",
        [VIEW_SPACE] = "TransformWorldToViewDir(input.normalWS)",
        [WORLD_SPACE] = "input.normalWS",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 1.0)",
    },

    [TAG_LIGHTING_FUNC] =
    {
        [VIEW_SPACE] = "TransformWorldToViewDir(input.normalWS)",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 1.0)",
    }
}

local UNITY_VIEW_DIR =
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
        [OBJECT_SPACE] = "TransformWorldToObjectDir(viewDirectionWS)",
        [VIEW_SPACE] = "TransformWorldToViewDir(viewDirectionWS)",
        [WORLD_SPACE] = "viewDirectionWS",
        [TANGENT_SPACE] = "TransformWorldToTangent(viewDirectionWS)",
    },

    [TAG_LIGHTING_FUNC] =
    {
        [OBJECT_SPACE] = "???",
        [VIEW_SPACE] = "???",
        [WORLD_SPACE] = "???",
        [TANGENT_SPACE] = "???",
    }
}

local UNITY_LIGHT_DIR =
{
    [VIEW_SPACE] = "gi.light.dir",
    [WORLD_SPACE] = "mul(transpose(UNITY_MATRIX_V), float4(gi.light.dir, 0.0)).xyz",
}

local UNITY_CONVERT_SPACE_VERT =
{
    [OBJECT_SPACE] =
    {
        [VIEW_SPACE] = "float3 objectToViewSpace(in appdata_full v, in float4 p) { return mul(UNITY_MATRIX_MV, p).xyz; }",
        [WORLD_SPACE] = "float3 objectToWorldSpace(in appdata_full v, in float4 p) { return mul(unity_ObjectToWorld, p).xyz; }",
        [TANGENT_SPACE] = "float3 objectToTangentSpace(in appdata_full v, in float4 p) { return p; }",
    },

    [VIEW_SPACE] =
    {
        [OBJECT_SPACE] = "float3 viewToObjectSpace(in appdata_full v, float4 p) { return mul(inverse(UNITY_MATRIX_MV), p).xyz; }",
        [WORLD_SPACE] = "float3 viewToWorldSpace(in appdata_full v, float4 p) { return mul(inverse(UNITY_MATRIX_V), p).xyz; }",
        [TANGENT_SPACE] = "float3 viewToTangentSpace(in appdata_full v, float4 p) { return p; }"
    },

    [WORLD_SPACE] =
    {
        [OBJECT_SPACE] = "float3 worldToObjectSpace(in appdata_full v, float4 p) { return mul(unity_WorldToObject, p).xyz; }",
        [VIEW_SPACE] = "float3 worldToViewSpace(in appdata_full v, float4 p) { return mul(UNITY_MATRIX_MV, mul(unity_WorldToObject, p)).xyz; }",
        [TANGENT_SPACE] = "float3 worldToTangentSpace(in appdata_full v, float4 p) { return p; }"
    },

    [TANGENT_SPACE] =
    {
        [OBJECT_SPACE] = "",
        [VIEW_SPACE] = "",
        [WORLD_SPACE] = "float3 tangentToWorldSpace(in appdata_full v, float4 p) { TANGENT_SPACE_ROTATION; return mul(rotation, p); }"
    }
}

local UNITY_CONVERT_SPACE_FRAG =
{
    [OBJECT_SPACE] =
    {
        [VIEW_SPACE] = "float3 objectToViewSpace(Input IN, in float4 p) { return mul(UNITY_MATRIX_MV, p).xyz; }",
        [WORLD_SPACE] = "float3 objectToWorldSpace(Input IN, in float4 p) { return mul(unity_ObjectToWorld, p).xyz; }",
        [TANGENT_SPACE] = "float3 objectToTangentSpace(Input IN, in float4 p) { return p; }",
        [CLIP_SPACE] = "float3 objectToClipSpace(Input IN, in float4 p) { return mul(UNITY_MATRIX_MVP, p).xyz; }",
    },

    [VIEW_SPACE] =
    {
        [OBJECT_SPACE] = "float3 viewToObjectSpace(Input IN, float4 p) { return mul(inverse(UNITY_MATRIX_MV), p).xyz; }",
        [WORLD_SPACE] = "float3 viewToWorldSpace(Input IN, float4 p) { return mul(inverse(UNITY_MATRIX_V), p).xyz; }",
        [TANGENT_SPACE] = "float3 viewToTangentSpace(Input IN, float4 p) { return p; }"
    },

    [WORLD_SPACE] =
    {
        [OBJECT_SPACE] = "float3 worldToObjectSpace(Input IN, float4 p) { return mul(unity_WorldToObject, p).xyz; }",
        [VIEW_SPACE] = "float3 worldToViewSpace(Input IN, float4 p) { return mul(UNITY_MATRIX_MV, mul(unity_WorldToObject, p)).xyz; }",
        [TANGENT_SPACE] = "float3 worldToTangentSpace(Input IN, float4 p) { return p; }"
    },

    [TANGENT_SPACE] =
    {
        [OBJECT_SPACE] = "",
        [VIEW_SPACE] = "",
        [WORLD_SPACE] = "float3 tangentToWorldSpace(in appdata_full v, float4 p) { TANGENT_SPACE_ROTATION; return mul(rotation, p); }"
    }
}

local UNITY_CONVERT_SPACE =
{
    [TAG_VERT] = UNITY_CONVERT_SPACE_VERT,
    [TAG_FRAG] = UNITY_CONVERT_SPACE_FRAG,
}

-- Exporters require syntax for various primitive elements to be defined
UnityExport.syntax =
{
    uv = function(self, index)
        if self:func() == TAG_LIGHTING_FUNC then
            return UNITY_TEXCOORD[self:func()]
        end

        return UNITY_TEXCOORD[self:tag()]
    end,

    color = function(self, index)
        if self:func() == TAG_LIGHTING_FUNC then
            return UNITY_COLOR[self:func()]
        end

        return UNITY_COLOR[self:tag()]
    end,

    position = function(self, space)
        if self:func() == TAG_LIGHTING_FUNC then
            return UNITY_POSITION[self:func()][space]
        end

        return UNITY_POSITION[self:tag()][space]
    end,

    normal = function(self, space)
        return UNITY_NORMAL[self:tag()][space]
    end,

    viewDir = function(self, space)
        if self:func() == TAG_LIGHTING_FUNC then
            -- TODO: non view space normals
            return UNITY_VIEW_DIR[self:func()][space]
        end

        if space == WORLD_SPACE and self:tag() == TAG_FRAG then
            self.viewModel[TAG_READ_WORLD_POS] = true
        end

        return UNITY_VIEW_DIR[self:tag()][space]
    end,

    lightDir = function(self, space)
        if self:func() == TAG_LIGHTING_FUNC then
            return UNITY_LIGHT_DIR[space]
        end
        return "half3(0.0, 0.0, 1.0)"
    end,

    lightType = function(self)
        if self:func() == TAG_LIGHTING_FUNC then
            return "0.0"
        end
        return "0.0"
    end,

    lightColor = function(self)
        if self:func() == TAG_LIGHTING_FUNC then
            return "gi.light.color"
        end
        return "half3(1.0, 1.0, 1.0)"
    end,

    convertSpace = function(self, value, from, to, w)
        if from == to then return value end
        if to == CLIP_SPACE and from ~= OBJECT_SPACE then return value end

        local conversionFunction = nil

        conversionFunction = string.format("%sTo%sSpace", from, to:titlecase())

        -- Inject conversion function
        self:lineUnique(self:funcTag(), UNITY_CONVERT_SPACE[self:tag()][from][to])

        if self:tag() == TAG_FRAG then
            return string.format("%s(IN, float4(%s, %s))", conversionFunction, value, w)
        else
            return string.format("%s(v, float4(%s, %s))", conversionFunction, value, w)
        end

        return value
    end,

    texture2D = function(self, sampler, uv)
        return string.format("tex2D(%s, %s)", sampler, uv)
    end,

    unpackNormal = function(self, normalMapRead)
        return string.format("UnpackNormal(%s)", normalMapRead)
    end,

    texture2DLod = function(self, sampler, uv, lod)
        return string.format("tex2Dlod(%s, float4(%s, 0.0, %s))", sampler, uv, lod)
    end,

    textureSize = function(self, tex)
        self:addUniform(tex, "sampler2D")
        local uniform = self:addUniform(tex.."_TexelSize", VEC4)
        return uniform..".zw"
    end,

    cameraPosition = function(self)
        return "_WorldSpaceCameraPos.xyz"
    end,

    sceneDepth = function(self, screenPos)
        return string.format("sceneDepth(%s)", screenPos)
    end,

    depth = function(self)
        if self:tag() == TAG_SURF or self:tag() == TAG_FRAG then
            return string.format("-%s.z", self:position(VIEW_SPACE))
        else
            return "-vertexInputs.positionVS.z"
        end
    end,

    frontFacing = function(self)
        if self:tag() == TAG_SURF or self:tag() == TAG_SURF then
            return "(facing == 1.0)"
        else
            return "false"
        end
    end,

    screenParams = function(self)
        return "_ScaledScreenParams"
    end,

    screenPos = function(self)
        if self:tag() == TAG_SURF or self:tag() == TAG_FRAG then
            return "(input.positionCS.xy / _ScaledScreenParams.xy)"
        else
            return "(output.positionCS.xy / _ScaledScreenParams.xy)"
        end
    end,

    sceneColor = function(self, screenPos)
        return string.format("sceneColor(%s)", screenPos)
    end,

    -- TODO implement instanceID functionality
    instanceID = function(self)
        return "0.0"
    end,

    -- TODO implement vertexID functionality
    vertexID = function(self)
        return "0.0"
    end,

    -- TODO implement barycentric functionality
    barycentric = function(self)
        return "vec3(0.0, 0.0, 0.0)"
    end,

    parallax = function(self, uv)
        local tangentViewDir = self:viewDir(TANGENT_SPACE)
        return string.format("parallax(%s, %s)", uv, tangentViewDir)
    end
}

return UnityExport
