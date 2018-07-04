// ImGui Renderer for: Metal

@class CAMetalLayer, MTLRenderPassDescriptor;
@protocol MTLDevice, MTLCommandBuffer, MTLRenderCommandEncoder;

IMGUI_IMPL_API bool ImGui_ImplMetal_Init(id<MTLDevice> device);
IMGUI_IMPL_API void ImGui_ImplMetal_Shutdown();
IMGUI_IMPL_API void ImGui_ImplMetal_NewFrame(MTLRenderPassDescriptor *renderPassDescriptor);
void ImGui_ImplMetal_RenderDrawData(ImDrawData* draw_data,
                                    id<MTLCommandBuffer> commandBuffer,
                                    id<MTLRenderCommandEncoder> commandEncoder);

// Called by Init/NewFrame/Shutdown
IMGUI_IMPL_API bool ImGui_ImplMetal_CreateFontsTexture(id<MTLDevice> device);
IMGUI_IMPL_API void ImGui_ImplMetal_DestroyFontsTexture();
IMGUI_IMPL_API bool ImGui_ImplMetal_CreateDeviceObjects(id<MTLDevice> device);
IMGUI_IMPL_API void ImGui_ImplMetal_DestroyDeviceObjects();
