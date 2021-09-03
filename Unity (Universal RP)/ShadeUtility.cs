using System.Collections;
using System.Collections.Generic;
using System.IO;
using System;

using UnityEngine;
using UnityEditor;

// This utiity provides a simple editor window that lists all Shade shaders and automatically creates and configures materials for them
public class ShadeUtility : EditorWindow 
{
    // Classes for parsing Graph.json files
    [Serializable]
    public class Options
    {
        public string userLabel;
        public string value;
        public string wrapMode;
        public string filterMode;
        public bool isNormalMap;
        public bool generateMipmaps;
    }

    [Serializable]
    public class ShaderNode 
    {
        public string name;
        public Options options;
    }

    [Serializable]
    public class ShaderGraph
    {
        public List<ShaderNode> nodes;
    }

    private Shader[] shaders;
    private Vector2 scrollPosition = Vector2.zero;

    [MenuItem("Window/Shade Utility")]
    public static void ShowWindow()
    {
        EditorWindow shadeWindow = EditorWindow.GetWindow(typeof(ShadeUtility));
        shadeWindow.ShowPopup();
    }

    bool MaterialExists(Shader shader)
    {
        return GetMaterial(shader) != null;
    }

    // Try to find an existing material for a given shader
    Material GetMaterial(Shader shader)
    {
        string shaderPath = AssetDatabase.GetAssetPath(shader);
        string shaderParentPath = Path.GetDirectoryName(Path.GetDirectoryName(shaderPath));
        string shaderName = shader.name.Substring("Shade/".Length);
        string materialPath = Path.Combine(shaderParentPath, shaderName);
        Material material = AssetDatabase.LoadAssetAtPath<Material>(materialPath + ".mat");
        return material;
    }

    // Create a material instance of a given shader and configure textures and such
    void CreateMaterial(Shader shader)
    {
        string shaderPath = AssetDatabase.GetAssetPath(shader);
        string shaderDirectory = Path.GetDirectoryName(shaderPath);                                    
        string shaderParentPath = Path.GetDirectoryName(Path.GetDirectoryName(shaderPath));
        string shaderName = shader.name.Substring("Shade/".Length);
        string materialPath = Path.Combine(shaderParentPath, shaderName);

        Material material = AssetDatabase.LoadAssetAtPath<Material>(materialPath+".mat");

        if (material == null)
        {
            material = new Material(shader);
            AssetDatabase.CreateAsset(material, materialPath+".mat");
        }

        material.shader = shader;      

        // Find the Graph.json file for this shader, find any Texture nodes and properly configure the associated material properties for them
        TextAsset shaderGraphAsset = AssetDatabase.LoadAssetAtPath<TextAsset>(Path.Combine(shaderDirectory, "Graph.json"));
        ShaderGraph graph = JsonUtility.FromJson<ShaderGraph>(shaderGraphAsset.text);
        ShaderImporter shaderImporter = ShaderImporter.GetAtPath(shaderPath) as ShaderImporter;

        string[] textureTypes = {
            "Texture",
            "Gradient",
            "Bake",
            "Tiler"
        };

        foreach (ShaderNode n in graph.nodes)
        {
            if (n.options.userLabel != null)
            {
                string lowercaseName = Char.ToLowerInvariant(n.options.userLabel[0]) + n.options.userLabel.Substring(1);
                string propertyName = "_" + lowercaseName.Replace(" ", "");

                if (Array.Exists(textureTypes, element => element == n.name))
                {
                    string textureName = n.options.value != null ? n.options.value : n.options.userLabel;
                    Texture2D tex = AssetDatabase.LoadAssetAtPath<Texture2D>(Path.Combine(shaderDirectory, textureName + ".png"));
                    if (tex != null)
                    {
                        material.SetTexture(propertyName, tex);
                        shaderImporter.SetDefaultTextures(new[] {propertyName}, new[] {tex});

                        string texturePath = AssetDatabase.GetAssetPath(tex);
                        TextureImporter importer = (TextureImporter)AssetImporter.GetAtPath(texturePath);

                        if (n.options.wrapMode != null)
                        {
                            switch(n.options.wrapMode)
                            {
                                case "repeat":
                                importer.wrapMode = TextureWrapMode.Repeat;
                                break;
                                case "clamp":
                                importer.wrapMode = TextureWrapMode.Clamp;
                                break;
                                case "mirror":
                                importer.wrapMode = TextureWrapMode.Mirror;
                                break;
                            }
                        }
                        else 
                        {
                            importer.wrapMode = TextureWrapMode.Clamp;
                        }

                        if (n.options.filterMode != null)
                        {
                            switch(n.options.filterMode)
                            {
                                case "point":
                                importer.filterMode = FilterMode.Point;
                                break;
                                case "linear":
                                importer.filterMode = n.options.generateMipmaps ? FilterMode.Trilinear : FilterMode.Bilinear;
                                break;
                            }
                        }
                    
                        importer.textureType = n.options.isNormalMap ? TextureImporterType.NormalMap : TextureImporterType.Default;

                        importer.SaveAndReimport();                        
                    }                
                }            
            }
        }
    }

    // Apply the material to all renderers in a GameObject
    void ApplyMaterial(GameObject target, Material material)
    {
        Renderer[] renderers = target.transform.GetComponentsInChildren<Renderer>();
        foreach (Renderer r in renderers)
        {
            r.material = material;    
        }
    }

    void OnInspectorUpdate()
    {
        // Call Repaint on OnInspectorUpdate as it repaints the windows
        // less times as if it was OnGUI/Update
        Repaint();
    }

    void OnGUI()
    {
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorStyles.label.wordWrap = true;
        GUILayout.Label("Shaders", EditorStyles.boldLabel);
        GUILayout.Label("All shaders generated in Shade are listed here.", EditorStyles.label);
        GUILayout.Label("You can create a new material based on these shaders or update existing ones.", EditorStyles.label);
        EditorGUILayout.EndVertical();

        EditorGUILayout.BeginVertical();

        scrollPosition = EditorGUILayout.BeginScrollView(scrollPosition);

        shaders = Resources.FindObjectsOfTypeAll<Shader>();

        for (int i = 0; i < shaders.Length; i++)
        {
            if (shaders[i] != null)
            {
                Shader s = shaders[i];
                if (s.name.StartsWith("Shade/", System.StringComparison.InvariantCulture))
                {
                    EditorGUILayout.BeginHorizontal();

                    EditorGUILayout.PrefixLabel(s.name.Replace("Shade/", ""));

                    GUILayout.FlexibleSpace();

                    bool matExists = MaterialExists(s);

                    if (GUILayout.Button(matExists ? "Update Material" : "Create Material", GUILayout.Width(100), GUILayout.Height(30)))
                    {
                        CreateMaterial(s);

                    }

                    EditorGUI.BeginDisabledGroup(matExists == false || Selection.activeGameObject == null);
                    if (GUILayout.Button("Apply", GUILayout.Width(55), GUILayout.Height(30)))
                    {
                        ApplyMaterial(Selection.activeGameObject, GetMaterial(s));
                    }
                    EditorGUI.EndDisabledGroup();

                    if (GUILayout.Button("Select", GUILayout.Width(55), GUILayout.Height(30)))
                    {
                        Selection.activeObject = GetMaterial(s);
                    }

                    EditorGUILayout.EndHorizontal();
                }

            }
        }

        EditorGUILayout.EndScrollView();

        EditorGUILayout.EndVertical();
    }
}
