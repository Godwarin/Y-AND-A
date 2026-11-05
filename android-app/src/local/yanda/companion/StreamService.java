package local.yanda.companion;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.graphics.Rect;
import android.hardware.display.*;
import android.media.*;
import android.media.projection.*;
import android.os.*;
import android.view.*;
import java.io.*;
import java.net.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.cert.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.net.ssl.*;

public class StreamService extends Service {
    public static volatile String uiStatus="Ожидание подключения";
    public static volatile boolean running=false;
    private Session session;
    private static final String CHANNEL="yanda_projection";
    @Override public IBinder onBind(Intent i){return null;}
    @Override public int onStartCommand(Intent intent,int flags,int startId){
        if(intent==null){stopSelf();return START_NOT_STICKY;}
        if("stop".equals(intent.getAction())){stopSelf();return START_NOT_STICKY;}
        if(session!=null)return START_NOT_STICKY;
        NotificationManager nm=getSystemService(NotificationManager.class);nm.createNotificationChannel(new NotificationChannel(CHANNEL,"Трансляция экрана",NotificationManager.IMPORTANCE_LOW));
        PendingIntent stop=PendingIntent.getService(this,1,new Intent(this,StreamService.class).setAction("stop"),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent open=PendingIntent.getActivity(this,2,new Intent(this,MainActivity.class),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        Notification notification=new Notification.Builder(this,CHANNEL).setSmallIcon(local.yanda.companion.R.drawable.ic_status).setContentTitle("Y AND A · Трансляция экрана").setContentText("Только ваш ПК. Нажмите «Остановить», чтобы завершить.").setOngoing(true).setContentIntent(open).addAction(new Notification.Action.Builder(null,"Остановить",stop).build()).build();
        startForeground(42,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        running=true;uiStatus="Защищённое подключение к ПК…";
        session=new Session(intent);session.control.post(session::begin);
        return START_NOT_STICKY;
    }
    @Override public void onDestroy(){if(session!=null)session.close();running=false;stopForeground(STOP_FOREGROUND_REMOVE);super.onDestroy();}

    private final class Session {
        final HandlerThread thread=new HandlerThread("YANDA-capture");final Handler control;
        final Intent request;
        final AtomicBoolean closed=new AtomicBoolean(false);
        final Object writeLock=new Object();
        SSLSocket socket;DataOutputStream output;DataInputStream input;
        MediaProjection projection;VirtualDisplay display;MediaCodec encoder;Surface surface;
        volatile AudioRecord record;
        Thread audioThread,monitor;
        ScheduledExecutorService heartbeat;
        int sourceW,sourceH,videoW,videoH,maxSize=1920,fps=30;
        boolean audioEnabled;
        DisplayManager.DisplayListener displayListener;
        Session(Intent intent){request=intent;thread.start();control=new Handler(thread.getLooper());}
        void begin(){try{
            Pairing pair=Pairing.parse(request.getStringExtra("offer"));
            X509TrustManager pin=new X509TrustManager(){
                public X509Certificate[] getAcceptedIssuers(){return new X509Certificate[0];}
                public void checkClientTrusted(X509Certificate[] chain,String type)throws CertificateException{throw new CertificateException("Client certificates not supported");}
                public void checkServerTrusted(X509Certificate[] chain,String type)throws CertificateException{
                    try{if(chain.length==0 || !MessageDigest.isEqual(MessageDigest.getInstance("SHA-256").digest(chain[0].getEncoded()),Pairing.hex(pair.fingerprint)))throw new CertificateException("Неверный сертификат ПК. Создайте новый QR.");}
                    catch(GeneralSecurityException e){throw new CertificateException("Сертификат ПК не подтверждён",e);}
                }
            };
            SSLContext tls=SSLContext.getInstance("TLSv1.3");tls.init(null,new TrustManager[]{pin},new SecureRandom());
            boolean connected=false;
            for(String host:pair.hosts){
                if(closed.get())return;
                socket=(SSLSocket)tls.getSocketFactory().createSocket();socket.setEnabledProtocols(new String[]{"TLSv1.3"});socket.setTcpNoDelay(true);socket.setKeepAlive(true);
                try{socket.connect(new InetSocketAddress(host,pair.port),2500);socket.setSoTimeout(10000);socket.startHandshake();connected=true;break;}
                catch(Exception failed){try{socket.close();}catch(Exception ignored){}}
            }
            if(!connected)throw new IOException("ПК недоступен");
            input=new DataInputStream(socket.getInputStream());output=new DataOutputStream(new BufferedOutputStream(socket.getOutputStream(),65536));
            output.write("YANDA03\n".getBytes(StandardCharsets.US_ASCII));output.write(pair.token.getBytes(StandardCharsets.US_ASCII));output.flush();
            byte[] magic=new byte[8];input.readFully(magic);if(!java.util.Arrays.equals(magic,"YANDAOK\n".getBytes(StandardCharsets.US_ASCII)))throw new IOException("Неверный ответ ПК");
            audioEnabled=input.readUnsignedByte()==1 && request.getBooleanExtra("audio",false);maxSize=input.readInt();fps=input.readInt();if(maxSize<640||maxSize>2560||(fps!=30&&fps!=60))throw new IOException("Неподдерживаемые параметры ПК");
            if(closed.get())return;
            // One new consent token, one getMediaProjection, one VirtualDisplay per session.
            Intent consent=request.getParcelableExtra("projection");
            projection=getSystemService(MediaProjectionManager.class).getMediaProjection(request.getIntExtra("result",0),consent);
            projection.registerCallback(new MediaProjection.Callback(){
                @Override public void onStop(){fail("Трансляция завершена системой Android");}
                @Override public void onCapturedContentResize(int w,int h){if(!closed.get()&&w>0&&h>0&&(sourceW!=w||sourceH!=h)){try{configure(w,h);}catch(Exception e){fail("Не удалось изменить размер трансляции");}}}
            },control);
            int iw=request.getIntExtra("captureWidth",0),ih=request.getIntExtra("captureHeight",0);int[] initial=iw>0&&ih>0?new int[]{iw,ih}:screenSize();configure(initial[0],initial[1]);
            if(Build.VERSION.SDK_INT<34){displayListener=new DisplayManager.DisplayListener(){public void onDisplayAdded(int id){}public void onDisplayRemoved(int id){}public void onDisplayChanged(int id){if(id==Display.DEFAULT_DISPLAY&&!closed.get()){int[] s=screenSize();if(s[0]!=sourceW||s[1]!=sourceH)try{configure(s[0],s[1]);}catch(Exception e){fail("Не удалось повернуть трансляцию");}}}};getSystemService(DisplayManager.class).registerDisplayListener(displayListener,control);}
            if(closed.get())return;
            if(audioEnabled)startAudio();else send(4,new byte[0],0);
            if(closed.get())return;
            heartbeat=Executors.newSingleThreadScheduledExecutor();heartbeat.scheduleAtFixedRate(()->{try{send(5,new byte[0],0);}catch(Exception e){fail("Связь с ПК потеряна");}},1,2,TimeUnit.SECONDS);
            monitor=new Thread(()->{try{while(!closed.get()){if(input.read()!=1)throw new EOFException();}}catch(Exception e){if(!closed.get())fail("ПК завершил соединение или сеть недоступна");}},"YANDA-link");monitor.start();
            uiStatus="Передаём экран в Y AND A";
        }catch(Exception e){fail("Не удалось подключиться. Проверьте общую сеть, свежий QR и доступ Y AND A к локальной сети на ПК.");}}

        @SuppressWarnings("deprecation") int[] screenSize(){android.util.DisplayMetrics metrics=new android.util.DisplayMetrics();Display d=getSystemService(DisplayManager.class).getDisplay(Display.DEFAULT_DISPLAY);if(d==null)throw new IllegalStateException("Display unavailable");d.getRealMetrics(metrics);return new int[]{metrics.widthPixels,metrics.heightPixels};}

        void configure(int w,int h)throws Exception{
            if(closed.get())return;
            double scale=Math.min(1.,maxSize/(double)Math.max(w,h));int ew=Math.max(16,((int)(w*scale)/16)*16),eh=Math.max(16,((int)(h*scale)/16)*16);
            sourceW=w;sourceH=h;if(encoder!=null&&ew==videoW&&eh==videoH)return;
            if(display!=null)display.setSurface(null);
            releaseEncoder();videoW=ew;videoH=eh;
            MediaFormat format=MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC,ew,eh);format.setInteger(MediaFormat.KEY_COLOR_FORMAT,MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);format.setInteger(MediaFormat.KEY_BIT_RATE,Math.min(12000000,Math.max(2000000,ew*eh*4)));format.setInteger(MediaFormat.KEY_FRAME_RATE,fps);format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL,1);format.setInteger(MediaFormat.KEY_MAX_B_FRAMES,0);format.setInteger(MediaFormat.KEY_PRIORITY,0);
            encoder=MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
            encoder.setCallback(new MediaCodec.Callback(){
                public void onInputBufferAvailable(MediaCodec c,int index){}
                public void onOutputBufferAvailable(MediaCodec c,int index,MediaCodec.BufferInfo info){if(closed.get()||c!=encoder)return;try{ByteBuffer buffer=c.getOutputBuffer(index);if(buffer!=null&&info.size>0){buffer.position(info.offset);buffer.limit(info.offset+info.size);byte[] bytes=new byte[info.size];buffer.get(bytes);send(1,bytes,info.presentationTimeUs);}c.releaseOutputBuffer(index,false);}catch(Exception e){fail("Передача экрана прервана");}}
                public void onOutputFormatChanged(MediaCodec c,MediaFormat format){if(closed.get()||c!=encoder)return;try{for(String key:new String[]{"csd-0","csd-1"}){ByteBuffer csd=format.getByteBuffer(key);if(csd!=null){ByteBuffer copy=csd.duplicate();byte[] bytes=new byte[copy.remaining()];copy.get(bytes);send(1,bytes,0);}}}catch(Exception e){fail("Не удалось передать настройки видео");}}
                public void onError(MediaCodec c,MediaCodec.CodecException error){if(c==encoder)fail("Видеокодек телефона недоступен. Остановите другие записи экрана и повторите.");}
            },control);
            encoder.configure(format,null,null,MediaCodec.CONFIGURE_FLAG_ENCODE);surface=encoder.createInputSurface();encoder.start();
            int dpi=getResources().getConfiguration().densityDpi;
            if(display==null)display=projection.createVirtualDisplay("Y AND A",ew,eh,dpi,DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,surface,null,control);
            else{display.resize(ew,eh,dpi);display.setSurface(surface);}
        }
        void startAudio(){if(closed.get())return;try{
            AudioPlaybackCaptureConfiguration capture=new AudioPlaybackCaptureConfiguration.Builder(projection).addMatchingUsage(AudioAttributes.USAGE_MEDIA).addMatchingUsage(AudioAttributes.USAGE_GAME).addMatchingUsage(AudioAttributes.USAGE_UNKNOWN).excludeUid(android.os.Process.myUid()).build();
            AudioFormat format=new AudioFormat.Builder().setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_IN_STEREO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build();
            int min=AudioRecord.getMinBufferSize(48000,AudioFormat.CHANNEL_IN_STEREO,AudioFormat.ENCODING_PCM_16BIT);record=new AudioRecord.Builder().setAudioFormat(format).setBufferSizeInBytes(Math.max(19200,min*2)).setAudioPlaybackCaptureConfig(capture).build();record.startRecording();if(record.getRecordingState()!=AudioRecord.RECORDSTATE_RECORDING)throw new IOException();
            audioThread=new Thread(()->{byte[] bytes=new byte[3840];try{while(!closed.get()){AudioRecord current=record;if(current==null)break;int count=current.read(bytes,0,bytes.length,AudioRecord.READ_BLOCKING);if(count<0)throw new IOException();if(count>0){byte[] packet=java.util.Arrays.copyOf(bytes,count);send(2,packet,System.nanoTime()/1000);}}}catch(Exception e){if(!closed.get())try{send(4,new byte[0],0);}catch(Exception ignored){}}},"YANDA-playback");audioThread.start();
        }catch(Exception e){try{send(4,new byte[0],0);}catch(Exception ignored){}AudioRecord old=record;record=null;if(old!=null)old.release();}}
        void send(int type,byte[] bytes,long pts)throws IOException{if(closed.get())throw new EOFException();synchronized(writeLock){output.writeByte(type);output.writeInt(bytes.length);output.writeLong(pts);output.write(bytes);output.flush();}}
        void fail(String message){if(!closed.get()){uiStatus=message;close();new Handler(Looper.getMainLooper()).post(()->stopSelf());}}
        void releaseEncoder(){MediaCodec old=encoder;encoder=null;if(old!=null){try{old.stop();}catch(Exception ignored){}old.release();}if(surface!=null){surface.release();surface=null;}}
        void close(){
            if(!closed.compareAndSet(false,true))return;
            running=false;if(uiStatus.startsWith("Передаём")||uiStatus.startsWith("Защищённое"))uiStatus="Трансляция остановлена";
            // Close from the caller immediately: this interrupts a blocked TLS write.
            try{if(socket!=null)socket.close();}catch(Exception ignored){}
            if(heartbeat!=null)heartbeat.shutdownNow();
            AudioRecord old=record;record=null;if(old!=null){try{old.stop();}catch(Exception ignored){}old.release();}
            control.post(()->{if(heartbeat!=null)heartbeat.shutdownNow();try{if(socket!=null)socket.close();}catch(Exception ignored){}AudioRecord late=record;record=null;if(late!=null){try{late.stop();}catch(Exception ignored){}late.release();}if(displayListener!=null)getSystemService(DisplayManager.class).unregisterDisplayListener(displayListener);if(display!=null){display.release();display=null;}releaseEncoder();if(projection!=null){projection.stop();projection=null;}thread.quitSafely();});
        }
    }
}
