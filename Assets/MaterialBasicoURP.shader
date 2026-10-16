Shader "Clase/Material Basico URP"
{
    Properties
    {
        [MainTexture]
        [NoScaleOffset]
        _BaseMap("Base Color", 2D) = "white" {}

        [Normal]
        [NoScaleOffset]
        _NormalMap("Normal Map", 2D) = "bump" {}

        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        LOD 300

        Pass
        {
            Name "ForwardLit"

            Tags
            {
                "LightMode" = "UniversalForward"
            }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM

            #pragma vertex Vertex
            #pragma fragment Fragment
            #pragma target 3.0

            // Sombras de la luz principal
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_SCREEN

            // Luces adicionales
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            // Sombras suaves, niebla e instancing
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            // Bibliotecas de URP
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // Necesario para decodificar el normal map
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"

            // =================================================
            // TEXTURAS
            // =================================================

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            // =================================================
            // PROPIEDADES DEL MATERIAL
            // =================================================

            CBUFFER_START(UnityPerMaterial)

                half _Smoothness;

            CBUFFER_END

            // =================================================
            // DATOS DE ENTRADA DEL VERTEX SHADER
            // =================================================

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // =================================================
            // DATOS QUE VIAJAN AL FRAGMENT SHADER
            // =================================================

            struct Varyings
            {
                float4 positionCS : SV_POSITION;

                float3 positionWS : TEXCOORD0;
                half3 normalWS    : TEXCOORD1;
                half4 tangentWS   : TEXCOORD2;

                float2 uv         : TEXCOORD3;

                float4 shadowCoord : TEXCOORD4;
                half fogFactor     : TEXCOORD5;

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // =================================================
            // VERTEX SHADER
            // =================================================

            Varyings Vertex(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                // Posición en World Space y Clip Space
                VertexPositionInputs positionInputs =
                    GetVertexPositionInputs(input.positionOS.xyz);

                output.positionWS =
                    positionInputs.positionWS;

                output.positionCS =
                    positionInputs.positionCS;

                // Normal y tangente en World Space
                VertexNormalInputs normalInputs =
                    GetVertexNormalInputs(
                        input.normalOS,
                        input.tangentOS
                    );

                output.normalWS =
                    normalInputs.normalWS;

                output.tangentWS = half4(
                    normalInputs.tangentWS,
                    input.tangentOS.w * GetOddNegativeScale()
                );

                // Utilizamos directamente las UV del modelo.
                // No hay Tiling ni Offset.
                output.uv = input.uv;

                // Datos para sombras y niebla
                output.shadowCoord =
                    GetShadowCoord(positionInputs);

                output.fogFactor =
                    ComputeFogFactor(positionInputs.positionCS.z);

                return output;
            }

            // =================================================
            // FRAGMENT SHADER
            // =================================================

            half4 Fragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // -------------------------------------------------
                // 1. TEXTURA DE BASE COLOR
                // -------------------------------------------------

                half4 baseColor = SAMPLE_TEXTURE2D(
                    _BaseMap,
                    sampler_BaseMap,
                    input.uv
                );

                // -------------------------------------------------
                // 2. NORMAL MAP
                // -------------------------------------------------

                half4 packedNormal = SAMPLE_TEXTURE2D(
                    _NormalMap,
                    sampler_NormalMap,
                    input.uv
                );

                // La normal almacenada en la textura está codificada.
                // Hay que desempaquetarla.
                half3 normalTS =
                    UnpackNormal(packedNormal);

                // -------------------------------------------------
                // 3. BASE TANGENTE
                // -------------------------------------------------

                half3 vertexNormalWS =
                    normalize(input.normalWS);

                half3 tangentWS =
                    normalize(input.tangentWS.xyz);

                half3 bitangentWS =
                    cross(vertexNormalWS, tangentWS)
                    * input.tangentWS.w;

                half3x3 tangentToWorld = half3x3(
                    tangentWS,
                    bitangentWS,
                    vertexNormalWS
                );

                // -------------------------------------------------
                // 4. NORMAL MAP: TANGENT SPACE → WORLD SPACE
                // -------------------------------------------------

                half3 normalWS = TransformTangentToWorld(
                    normalTS,
                    tangentToWorld
                );

                normalWS =
                    NormalizeNormalPerPixel(normalWS);

                // -------------------------------------------------
                // 5. PROPIEDADES DE LA SUPERFICIE
                // -------------------------------------------------

                SurfaceData surfaceData =
                    (SurfaceData)0;

                surfaceData.albedo =
                    baseColor.rgb;

                surfaceData.alpha =
                    1.0;

                surfaceData.normalTS =
                    normalTS;

                surfaceData.metallic =
                    0.0;

                surfaceData.specular =
                    half3(0.0, 0.0, 0.0);

                surfaceData.smoothness =
                    _Smoothness;

                surfaceData.occlusion =
                    1.0;

                surfaceData.emission =
                    half3(0.0, 0.0, 0.0);

                surfaceData.clearCoatMask =
                    0.0;

                surfaceData.clearCoatSmoothness =
                    0.0;

                // -------------------------------------------------
                // 6. DATOS NECESARIOS PARA LA ILUMINACIÓN
                // -------------------------------------------------

                InputData inputData =
                    (InputData)0;

                inputData.positionWS =
                    input.positionWS;

                inputData.normalWS =
                    normalWS;

                inputData.viewDirectionWS =
                    GetWorldSpaceNormalizeViewDir(input.positionWS);

                inputData.shadowCoord =
                    input.shadowCoord;

                inputData.fogCoord =
                    input.fogFactor;

                inputData.vertexLighting =
                    VertexLighting(
                        input.positionWS,
                        normalWS
                    );

                inputData.bakedGI =
                    SampleSH(normalWS);

                inputData.normalizedScreenSpaceUV =
                    GetNormalizedScreenSpaceUV(
                        input.positionCS
                    );

                inputData.shadowMask =
                    half4(1.0, 1.0, 1.0, 1.0);

                // -------------------------------------------------
                // 7. ILUMINACIÓN PBR DE URP
                // -------------------------------------------------

                half4 finalColor =
                    UniversalFragmentPBR(
                        inputData,
                        surfaceData
                    );

                // -------------------------------------------------
                // 8. NIEBLA
                // -------------------------------------------------

                finalColor.rgb = MixFog(
                    finalColor.rgb,
                    inputData.fogCoord
                );

                return finalColor;
            }

            ENDHLSL
        }

        // Permite que el objeto proyecte sombras.
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"

        // Permite que participe en la textura de profundidad.
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}