
#import <simd/simd.h>
#import <ModelIO/ModelIO.h>

#import "Renderer.h"
#import "ShaderTypes.h"

#include "imgui.h"
#include "imgui_impl_metal.h"

static const NSUInteger MaxBuffersInFlight = 3;

@interface Renderer ()
@property (nonatomic, strong) dispatch_semaphore_t inFlightSemaphore;
@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;

@property (nonatomic, strong) NSMutableArray<id<MTLBuffer>> *dynamicUniformBuffers;
@property (nonatomic, strong) id <MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id <MTLDepthStencilState> depthState;
@property (nonatomic, strong) MTLVertexDescriptor *mtlVertexDescriptor;

@property (nonatomic, strong) MTKMesh *mesh;

@property (nonatomic, assign) uint8_t uniformBufferIndex;
@property (nonatomic, assign) matrix_float4x4 projectionMatrix;
@property (nonatomic, assign) float rotation;
@end

@implementation Renderer

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
    self = [super init];
    if(self)
    {
        _device = view.device;
        _inFlightSemaphore = dispatch_semaphore_create(MaxBuffersInFlight);
        _dynamicUniformBuffers = [NSMutableArray arrayWithCapacity:MaxBuffersInFlight];
        [self _loadMetalWithView:view];
        [self _loadAssets];
        
        ImGui_ImplMetal_Init((CAMetalLayer *)view.layer);
        
        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        (void)ImGui::GetIO();
        
        ImGui::StyleColorsDark();
    }

    return self;
}

- (void)_loadMetalWithView:(nonnull MTKView *)view;
{
    /// Load Metal state objects and initalize renderer dependent view properties

    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    view.sampleCount = 1;

    _mtlVertexDescriptor = [[MTLVertexDescriptor alloc] init];

    _mtlVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].offset = 0;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexMeshVertices;

    _mtlVertexDescriptor.attributes[VertexAttributeNormal].format = MTLVertexFormatFloat3;
    _mtlVertexDescriptor.attributes[VertexAttributeNormal].offset = 16;
    _mtlVertexDescriptor.attributes[VertexAttributeNormal].bufferIndex = BufferIndexMeshVertices;
    
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].format = MTLVertexFormatFloat2;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].offset = 32;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].bufferIndex = BufferIndexMeshVertices;

    _mtlVertexDescriptor.layouts[BufferIndexMeshVertices].stride = 40;
    _mtlVertexDescriptor.layouts[BufferIndexMeshVertices].stepRate = 1;
    _mtlVertexDescriptor.layouts[BufferIndexMeshVertices].stepFunction = MTLVertexStepFunctionPerVertex;

    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];

    id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.sampleCount = view.sampleCount;
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.vertexDescriptor = _mtlVertexDescriptor;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;

    NSError *error = NULL;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_pipelineState)
    {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }

    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];

    for(NSUInteger i = 0; i < MaxBuffersInFlight; i++)
    {
        id<MTLBuffer> dynamicUniformBuffer = [_device newBufferWithLength:512
                                                                  options:MTLResourceStorageModeShared];

        dynamicUniformBuffer.label = @"Uniform Buffer";
        _dynamicUniformBuffers[i] = dynamicUniformBuffer;
    }

    _commandQueue = [_device newCommandQueue];
}

