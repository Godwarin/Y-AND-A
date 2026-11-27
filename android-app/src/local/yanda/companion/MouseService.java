package local.yanda.companion;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.app.KeyguardManager;
import android.graphics.Path;
import android.view.accessibility.AccessibilityEvent;

public final class MouseService extends AccessibilityService {
    private static volatile MouseService active;

    @Override protected void onServiceConnected() { active = this; }
    @Override public void onDestroy() { if (active == this) active = null; super.onDestroy(); }
    @Override public void onAccessibilityEvent(AccessibilityEvent event) {}
    @Override public void onInterrupt() {}
    static boolean available() { return active != null; }

    static void gesture(float x, float y, float endX, float endY, int duration) {
        MouseService service = active;
        if (service == null || service.getSystemService(KeyguardManager.class).isKeyguardLocked()) return;
        Path path = new Path();
        path.moveTo(x, y);
        if (x != endX || y != endY) path.lineTo(endX, endY);
        GestureDescription gesture = new GestureDescription.Builder()
            .addStroke(new GestureDescription.StrokeDescription(path, 0, duration)).build();
        service.dispatchGesture(gesture, null, null);
    }
}
