package local.yanda.companion;

import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

/** Strict offline QR parser. No DNS lookup, private IPv4 only, no persistence. */
public final class Pairing {
    public final String host, fingerprint, token;
    public final int port;
    public final java.util.List<String> hosts=new java.util.ArrayList<>();
    private Pairing(String h,int p,String f,String t){host=h;port=p;fingerprint=f;token=t;hosts.add(h);}
    private static void privateHost(String h)throws Exception {
        if(h==null || !h.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}"))throw new Exception("Некорректный адрес ПК");
        String[] ip=h.split("\\.");int a=Integer.parseInt(ip[0]),b=Integer.parseInt(ip[1]);
        for(String octet:ip)if(Integer.parseInt(octet)>255 || octet.length()>1&&octet.charAt(0)=='0')throw new Exception("Некорректный адрес ПК");
        if(!(a==10 || a==192&&b==168 || a==172&&b>=16&&b<=31 || a==169&&b==254))throw new Exception("Разрешена только локальная сеть");
    }
    public static Pairing parse(String value) throws Exception {
        if(value==null || value.length()>1024)throw new Exception("Отсканируйте QR из Y AND A на ПК");
        URI uri=new URI(value.trim());
        if(!"yanda".equals(uri.getScheme()) || !"connect".equals(uri.getHost()) || uri.getRawUserInfo()!=null || uri.getFragment()!=null || uri.getPort()!=-1 || (uri.getRawPath()!=null&&!uri.getRawPath().isEmpty()))throw new Exception("Это не QR подключения Y AND A");
        Map<String,String> q=new HashMap<>();
        if(uri.getRawQuery()==null)throw new Exception("QR не содержит подключения");
        for(String part:uri.getRawQuery().split("&",-1)){
            String[] p=part.split("=",2);if(p.length!=2 || q.containsKey(p[0]))throw new Exception("Повреждённый QR");
            if(!java.util.Arrays.asList("v","host","alt","port","fp","token").contains(p[0]))throw new Exception("Неподдерживаемое поле QR");
            q.put(p[0],URLDecoder.decode(p[1],StandardCharsets.UTF_8.name()));
        }
        String h=q.get("host"),f=q.get("fp"),t=q.get("token");
        if(!"3".equals(q.get("v")) || h==null || !h.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}") || f==null || t==null || !f.matches("[0-9a-f]{64}") || !t.matches("[0-9a-f]{64}"))throw new Exception("Неподдерживаемый QR. Обновите приложения на телефоне и ПК");
        privateHost(h);
        int p=Integer.parseInt(q.getOrDefault("port","0"));if(p<1 || p>65535)throw new Exception("Некорректный порт ПК");
        Pairing result=new Pairing(h,p,f,t);
        String alt=q.getOrDefault("alt","");
        if(!alt.isEmpty())for(String candidate:alt.split(",",-1)){
            privateHost(candidate);
            if(!result.hosts.contains(candidate))result.hosts.add(candidate);
            if(result.hosts.size()>8)throw new Exception("Слишком много сетевых адресов в QR");
        }
        return result;
    }
    public static byte[] hex(String s){byte[] out=new byte[s.length()/2];for(int i=0;i<out.length;i++)out[i]=(byte)Integer.parseInt(s.substring(i*2,i*2+2),16);return out;}
}