- (void)_loadAssets
{
    NSError *error;

    MTKMeshBufferAllocator *metalAllocator = [[MTKMeshBufferAllocator alloc]
                                              initWithDevice: _device];

    MDLMesh *mdlMesh = [MDLMesh newBoxWithDimensions:(vector_float3){ 2, 2, 2 }
                                            segments:(vector_uint3){ 1, 1, 1 }
                                        geometryType:MDLGeometryTypeTriangles
                                       inwardNormals:NO
                                           allocator:metalAllocator];

    MDLVertexDescriptor *mdlVertexDescriptor =
    MTKModelIOVertexDescriptorFromMetal(_mtlVertexDescriptor);

    mdlVertexDescriptor.attributes[VertexAttributePosition].name  = MDLVertexAttributePosition;
    mdlVertexDescriptor.attributes[VertexAttributeTexcoord].name  = MDLVertexAttributeTextureCoordinate;
    mdlVertexDescriptor.attributes[VertexAttributeNormal].name  = MDLVertexAttributeNormal;

    mdlMesh.vertexDescriptor = mdlVertexDescriptor;

    _mesh = [[MTKMesh alloc] initWithMesh:mdlMesh
                                   device:_device
                                    error:&error];

    if(!_mesh || error)
    {
        NSLog(@"Error creating MetalKit mesh %@", error.localizedDescription);
    }
}

