package local.yanda.companion;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.hardware.Camera;
import android.os.Bundle;
import android.view.*;
import android.widget.*;
import com.google.zxing.*;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeReader;
import java.util.concurrent.*;

/** Offline scanner, no Play Services, analytics or image upload. Camera only while visible. */
@SuppressWarnings("deprecation")
public class ScanActivity extends Activity implements SurfaceHolder.Callback {
    private Camera camera;private SurfaceView surface;private TextView message;private volatile boolean visible,decoding;
    private final ExecutorService reader=Executors.newSingleThreadExecutor();
    @Override public void onCreate(Bundle saved){super.onCreate(saved);LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setBackgroundColor(0xff080808);message=new TextView(this);message.setText("Наведите камеру на QR в Y AND A на ПК");message.setTextColor(0xffeeeeee);message.setTextSize(17);message.setPadding(24,64,24,24);root.addView(message);surface=new SurfaceView(this);root.addView(surface,new LinearLayout.LayoutParams(-1,0,1));Button back=new Button(this);back.setText("Отмена");root.addView(back);back.setOnClickListener(v->finish());setContentView(root);surface.getHolder().addCallback(this);if(checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{Manifest.permission.CAMERA},1);}
    private void open(){if(!visible||camera!=null||!surface.getHolder().getSurface().isValid()||checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)return;try{camera=Camera.open();Camera.Parameters p=camera.getParameters();Camera.Size choice=p.getSupportedPreviewSizes().get(0);for(Camera.Size size:p.getSupportedPreviewSizes())if(size.width>=640&&size.width<=1280){choice=size;if(size.width==1280)break;}p.setPreviewSize(choice.width,choice.height);if(p.getSupportedFocusModes().contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE))p.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);camera.setParameters(p);camera.setDisplayOrientation(90);camera.setPreviewDisplay(surface.getHolder());camera.setPreviewCallback((bytes,c)->decode(bytes,c));camera.startPreview();}catch(Exception e){close();message.setText("Камера недоступна. Вернитесь и вставьте код подключения вручную.");}}
    private void decode(byte[] data,Camera c){if(decoding||!visible)return;decoding=true;Camera.Size size=c.getParameters().getPreviewSize();byte[] frame=data.clone();reader.execute(()->{try{Result result=new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(new PlanarYUVLuminanceSource(frame,size.width,size.height,0,0,size.width,size.height,false))));Pairing.parse(result.getText());runOnUiThread(()->{if(visible){setResult(RESULT_OK,new Intent().putExtra("offer",result.getText()));finish();}});}catch(Exception ignored){}finally{decoding=false;}});}
    private void close(){if(camera!=null){camera.setPreviewCallback(null);camera.stopPreview();camera.release();camera=null;}}
    @Override public void onResume(){super.onResume();visible=true;open();}
    @Override public void onPause(){visible=false;close();super.onPause();}
    @Override public void onDestroy(){reader.shutdownNow();super.onDestroy();}
    @Override public void onRequestPermissionsResult(int r,String[] p,int[] g){super.onRequestPermissionsResult(r,p,g);if(checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)open();else message.setText("Разрешите камеру для QR или вернитесь и вставьте код подключения вручную.");}
    public void surfaceCreated(SurfaceHolder h){open();}public void surfaceChanged(SurfaceHolder h,int f,int w,int y){}public void surfaceDestroyed(SurfaceHolder h){close();}
}
