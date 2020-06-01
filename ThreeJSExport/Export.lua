require 'Editor/Evaluator/GLSLEvaluator'

-- Templates use lustache for rendering: https://github.com/Olivine-Labs/lustache

local INDEX_TEMPLATE =
[[<html>
	<head>
		<title>{{name_no_spaces}} (three.js)</title>
		<style>
			body { margin: 0; }
			canvas { width: 100%; height: 100% }
		</style>
	</head>
	<body>
		<script src="js/three.js"></script>
		<script src="js/loaders/OBJLoader.js"></script>
        <script src="js/controls/OrbitControls.js"></script>
        <script src="js/shaders/{{name_no_spaces}}Shader.js"></script>
		<script>
			var scene = new THREE.Scene();
			var camera = new THREE.PerspectiveCamera( 75, window.innerWidth/window.innerHeight, 0.1, 1000 );

			var renderer = new THREE.WebGLRenderer();
			renderer.setPixelRatio( window.devicePixelRatio );
            renderer.debug.checkShaderErrors = true

			renderer.setSize( window.innerWidth, window.innerHeight );
			document.body.appendChild( renderer.domElement );

			var light = new THREE.AmbientLight( 0x404040 ); // soft white light
            scene.add( light );

            var sun = new THREE.DirectionalLight( 0xFFFFFF, 0.5 );
            sun.position.y = 5
            scene.add( sun )

            var helper = new THREE.DirectionalLightHelper( sun, 1 );
            scene.add( helper );

            var material = new THREE.ShaderMaterial( THREE.{{name_no_spaces}}Shader );

            // instantiate a loader
            var loader = new THREE.OBJLoader();

            // load a resource
            loader.load(
            	// resource URL
            	'models/ShaderBall.obj',
            	// called when resource is loaded
            	function ( object ) {

                    object.traverse(function ( child ) {
                        if ( child.isMesh )
                            child.material = material;
                        });

            		scene.add( object );
            	},
            	// called when loading is in progresses
            	function ( xhr ) {
            		console.log( ( xhr.loaded / xhr.total * 100 ) + '% loaded' );
            	},
            	// called when loading has errors
            	function ( error ) {
            		console.log( 'An error happened' );
            	}
            );

            var controls = new THREE.OrbitControls( camera );

            camera.position.z = 10;
            camera.position.y = 10;
            controls.update();

			var animate = function () {
				requestAnimationFrame( animate );

                controls.update();

				renderer.render( scene, camera );
			};

			animate();
		</script>
	</body>
</html>]]

