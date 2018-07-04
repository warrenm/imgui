// ImGui Platform Binding for: OSX / Cocoa
// This needs to be used along with a Renderer (e.g. OpenGL2, OpenGL3, Vulkan..)

@class NSEvent;
@class NSView;

IMGUI_API bool        ImGui_ImplOSX_Init();
IMGUI_API void        ImGui_ImplOSX_Shutdown();
IMGUI_API void        ImGui_ImplOSX_NewFrame(NSView *_Nonnull view);
bool ImGui_ImplOSX_HandleEvent(NSEvent *_Nonnull event, NSView *_Nullable view);
