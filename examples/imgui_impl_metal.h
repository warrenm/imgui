// ImGui Renderer for: Metal

@class CAMetalLayer;
@protocol MTLCommandBuffer, MTLRenderCommandEncoder;

IMGUI_IMPL_API bool     ImGui_ImplMetal_Init(CAMetalLayer *layer);
IMGUI_IMPL_API void     ImGui_ImplMetal_Shutdown();
IMGUI_IMPL_API void     ImGui_ImplMetal_NewFrame();
void ImGui_ImplMetal_RenderDrawData(ImDrawData* draw_data, id<MTLCommandBuffer> commandBuffer, id<MTLRenderCommandEncoder> commandEncoder);

// Called by Init/NewFrame/Shutdown
IMGUI_IMPL_API bool     ImGui_ImplMetal_CreateFontsTexture();
IMGUI_IMPL_API void     ImGui_ImplMetal_DestroyFontsTexture();
IMGUI_IMPL_API bool     ImGui_ImplMetal_CreateDeviceObjects();
IMGUI_IMPL_API void     ImGui_ImplMetal_DestroyDeviceObjects();