local SHADER_TEMPLATE =
[[/**
 * @author Shade / https://shade.to
 *
 * Shader built with Shade
 */

THREE.{{name_no_spaces}}Shader = {

	uniforms:
    {{#physical}}
    THREE.UniformsUtils.merge( [
        THREE.UniformsLib[ "lights" ],
        {
        {{#properties}}
            {{{three_property}}},
        {{/properties}}
    }]),
    {{/physical}}
    {{#unlit}}
    {
    {{#properties}}
        {{{three_property}}},
    {{/properties}}
    },
    {{/unlit}}

	vertexShader: [

        "#define PHYSICAL",
		"#define STANDARD",

        "varying vec3 vViewPosition;",
        "#ifndef FLAT_SHADED",
        	"varying vec3 vNormal;",
        	"#ifdef USE_TANGENT",
        		"varying vec3 vTangent;",
        		"varying vec3 vBitangent;",
        	"#endif",
        "#endif",

        "#include <common>",

        "varying vec2 vUv;",

        "#include <displacementmap_pars_vertex>",
        "#include <color_pars_vertex>",
        "#include <fog_pars_vertex>",
        "#include <morphtarget_pars_vertex>",
        "#include <skinning_pars_vertex>",
        "#include <shadowmap_pars_vertex>",
        "#include <logdepthbuf_pars_vertex>",
        "#include <clipping_planes_pars_vertex>",

        {{#uniforms}}
        "{{{three_uniform}}}",
        {{/uniforms}}

		{{#vert_funcs}}
		{{{.}}}
		{{/vert_funcs}}

		"void main() {",

            "vUv = uv;",

            "#include <color_vertex>",
            "#include <beginnormal_vertex>",
            "#include <morphnormal_vertex>",
            "#include <skinbase_vertex>",
            "#include <skinnormal_vertex>",
            "#include <defaultnormal_vertex>",

            "#ifndef FLAT_SHADED // Normal computed with derivatives when FLAT_SHADED",
	           "vNormal = normalize( transformedNormal );",
            "#ifdef USE_TANGENT",
		       "vTangent = normalize( transformedTangent );",
		       "vBitangent = normalize( cross( vNormal, vTangent ) * tangent.w );",
	        "#endif",
            "#endif",

            "#include <begin_vertex>",
            "#include <morphtarget_vertex>",
            "#include <skinning_vertex>",
            "#include <displacementmap_vertex>",
            "#include <project_vertex>",
            "#include <logdepthbuf_vertex>",
            "#include <clipping_planes_vertex>",

            "vViewPosition = - mvPosition.xyz;",

            "#include <worldpos_vertex>",
            "#include <shadowmap_vertex>",
            "#include <fog_vertex>",

		"}"

	].join( "\n" ),

	fragmentShader: [

        "#define PHYSICAL",
        "#define STANDARD",

        "varying vec3 vViewPosition;",

        "#ifndef FLAT_SHADED",
        	"varying vec3 vNormal;",
        	"#ifdef USE_TANGENT",
        		"varying vec3 vTangent;",
        		"varying vec3 vBitangent;",
        	"#endif",
        "#endif",

        "#include <common>",

        "varying vec2 vUv;",

        "#include <packing>",
        "#include <dithering_pars_fragment>",
        "#include <color_pars_fragment>",
        "#include <map_pars_fragment>",
        "#include <alphamap_pars_fragment>",
        "#include <aomap_pars_fragment>",
        "#include <lightmap_pars_fragment>",
        "#include <bsdfs>",
        "#include <cube_uv_reflection_fragment>",
        "#include <envmap_pars_fragment>",
        "#include <envmap_physical_pars_fragment>",
        "#include <fog_pars_fragment>",
        "#include <lights_pars_begin>",
        "#include <lights_physical_pars_fragment>",
        "#include <shadowmap_pars_fragment>",
        "#include <bumpmap_pars_fragment>",
        "#include <normalmap_pars_fragment>",

        "#include <logdepthbuf_pars_fragment>",
        "#include <clipping_planes_pars_fragment>",

        {{#uniforms}}
        "{{{three_uniform}}}",
        {{/uniforms}}

		{{#frag_funcs}}
		{{{.}}}
		{{/frag_funcs}}

		"void main() {",
            {{#frag}}
            "{{{three_surface_output}}}",
            {{/frag}}

            {{#physical}}
            "float roughnessFactor = input_roughness;",
            "float metalnessFactor = input_metalness;",
            {{/physical}}

            "#include <clipping_planes_fragment>",
        	"vec4 diffuseColor = vec4( input_diffuse, input_opacity );",

            {{#physical}}
        	"ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );",
        	"vec3 totalEmissiveRadiance = input_emission;",

        	"#include <logdepthbuf_fragment>",
        	"#include <map_fragment>",
        	"#include <color_fragment>",
        	"#include <alphamap_fragment>",
        	"#include <alphatest_fragment>",

        	"#include <normal_fragment_begin>",
        	"#include <normal_fragment_maps>",

        	"// accumulation",
        	"#include <lights_physical_fragment>",
        	"#include <lights_fragment_begin>",
        	"#include <lights_fragment_maps>",
        	"#include <lights_fragment_end>",

        	"// modulation",
        	"#include <aomap_fragment>",
        	"vec3 outgoingLight = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse + reflectedLight.directSpecular + reflectedLight.indirectSpecular + totalEmissiveRadiance;",
        	"gl_FragColor = vec4( outgoingLight, diffuseColor.a );",
            {{/physical}}
            {{#unlit}}
            "gl_FragColor = vec4( diffuseColor.rgb + emissive, diffuseColor.a );",
            {{/unlit}}

        	"#include <tonemapping_fragment>",
        	"#include <encodings_fragment>",
        	"#include <fog_fragment>",
        	"#include <premultiplied_alpha_fragment>",
        	"#include <dithering_fragment>",
		"}"

	].join( "\n" ),

    {{#physical}}
    "lights" : true
    {{/physical}}

};]]

local ThreeJSExport = class(GLSLEvaluator)

function ThreeJSExport:init()
    GLSLEvaluator.init(self)
    self:addTemplate("index.html", INDEX_TEMPLATE)
    self:addTemplate("js/shaders/{{name_no_spaces}}Shader.js", SHADER_TEMPLATE)
end

function ThreeJSExport:clear()
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
ThreeJSExport.model =
{
    -- Convert property data into three properties
    three_property = function(self)

        local valueType = nil
        local default = nil
        local name = self.name
        local uniformName = self.uniform_name
        local control = self.options and self.options.control
        local default = self.default

        if default and type(default) == 'number' then
            default = string.format('%.2f', default)
        end

        if self.type == FLOAT then
            return string.format('"%s" : { value : %s}', uniformName, default )
        elseif self.type == VEC2 then
            return string.format('"%s" : { value : new THREE.Vector2( %.2f, %.2f ) }', uniformName, default[1], default[2])
        elseif self.type == VEC3 then
            return string.format('"%s" : { value : new THREE.Vector3( %.2f, %.2f, %.2f ) }', uniformName, default[1], default[2], default[3])
        elseif self.type == VEC4 then
            return string.format('"%s" : { value : new THREE.Vector4( %.2f, %.2f, %.2f, %.2f ) }', uniformName, default[1], default[2], default[3], default[4])
        end
    end,
    --
    -- -- Convert vertex outputs into shader code
    -- unity_vertex_output = function(self)
    --     if type(self) == 'string' then
    --         return self
    --     elseif self.input_name == TAG_INPUT_VERTEX_OFFSET then
    --         return string.format("v.vertex.xyz += %s;", self.code)
    --     end
    -- end,

    three_uniform = function(self)
        return string.format("uniform %s %s;", self.value_type, self.name)
    end,

    -- Convert fragment/surface outputs into shader code
    three_surface_output = function(self)
        if type(self) == 'string' then
            return self
        else
            return string.format("%s %s = %s;", self.value_type, self.input_name, self.code)
        end
    end,
    --
    -- -- Convert render queue into appropriate unity shader tags
    -- unity_render_queue = function(self)
    --     return UNITY_RENDER_QUEUE_MAP[self[TAG_RENDER_QUEUE]]
    -- end,
    --
    -- unity_render_type = function(self)
    --     return UNITY_RENDER_TYPE_MAP[self[TAG_RENDER_QUEUE]]
    -- end,
    --
    -- unity_depth_write = function(self)
    --     if self[TAG_DEPTH_WRITE] then
    --         return "ZWrite On"
    --     else
    --         return "ZWrite Off"
    --     end
    -- end,
    --
    -- unity_blend = function(self)
    --     local blendOps = UNITY_BLEND_MAP[self[TAG_BLEND_MODE]]
    --     return string.format("Blend %s %s", blendOps[1], blendOps[2])
    -- end
}

-- Lookup tables for various shader syntax
local THREE_TEXCOORD =
{
    [TAG_VERT] = "uv",
    [TAG_FRAG] = "vUv"
}

local THREE_COLOR =
{
    [TAG_VERT] = "color",
    [TAG_FRAG] = "vColor"
}

local THREE_POSITION =
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
        [OBJECT_SPACE] = "???",
        [VIEW_SPACE] = "vViewPosition",
        [WORLD_SPACE] = "worldPosition",
        [TANGENT_SPACE] = "vec3(0.0, 0.0, 0.0)", -- TODO
    }
}

local THREE_NORMAL =
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

local THREE_VIEW_DIR =
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
ThreeJSExport.syntax =
{
    uv = function(self, index) return THREE_TEXCOORD[self:tag()] end,

    color = function(self, index) return THREE_COLOR[self:tag()] end,

    -- position = function(self, space)
    --     return UNITY_POSITION[self:tag()][space]
    -- end,
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

return ThreeJSExport
