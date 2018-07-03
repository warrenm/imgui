
#import "ViewController.h"
#import "Renderer.h"
#include "imgui.h"

@interface ViewController ()
@property (nonatomic, readonly) MTKView *mtkView;
@property (nonatomic, strong) Renderer *renderer;
#if TARGET_OS_OSX
@property (nonatomic, assign) NSTrackingRectTag trackingAreaToken;
#endif
@end

@implementation ViewController

- (MTKView *)mtkView {
    return (MTKView *)self.view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.mtkView.device = MTLCreateSystemDefaultDevice();
    
    if (!self.mtkView.device) {
        NSLog(@"Metal is not supported");
        abort();
    }

    self.renderer = [[Renderer alloc] initWithMetalKitView:self.mtkView];

    [self.renderer mtkView:self.mtkView drawableSizeWillChange:self.mtkView.bounds.size];

    self.mtkView.delegate = self.renderer;

#if TARGET_OS_OSX
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                                options:NSTrackingMouseMoved | NSTrackingInVisibleRect | NSTrackingActiveAlways
                                                                  owner:self
                                                               userInfo:nil];
    [self.view addTrackingArea:trackingArea];
#endif
}

#if TARGET_OS_OSX

- (void)updateIOWithMouseEvent:(NSEvent *)event {
    NSPoint mousePoint = event.locationInWindow;
    mousePoint = [self.mtkView convertPoint:mousePoint fromView:nil];
    mousePoint = NSMakePoint(mousePoint.x, self.view.bounds.size.height - mousePoint.y);
    
    NSUInteger pressedButtons = NSEvent.pressedMouseButtons;
    bool leftButtonPressed = (pressedButtons & (1 << 0)) != 0;
    bool rightButtonPressed = (pressedButtons & (1 << 1)) != 0;
    
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(mousePoint.x, mousePoint.y);
    io.MouseDown[0] = leftButtonPressed;
    io.MouseDown[1] = rightButtonPressed;
}

- (void)mouseMoved:(NSEvent *)event {
    [self updateIOWithMouseEvent:event];
}

- (void)mouseDown:(NSEvent *)event {
    [self updateIOWithMouseEvent:event];
}

- (void)mouseUp:(NSEvent *)event {
    [self updateIOWithMouseEvent:event];
}

- (void)mouseDragged:(NSEvent *)event {
    [self updateIOWithMouseEvent:event];
}

#elif TARGET_OS_IOS

// This touch mapping is super cheesy/hacky. We treat any touch on the screen
// as if it were a depressed left mouse button, and we don't bother handling
// multitouch correctly at all. This causes the "cursor" to behave very erratically
// when there are multiple active touches. But for demo purposes, single-touch
// interaction actually works surprisingly well.
- (void)updateIOWithTouchEvent:(UIEvent *)event {
    UITouch *anyTouch = event.allTouches.anyObject;
    CGPoint touchLocation = [anyTouch locationInView:self.view];
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(touchLocation.x, touchLocation.y);
    
    BOOL hasActiveTouch = NO;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            hasActiveTouch = YES;
            break;
        }
    }
    io.MouseDown[0] = hasActiveTouch;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateIOWithTouchEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self updateIOWithTouchEvent:event];
}

#endif

@end