- (void)_updateSceneState
{
    simd_float4x4 baseModelViewMatrix = simd_mul(matrix4x4_translation(0, 0, -8), matrix4x4_rotation(_rotation, (simd_float3){ 0, 1, 0}));
    simd_float4x4 leftCubeModelView = simd_mul(baseModelViewMatrix, simd_mul(matrix4x4_translation(-3, 0, 0), matrix4x4_rotation(_rotation, (simd_float3){ 1, 1, 1})));
    simd_float4x4 rightCubeModelView = simd_mul(baseModelViewMatrix, simd_mul(matrix4x4_translation(3, 0, 0), matrix4x4_rotation(_rotation, (simd_float3){ 1, 1, 1})));

    Uniforms *leftUniforms = (Uniforms*)_dynamicUniformBuffers[_uniformBufferIndex].contents;
    Uniforms *rightUniforms = (Uniforms*)((char *)_dynamicUniformBuffers[_uniformBufferIndex].contents + 256);
    
    leftUniforms->projectionMatrix = _projectionMatrix;
    leftUniforms->modelViewMatrix = leftCubeModelView;
    leftUniforms->normalMatrix = leftCubeModelView; // This "works" as long as (1) there is no non-uniform scale, (2) we light in eye space, and (3) normals have a w coord of 0
    leftUniforms->color = (simd_float4){ 0.4, 0.4, 1, 1 };

    rightUniforms->projectionMatrix = _projectionMatrix;
    rightUniforms->modelViewMatrix = rightCubeModelView;
    rightUniforms->normalMatrix = rightCubeModelView;
    rightUniforms->color = (simd_float4){ 1, 0.4, 0.4, 1 };

    _rotation += .015;
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    _uniformBufferIndex = (_uniformBufferIndex + 1) % MaxBuffersInFlight;

    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
         dispatch_semaphore_signal(block_sema);
    }];

    [self _updateSceneState];

    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    
    static bool show_demo_window = true;
    static bool show_another_window = true;
    static float clear_color[4] = { 0.28f, 0.36f, 0.5f, 1.0f };

    if(renderPassDescriptor != nil)
    {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(clear_color[0], clear_color[1], clear_color[2], clear_color[3]);
        
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

        [renderEncoder pushDebugGroup:@"Draw Boxes"];

        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setDepthStencilState:_depthState];
        
        for (int cubeIndex = 0; cubeIndex < 2; ++cubeIndex) {
            [renderEncoder setVertexBuffer:_dynamicUniformBuffers[_uniformBufferIndex]
                                    offset:cubeIndex * 256
                                   atIndex:BufferIndexUniforms];

            [renderEncoder setFragmentBuffer:_dynamicUniformBuffers[_uniformBufferIndex]
                                      offset:cubeIndex * 256
                                     atIndex:BufferIndexUniforms];

            for (NSUInteger bufferIndex = 0; bufferIndex < _mesh.vertexBuffers.count; bufferIndex++)
            {
                MTKMeshBuffer *vertexBuffer = _mesh.vertexBuffers[bufferIndex];
                if((NSNull*)vertexBuffer != [NSNull null])
                {
                    [renderEncoder setVertexBuffer:vertexBuffer.buffer
                                            offset:vertexBuffer.offset
                                           atIndex:bufferIndex];
                }
            }

            for(MTKSubmesh *submesh in _mesh.submeshes)
            {
                [renderEncoder drawIndexedPrimitives:submesh.primitiveType
                                          indexCount:submesh.indexCount
                                           indexType:submesh.indexType
                                         indexBuffer:submesh.indexBuffer.buffer
                                   indexBufferOffset:submesh.indexBuffer.offset];
            }
        }
        
        [renderEncoder popDebugGroup];
        
        [renderEncoder pushDebugGroup:@"Draw ImGui"];
        
        ImGuiIO &io = ImGui::GetIO();
        io.DeltaTime = 1 / float(view.preferredFramesPerSecond ?: 60);
        
        ImGui_ImplMetal_NewFrame();

        {
            static float f = 0.0f;
            static int counter = 0;
            ImGui::Text("Hello, world!");                           // Display some text (you can use a format string too)
            ImGui::SliderFloat("float", &f, 0.0f, 1.0f);            // Edit 1 float using a slider from 0.0f to 1.0f
            ImGui::ColorEdit3("clear color", (float*)&clear_color); // Edit 3 floats representing a color

            ImGui::Checkbox("Demo Window", &show_demo_window);      // Edit bools storing our windows open/close state
            ImGui::Checkbox("Another Window", &show_another_window);

            if (ImGui::Button("Button"))                            // Buttons return true when clicked (NB: most widgets return true when edited/activated)
                counter++;
            ImGui::SameLine();
            ImGui::Text("counter = %d", counter);

            ImGui::Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0f / ImGui::GetIO().Framerate, ImGui::GetIO().Framerate);
        }
        
        // 2. Show another simple window. In most cases you will use an explicit Begin/End pair to name your windows.
        if (show_another_window)
        {
            ImGui::Begin("Another Window", &show_another_window);
            ImGui::Text("Hello from another window!");
            if (ImGui::Button("Close Me"))
                show_another_window = false;
            ImGui::End();
        }
        
        // 3. Show the ImGui demo window. Most of the sample code is in ImGui::ShowDemoWindow(). Read its code to learn more about Dear ImGui!
        if (show_demo_window)
        {
            ImGui::SetNextWindowPos(ImVec2(650, 20), ImGuiCond_FirstUseEver); // Normally user code doesn't need/want to call this because positions are saved in .ini file anyway. Here we just want to make the demo initial state a bit more friendly!
            ImGui::ShowDemoWindow(&show_demo_window);
        }
        
        ImGui::Render();
        ImDrawData *drawData = ImGui::GetDrawData();
        ImGui_ImplMetal_RenderDrawData(drawData, renderEncoder);
        
        [renderEncoder popDebugGroup];

        [renderEncoder endEncoding];

        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    [commandBuffer commit];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    float aspect = size.width / (float)size.height;
    _projectionMatrix = matrix_perspective_right_hand(65.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0f);
    
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize.x = view.bounds.size.width;
    io.DisplaySize.y = view.bounds.size.height;
    
#if TARGET_OS_OSX
    CGFloat framebufferScale = view.window.screen.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
#else
    CGFloat framebufferScale = view.window.screen.scale ?: UIScreen.mainScreen.scale;
#endif
    io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);
}

#pragma mark Matrix Math Utilities

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz)
{
    return (matrix_float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { tx, ty, tz,  1 }
    }};
}

static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis)
{
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;

    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0 },
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0 },
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0 },
        {                   0,                   0,                   0, 1 }
    }};
}

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);

    return (matrix_float4x4) {{
        { xs,   0,          0,  0 },
        {  0,  ys,          0,  0 },
        {  0,   0,         zs, -1 },
        {  0,   0, nearZ * zs,  0 }
    }};
}

@end
