using UnityEngine;
using UnityEngine.InputSystem;

public class ShaderTransition : MonoBehaviour
{
    [SerializeField] private Renderer targetRenderer;
    private Material material;

    void Start()
    {
        material = targetRenderer.material;
        material.SetFloat("_Active", 0f);
    }

    void Update()
    {
        if (Keyboard.current != null && Keyboard.current.spaceKey.wasPressedThisFrame)
        {
            RestartTransition();
        }
    }

    void RestartTransition()
    {
        material.SetFloat("_StartTime", Time.timeSinceLevelLoad);
        material.SetFloat("_Active", 1f);
    }
}