package local.yanda.companion;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.File;
import com.google.zxing.*;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeReader;
public class QrImageTest {
 public static void main(String[] args)throws Exception{
  BufferedImage image=ImageIO.read(new File(args[0]));
  for(int angle=0;angle<4;angle++){
   int w=image.getWidth(),h=image.getHeight();int[] pixels=image.getRGB(0,0,w,h,null,0,w);
   Result result=new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(new RGBLuminanceSource(w,h,pixels))));
   Pairing p=Pairing.parse(result.getText());if(p.hosts.size()!=8||p.port!=12345)throw new AssertionError("QR content changed");
   BufferedImage rotated=new BufferedImage(h,w,BufferedImage.TYPE_INT_RGB);for(int y=0;y<h;y++)for(int x=0;x<w;x++)rotated.setRGB(h-1-y,x,image.getRGB(x,y));image=rotated;
  }
  System.out.println("PASS 4 rotations: desktop qrcode PNG decoded by Android ZXing core; synthetic URI");
 }
}
