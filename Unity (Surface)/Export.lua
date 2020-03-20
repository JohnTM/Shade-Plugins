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

        Tags { "Queue"="{{unity_render_queue}}" "RenderType"="{{unity_render_type}}" }
        {{#blend_enabled}}
        {{unity_blend}}
        {{/blend_enabled}}
        {{unity_depth_write}}
        LOD 200

        CGPROGRAM

        #pragma target 4.0
        {{#physical}}

        // Physically based Standard lighting model, and enable shadows on all light types
        #pragma surface surf Standard vertex:vert{{#behind}} finalcolor:customColor{{/behind}} fullforwardshadows addshadow
        {{/physical}}
        {{#unlit}}

        // Unlit model
        #pragma surface surf NoLighting vertex:vert{{#behind}} finalcolor:customColor{{/behind}} noforwardadd addshadow

        fixed4 LightingNoLighting(SurfaceOutput s, fixed3 lightDir, fixed atten)
        {
            fixed4 c;
            c.rgb = s.Albedo + s.Emission.rgb;
            c.a = s.Alpha;
            return c;
        }

        {{/unlit}}
        struct Input {
            float2 texcoord : TEXCOORD0;
        {{#read_screen_pos}}
            float4 screenPos : TEXCOORD1;
        {{/read_screen_pos}}
        {{#read_depth}}
            float eyeDepth;
        {{/read_depth}}
        {{#read_view_dir}}
            float3 viewDirection;
        {{/read_view_dir}}
        {{#read_tangent_view_dir}}
            float3 tangentViewDir;
        {{/read_tangent_view_dir}}
        {{#read_world_pos}}
            float3 worldPos;
        {{/read_world_pos}}
        {{#read_object_pos}}
            float3 objectPos;
        {{/read_object_pos}}
        {{#read_world_normal}}
            float3 worldNormal; {{#write_normal}}INTERNAL_DATA{{/write_normal}}
        {{/read_world_normal}}
        {{#read_normal}}
            float3 normal;
        {{/read_normal}}
        {{#read_view_pos}}
            float3 viewPos;
        {{/read_view_pos}}
        {{#read_facing}}
            float facing : VFACE;
        {{/read_facing}}
            float4 color : COLOR;
        };

        {{#uniforms}}
        {{{unity_uniform}}}
        {{/uniforms}}
        {{#grab_pass}}

        sampler2D _BackgroundTexture;

        {{/grab_pass}}
        {{#read_depth_texture}}

        sampler2D_float _CameraDepthTexture;
        float4 _CameraDepthTexture_TexelSize;

        {{/read_depth_texture}}
        {{#vert_funcs}}
        {{{.}}}
        {{/vert_funcs}}
        {{#frag_funcs}}
        {{{.}}}
        {{/frag_funcs}}
        {{#physical}}
        {{#behind}}

        #include "UnityPBSLighting.cginc"
        void customColor (Input IN, SurfaceOutputStandard o, inout fixed4 color)
        {
        #ifndef UNITY_PASS_FORWARDADD
        {{{behind}}}
        #endif
        }

        {{/behind}}
        {{/physical}}
        {{#unlit}}
        {{#behind}}

        void customColor (Input IN, SurfaceOutput o, inout fixed4 color)
        {
        #ifndef UNITY_PASS_FORWARDADD
        {{{behind}}}
        #endif
        }

        {{/behind}}
        {{/unlit}}
        void vert (inout appdata_full v, out Input o)
        {
            UNITY_INITIALIZE_OUTPUT(Input, o);
            o.texcoord = v.texcoord;
        {{#read_depth}}
            COMPUTE_EYEDEPTH(o.eyeDepth);
        {{/read_depth}}
        {{#read_normal}}
            o.normal = COMPUTE_VIEW_NORMAL;
        {{/read_normal}}
        {{#read_view_pos}}
            o.viewPos = UnityObjectToViewPos(v.vertex.xyz);
        {{/read_view_pos}}
        {{#read_view_dir}}
            o.viewDirection = -UnityObjectToViewPos(v.vertex.xyz);
        {{/read_view_dir}}
        {{#read_object_pos}}
            o.objectPos = v.vertex.xyz;
        {{/read_object_pos}}
        {{#read_tangent_view_dir}}
            float3x3 objectToTangent = float3x3(
                v.tangent.xyz,
                cross(v.normal, v.tangent.xyz) * v.tangent.w,
                v.normal);
            o.tangentViewDir = mul(objectToTangent, ObjSpaceViewDir(v.vertex));
        {{/read_tangent_view_dir}}
        {{#read_screen_pos}}
            o.screenPos = ComputeGrabScreenPos(UnityObjectToClipPos(v.vertex));
        {{/read_screen_pos}}
        {{#vert}}
            {{{unity_vertex_output}}}
        {{/vert}}
        }

        {{#physical}}
        void surf (Input IN, inout SurfaceOutputStandard o)
        {{/physical}}
        {{#unlit}}
        void surf (Input IN, inout SurfaceOutput o)
        {{/unlit}}
        {
        {{#frag}}
            {{{unity_surface_output}}}
        {{/frag}}
        }
        ENDCG
    }
}
]]

UnityExport = class(HLSLEvaluator)

function UnityExport:init()
    HLSLEvaluator.init(self)
    self:addTemplate("Unity.shader", template)
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
        [TAG_FRAG_FUNCS] = {}
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

local SURFACE_OUTPUTS =
{
    [TAG_INPUT_DIFFUSE] = "Albedo",
    [TAG_INPUT_EMISSION] = "Emission",
    [TAG_INPUT_NORMAL] = "Normal",
    [TAG_INPUT_OPACITY] = "Alpha",
    [TAG_INPUT_SMOOTHNESS] = "Smoothness",
    [TAG_INPUT_METALNESS] = "Metallic",
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
            default = '"white" = {}'
        elseif self.type == FLOAT then
            if control == INPUT_CONTROL_NUMBER then
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
            return string.format("o.%s = %s;", SURFACE_OUTPUTS[self.input_name], self.code)
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
    end
}

-- Lookup tables for various shader syntax
local UNITY_TEXCOORD =
{
    [TAG_VERT] = "v.texcoord",
    [TAG_FRAG] = "IN.texcoord"
}

local UNITY_COLOR =
{
    [TAG_VERT] = "v.color",
    [TAG_FRAG] = "IN.color"
}

local UNITY_POSITION =
{
    [TAG_VERT] =
    {
        [OBJECT_SPACE] = "v.vertex",
        [VIEW_SPACE] = "UnityObjectToViewPos(v.vertex.xyz)",
        [WORLD_SPACE] = "mul(float4(v.vertex, 1.0), unity_ObjectToWorld).xyz",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 0.0)", -- TODO
    },

    [TAG_FRAG] =
    {
        [OBJECT_SPACE] = "IN.objectPos",
        [VIEW_SPACE] = "IN.viewPos",
        [WORLD_SPACE] = "IN.worldPos",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 0.0)", -- TODO
    }
}

local UNITY_NORMAL =
{
    [TAG_VERT] =
    {
        [OBJECT_SPACE] = "v.normal",
        [VIEW_SPACE] = "o.normal",
        [WORLD_SPACE] = "normalize( mul( float4( v.normal, 0.0 ), unity_ObjectToWorld ).xyz )",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 1.0)",
    },

    [TAG_FRAG] =
    {
        -- [OBJECT_SPACE] *special-case*
        [VIEW_SPACE] = "normalize(IN.normal)",
        -- [WORLD_SPACE] *special-case*
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 1.0)",
    }
}

local UNITY_VIEW_DIR =
{
    [TAG_VERT] =
    {
        [OBJECT_SPACE] = "normalize(ObjSpaceViewDir(v.vertex).xyz)",
        [VIEW_SPACE] = "normalize(-UnityObjectToViewPos(v.vertex.xyz))",
        [WORLD_SPACE] = "normalize(WorldSpaceViewDir(v.vertex).xyz)",
        [TANGENT_SPACE] = "normalize(o.tangentViewDir)",
    },

    [TAG_FRAG] =
    {
        [OBJECT_SPACE] = "",
        [VIEW_SPACE] = "normalize(IN.viewDirection)",
        [WORLD_SPACE] = "normalize(_WorldSpaceCameraPos - IN.worldPos)",
        [TANGENT_SPACE] = "normalize(IN.tangentViewDir)",
    }
}


-- Exporters require syntax for various primitive elements to be defined
UnityExport.syntax =
{
    uv = function(self, index) return UNITY_TEXCOORD[self:tag()] end,

    color = function(self, index) return UNITY_COLOR[self:tag()] end,

    position = function(self, space)
        return UNITY_POSITION[self:tag()][space]
    end,

    normal = function(self, space)

        -- Exception for object/world space normals in surface shader (due to special behaviour when writing custom normals)
        if space == OBJECT_SPACE and self:tag() == TAG_FRAG then
            return string.format("normalize( mul( float4(%s , 0.0 ), unity_WorldToObject ).xyz )", self:normal(WORLD_SPACE))
        elseif space == WORLD_SPACE and self:tag() == TAG_FRAG then
            if self.viewModel[TAG_WRITE_NORMAL] then
                return "WorldNormalVector(IN, float3(0, 0, 1))"
            else
                return "normalize(IN.worldNormal)"
            end
        end

        return UNITY_NORMAL[self:tag()][space]
    end,

    viewDir = function(self, space)
        if space == WORLD_SPACE and self:tag() == TAG_FRAG then
            self.viewModel[TAG_READ_WORLD_POS] = true
        end

        return UNITY_VIEW_DIR[self:tag()][space]
    end,

    texture2D = function(self, sampler, uv)
        return string.format("tex2D(%s, %s)", sampler, uv)
    end,

    texture2DLod = function(self, sampler, uv, lod)
        return string.format("tex2DLod(%s, %s)", sampler, uv)
    end,

    textureSize = function(self, tex)
        return "vec2(0.0, 0.0)"
    end,

    cameraPosition = function(self)
        return "_WorldSpaceCameraPos.xyz"
    end,

    sceneDepth = function(self, screenPos)
        return string.format("LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, %s/%s))", screenPos, self:screenPos():gsub(".xy", ".w"))
    end,

    depth = function(self)
        if self:tag() == TAG_SURF or self:tag() == TAG_FRAG then
            return "IN.eyeDepth"
        else
            return "o.eyeDepth"
        end
    end,

    frontFacing = function(self)
        if self:tag() == TAG_SURF or self:tag() == TAG_SURF then
            return "(facing == 1.0)"
        else
            return "false"
        end
    end,

    screenPos = function(self)
        if self:tag() == TAG_SURF or self:tag() == TAG_FRAG then
            return "IN.screenPos.xy"
        else
            return "(o.screenPos.xy)"
        end
    end,

    sceneColor = function(self, screenPos)
        return string.format("tex2D(_BackgroundTexture, %s/%s)", screenPos, self:screenPos():gsub(".xy", ".w"))
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
