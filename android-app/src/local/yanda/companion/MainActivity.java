package local.yanda.companion;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.projection.MediaProjectionManager;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.util.ArrayList;

public class MainActivity extends Activity {
    private String offer;
    private String pendingOffer;
    private boolean pendingAudio;
    private TextView connection,status;
    private CheckBox audio;
    private Button start;
    private final Handler ui=new Handler(Looper.getMainLooper());
    private final Runnable refresh=new Runnable(){public void run(){if(status!=null){status.setText(StreamService.uiStatus);start.setEnabled(offer!=null && !StreamService.running);start.setAlpha(start.isEnabled()?1f:.4f);}ui.postDelayed(this,500);}};
    @Override public void onCreate(Bundle saved){super.onCreate(saved);getWindow().setStatusBarColor(Color.rgb(8,8,8));getWindow().setNavigationBarColor(Color.rgb(8,8,8));build();}
    private int dp(int v){return (int)(v*getResources().getDisplayMetrics().density+.5f);}
    private GradientDrawable bg(int color){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(14));return d;}
    private TextView text(String s,int size,int color){TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(color);t.setPadding(0,dp(8),0,dp(8));return t;}
    private Button button(String label,boolean primary){Button b=new Button(this);b.setText(label);b.setAllCaps(false);b.setTextSize(15);b.setTextColor(Color.WHITE);b.setBackground(bg(primary?Color.rgb(225,25,45):Color.rgb(32,32,35)));LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(56));lp.topMargin=dp(12);b.setLayoutParams(lp);return b;}
    private void build(){
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setBackgroundColor(Color.rgb(8,8,8));
        LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setPadding(dp(24),dp(24),dp(24),dp(28));scroll.addView(root);setContentView(scroll);
        if(Build.VERSION.SDK_INT>=30)root.setOnApplyWindowInsetsListener((v,insets)->{android.graphics.Insets bars=insets.getInsets(WindowInsets.Type.systemBars());v.setPadding(dp(24),bars.top+dp(16),dp(24),bars.bottom+dp(20));return insets;});
        TextView brand=text("Y AND A.",29,Color.WHITE);brand.setTypeface(null,Typeface.BOLD);root.addView(brand);
        root.addView(text("ВАШ ЭКРАН. ВАШ КОМПЬЮТЕР.",10,Color.rgb(225,25,45)));
        root.addView(text("Экран и звук\nна большом экране",29,Color.WHITE));
        root.addView(text("Без кабеля и режима разработчика. Подключите телефон и ПК к одной локальной сети.",14,Color.rgb(155,155,165)));
        LinearLayout card=new LinearLayout(this);card.setOrientation(1);card.setPadding(dp(18),dp(15),dp(18),dp(15));card.setBackground(bg(Color.rgb(20,20,22)));LinearLayout.LayoutParams cardLp=new LinearLayout.LayoutParams(-1,-2);cardLp.topMargin=dp(24);card.setLayoutParams(cardLp);root.addView(card);
        card.addView(text("ПОДКЛЮЧЕНИЕ",10,Color.GRAY));connection=text("Отсканируйте QR на компьютере",16,Color.WHITE);card.addView(connection);
        status=text(StreamService.uiStatus,13,Color.rgb(160,160,170));card.addView(status);
        Button scan=button("Сканировать QR-код",true);root.addView(scan);scan.setOnClickListener(v->startActivityForResult(new Intent(this,ScanActivity.class),10));
        Button manual=button("Вставить код подключения",false);root.addView(manual);manual.setOnClickListener(v->{EditText input=new EditText(this);input.setTextColor(Color.WHITE);input.setTextSize(12);input.setHint("yanda://connect?…");input.setSingleLine(false);input.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);new AlertDialog.Builder(this).setTitle("Код из Y AND A на ПК").setView(input).setPositiveButton("Подключить",(d,w)->accept(input.getText().toString())).setNegativeButton("Отмена",null).show();});
        audio=new CheckBox(this);audio.setText("Передавать звук приложений");audio.setTextSize(14);audio.setTextColor(Color.LTGRAY);audio.setChecked(true);audio.setButtonTintList(android.content.res.ColorStateList.valueOf(Color.rgb(225,25,45)));audio.setPadding(0,dp(20),0,dp(8));root.addView(audio);
        start=button("Начать трансляцию",true);start.setEnabled(false);root.addView(start);start.setOnClickListener(v->requestStart());
        Button stop=button("Остановить",false);root.addView(stop);stop.setOnClickListener(v->stopService(new Intent(this,StreamService.class)));
        root.addView(text("Android попросит разрешить показ экрана для каждого сеанса. Разрешение на звук называется «Запись аудио», но Y AND A захватывает воспроизведение приложений, а не микрофон.",12,Color.GRAY));
        root.addView(text("Некоторые приложения запрещают передачу звука или защищённого изображения. Трансляция зашифрована и не записывается на диск.",12,Color.GRAY));
        root.addView(text("0.42a · Android 10+ · Только ваша сеть",10,Color.GRAY));
    }
    private void accept(String raw){if(raw==null || pendingOffer!=null || StreamService.running)return;try{Pairing p=Pairing.parse(raw);offer=raw;connection.setText("Y AND A на ПК · "+p.host);start.setEnabled(!StreamService.running);status.setText("Готово. Нажмите «Начать трансляцию»");}catch(Exception e){new AlertDialog.Builder(this).setMessage("Не удалось прочитать код подключения. Создайте новый QR на ПК.").setPositiveButton("Понятно",null).show();}}
    private void requestStart(){if(offer==null || pendingOffer!=null || StreamService.running)return;pendingOffer=offer;pendingAudio=audio.isChecked();ArrayList<String> permissions=new ArrayList<>();if(pendingAudio&&checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED)permissions.add(Manifest.permission.RECORD_AUDIO);if(Build.VERSION.SDK_INT>=33&&checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)permissions.add(Manifest.permission.POST_NOTIFICATIONS);if(permissions.isEmpty())consent();else requestPermissions(permissions.toArray(new String[0]),20);}
    private void consent(){try{if(pendingOffer!=null)startActivityForResult(getSystemService(MediaProjectionManager.class).createScreenCaptureIntent(),30);}catch(Exception e){pendingOffer=null;status.setText("Система не разрешила запрос экрана");}}
    @Override public void onRequestPermissionsResult(int r,String[] p,int[] g){super.onRequestPermissionsResult(r,p,g);if(r==20)consent();}
    @Override public void onActivityResult(int r,int result,Intent data){super.onActivityResult(r,result,data);if(r==10&&result==RESULT_OK&&data!=null)accept(data.getStringExtra("offer"));if(r==30){String approved=pendingOffer;pendingOffer=null;if(result==RESULT_OK&&data!=null&&approved!=null){Intent service=new Intent(this,StreamService.class).putExtra("offer",approved).putExtra("result",result).putExtra("projection",data).putExtra("audio",pendingAudio&&checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED);int[] size=initialCaptureSize();service.putExtra("captureWidth",size[0]).putExtra("captureHeight",size[1]);try{startForegroundService(service);}catch(Exception e){status.setText("Система не разрешила запуск трансляции");}}}}
    @SuppressWarnings("deprecation") private int[] initialCaptureSize(){
        if(Build.VERSION.SDK_INT>=30){android.graphics.Rect b=getWindowManager().getMaximumWindowMetrics().getBounds();return new int[]{b.width(),b.height()};}
        android.util.DisplayMetrics m=new android.util.DisplayMetrics();getWindowManager().getDefaultDisplay().getRealMetrics(m);return new int[]{m.widthPixels,m.heightPixels};
    }
    @Override public void onResume(){super.onResume();ui.post(refresh);}
    @Override public void onPause(){ui.removeCallbacks(refresh);super.onPause();}
}
