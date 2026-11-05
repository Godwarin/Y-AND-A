package local.yanda.companion;
public class PairingTest {
 public static void main(String[] args)throws Exception{
  String tail="&fp="+"a".repeat(64)+"&token="+"b".repeat(64);
  String valid="yanda://connect?v=3&host=192.168.1.2&port=12345"+tail;
  Pairing p=Pairing.parse(valid);if(p.port!=12345||!p.host.equals("192.168.1.2"))throw new AssertionError();
  if(Pairing.parse(valid+"&alt=10.0.0.2,172.16.0.2").hosts.size()!=3)throw new AssertionError();
  int checks=2;
  for(String bad:new String[]{valid+"&alt=8.8.8.8",valid.replace("192.168.1.2","8.8.8.8"),valid.replace("192.168.1.2","127.0.0.1"),valid.replace("192.168.1.2","host.local"),valid.replace("192.168.1.2","192.168.999.1"),valid.replace("port=12345","port=0"),valid.replace("port=12345","port=99999"),valid.replace("v=3","v=2"),valid+"&token="+"b".repeat(64),valid+"#secret",valid.replace("yanda:","https:"),valid.replace("fp="+"a".repeat(64),"fp=bad"),"WIFI:T:ADB;S:fixture;P:fixture;;"}){
   boolean rejected=false;try{Pairing.parse(bad);}catch(Exception e){rejected=true;}if(!rejected)throw new AssertionError("Malformed/untrusted QR accepted");checks++;
  }
  System.out.println("PASS "+checks+" JVM pairing parser checks; no Android device");
  for(String bad:new String[]{valid+"&alt=10.0.0.2%26alt%3D10.0.0.3",valid+"&alt=10.0.0.2,",valid+"&alt=10.0.0.2%26evil%3Dx",valid+"&unknown=1",valid.replace("connect?","connect/path?"),valid.replace("connect?","connect:123?"),valid.replace("192.168.1.2","010.0.0.1"),valid+"&",valid+"&alt=10.0.0.2,10.0.0.3,10.0.0.4,10.0.0.5,10.0.0.6,10.0.0.7,10.0.0.8,10.0.0.9"}){
   boolean rejected=false;try{Pairing.parse(bad);}catch(Exception e){rejected=true;}if(!rejected)throw new AssertionError("Malformed alternative/URI accepted");checks++;
  }
  System.out.println("PASS "+checks+" JVM pairing parser checks; no Android device (final)");
 }
}
