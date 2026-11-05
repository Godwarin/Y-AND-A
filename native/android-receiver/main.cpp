#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/crypto.h>
#include <SDL.h>
#include <SDL_syswm.h>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <iostream>
#include <memory>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

// YANDA03: TLS 1.3, certificate pinned by QR, single-use 256-bit token.
// All network integers are big endian. No media is written to disk.
static std::atomic<bool> stopping{false}, finished{false};
static std::atomic<SOCKET> connection{INVALID_SOCKET};
static std::mutex frameMutex, outputMutex;
struct Picture { int w=0,h=0; std::vector<uint8_t> rgba; };
static Picture latest;
static std::atomic<unsigned> generation{0};
static void marker(const std::string& s) { std::lock_guard<std::mutex> lock(outputMutex); std::cout<<s<<std::endl; }
static void require(bool ok) { if(!ok) throw std::runtime_error("receiver failure"); }
static bool privateIp(uint32_t host) {
    return (host>>24)==10 || (host>>20)==0xac1 || (host>>16)==0xc0a8 || (host>>16)==0xa9fe;
}
static std::string addresses() {
    ULONG size=16384; std::vector<unsigned char> data(size);
    auto p=reinterpret_cast<IP_ADAPTER_ADDRESSES*>(data.data());
    ULONG rc=GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST|GAA_FLAG_SKIP_MULTICAST|GAA_FLAG_SKIP_DNS_SERVER,nullptr,p,&size);
    if(rc==ERROR_BUFFER_OVERFLOW) { data.resize(size); p=reinterpret_cast<IP_ADAPTER_ADDRESSES*>(data.data()); rc=GetAdaptersAddresses(AF_INET,GAA_FLAG_SKIP_ANYCAST|GAA_FLAG_SKIP_MULTICAST|GAA_FLAG_SKIP_DNS_SERVER,nullptr,p,&size); }
    std::set<std::string> result;
    if(rc==NO_ERROR) for(auto a=p;a;a=a->Next) if(a->OperStatus==IfOperStatusUp && a->IfType!=IF_TYPE_SOFTWARE_LOOPBACK) {
        for(auto u=a->FirstUnicastAddress;u;u=u->Next) if(u->Address.lpSockaddr->sa_family==AF_INET) {
            auto ip=reinterpret_cast<sockaddr_in*>(u->Address.lpSockaddr)->sin_addr;
            if(privateIp(ntohl(ip.s_addr))) { char b[INET_ADDRSTRLEN]{}; inet_ntop(AF_INET,&ip,b,sizeof b); result.insert(b); }
        }
    }
    std::string out;
    for(const auto& ip:result) { if(!out.empty()) out+=","; out+=ip; }
    return out;
}
using Deadline=std::chrono::steady_clock::time_point;
static bool waitTls(SSL* ssl,int result,Deadline deadline) {
    int error=SSL_get_error(ssl,result);
    if(error!=SSL_ERROR_WANT_READ && error!=SSL_ERROR_WANT_WRITE)return false;
    SOCKET fd=connection.load();if(fd==INVALID_SOCKET)return false;
    while(!stopping && std::chrono::steady_clock::now()<deadline) {
        fd_set fds;FD_ZERO(&fds);FD_SET(fd,&fds);timeval timeout{0,100000};
        int ready=select(0,error==SSL_ERROR_WANT_READ?&fds:nullptr,error==SSL_ERROR_WANT_WRITE?&fds:nullptr,nullptr,&timeout);
        if(ready>0)return true;if(ready<0)return false;
    }
    return false;
}
static bool readExact(SSL* ssl, void* out, size_t size,Deadline deadline=std::chrono::steady_clock::now()+std::chrono::seconds(10)) {
    auto p=static_cast<unsigned char*>(out);
    while(size && !stopping && std::chrono::steady_clock::now()<deadline) {
        size_t got=0;
        int rc=SSL_read_ex(ssl,p,size,&got);
        if(rc!=1){if(waitTls(ssl,rc,deadline))continue;return false;}
        if(!got)return false;
        p+=got;size-=got;
    }
    return size==0;
}
static bool writeExact(SSL* ssl,const void* data,size_t size) {
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);
    auto p=static_cast<const unsigned char*>(data);
    while(size && !stopping && std::chrono::steady_clock::now()<deadline){size_t sent=0;int rc=SSL_write_ex(ssl,p,size,&sent);if(rc!=1){if(waitTls(ssl,rc,deadline))continue;return false;}if(!sent)return false;p+=sent;size-=sent;}
    return size==0;
}
static uint32_t be32(const unsigned char* p) { return (uint32_t(p[0])<<24)|(uint32_t(p[1])<<16)|(uint32_t(p[2])<<8)|p[3]; }
static uint64_t be64(const unsigned char* p) { return (uint64_t(be32(p))<<32)|be32(p+4); }
struct Decoder {
    AVCodecContext* context=nullptr; AVFrame* frame=nullptr; AVPacket* packet=nullptr; SwsContext* scaler=nullptr;
    Decoder() {
        context=avcodec_alloc_context3(avcodec_find_decoder(AV_CODEC_ID_H264)); require(context!=nullptr);
        context->max_pixels=4096LL*4096; context->thread_count=2; context->flags|=AV_CODEC_FLAG_LOW_DELAY;
        require(avcodec_open2(context,avcodec_find_decoder(AV_CODEC_ID_H264),nullptr)>=0);
        frame=av_frame_alloc(); packet=av_packet_alloc(); require(frame && packet);
    }
    ~Decoder() { sws_freeContext(scaler);av_packet_free(&packet);av_frame_free(&frame);avcodec_free_context(&context); }
    void decode(const std::vector<uint8_t>& bytes, int64_t pts) {
        av_packet_unref(packet); require(av_new_packet(packet,static_cast<int>(bytes.size()))>=0);
        std::copy(bytes.begin(),bytes.end(),packet->data); packet->pts=pts;
        if(avcodec_send_packet(context,packet)<0) return;
        while(avcodec_receive_frame(context,frame)==0) {
            int w=frame->width,h=frame->height;
            require(w>0 && h>0 && w<=4096 && h<=4096 && int64_t(w)*h<=16777216);
            scaler=sws_getCachedContext(scaler,w,h,static_cast<AVPixelFormat>(frame->format),w,h,AV_PIX_FMT_RGBA,SWS_FAST_BILINEAR,nullptr,nullptr,nullptr);
            require(scaler!=nullptr);
            Picture image;image.w=w;image.h=h;image.rgba.resize(size_t(w)*h*4);
            uint8_t* dst[]={image.rgba.data(),nullptr,nullptr,nullptr}; int stride[]={w*4,0,0,0};
            sws_scale(scaler,frame->data,frame->linesize,0,h,dst,stride);
            { std::lock_guard<std::mutex> lock(frameMutex);latest=std::move(image); }
            ++generation;
        }
    }
};
static std::pair<SOCKET,SSL*> authenticate(SOCKET listener,SSL_CTX* ctx,const std::string& token,Deadline expires) {
    struct Pending {SOCKET fd;SSL* ssl;uint32_t ip;Deadline deadline;bool tls=false,wantWrite=false;size_t used=0;std::array<unsigned char,72> auth{};};
    std::vector<Pending> pending;pending.reserve(8);
    auto rateStart=std::chrono::steady_clock::now();unsigned accepted=0;
    auto dispose=[](Pending& p){SSL_free(p.ssl);closesocket(p.fd);};
    while(!stopping && std::chrono::steady_clock::now()<expires) {
        fd_set readable,writable;FD_ZERO(&readable);FD_ZERO(&writable);FD_SET(listener,&readable);
        for(auto& p:pending){if(p.wantWrite)FD_SET(p.fd,&writable);else FD_SET(p.fd,&readable);}
        timeval wait{0,100000};int ready=select(0,&readable,&writable,nullptr,&wait);if(ready<0)break;
        auto now=std::chrono::steady_clock::now();
        for(size_t i=0;i<pending.size();) {
            auto& p=pending[i];bool close=now>=p.deadline;
            if(!close && (FD_ISSET(p.fd,&readable) || FD_ISSET(p.fd,&writable) || SSL_pending(p.ssl)>0)) {
                int rc=1;
                if(!p.tls){rc=SSL_accept(p.ssl);if(rc==1)p.tls=true;}
                if(rc==1 && p.tls){size_t got=0;rc=SSL_read_ex(p.ssl,p.auth.data()+p.used,p.auth.size()-p.used,&got);if(rc==1){if(!got)close=true;p.used+=got;p.wantWrite=false;}}
                if(rc!=1){int error=SSL_get_error(p.ssl,rc);p.wantWrite=error==SSL_ERROR_WANT_WRITE;if(error!=SSL_ERROR_WANT_READ && error!=SSL_ERROR_WANT_WRITE)close=true;}
                if(p.used==p.auth.size()) {
                    if(!close && std::chrono::steady_clock::now()<p.deadline && CRYPTO_memcmp(p.auth.data(),"YANDA03\n",8)==0 && CRYPTO_memcmp(p.auth.data()+8,token.data(),64)==0){
                        auto result=std::make_pair(p.fd,p.ssl);pending.erase(pending.begin()+i);for(auto& other:pending)dispose(other);return result;
                    }
                    close=true;
                }
            }
            if(close){dispose(p);pending.erase(pending.begin()+i);}else ++i;
        }
        if(ready>0 && FD_ISSET(listener,&readable)) {
            sockaddr_in peer{};int len=sizeof peer;SOCKET fd=accept(listener,reinterpret_cast<sockaddr*>(&peer),&len);if(fd==INVALID_SOCKET)continue;
            uint32_t ip=ntohl(peer.sin_addr.s_addr);
            if(now-rateStart>=std::chrono::seconds(1)){rateStart=now;accepted=0;}
            if(++accepted>32 || (!privateIp(ip) && (ip>>24)!=127) || pending.size()>=8 || std::any_of(pending.begin(),pending.end(),[&](const Pending& p){return p.ip==ip;})){closesocket(fd);continue;}
            u_long nonblocking=1;if(ioctlsocket(fd,FIONBIO,&nonblocking)!=0){closesocket(fd);continue;}
            BOOL yes=TRUE;setsockopt(fd,IPPROTO_TCP,TCP_NODELAY,reinterpret_cast<char*>(&yes),sizeof yes);
            SSL* ssl=SSL_new(ctx);if(!ssl){closesocket(fd);continue;}SSL_set_fd(ssl,static_cast<int>(fd));
            pending.push_back(Pending{fd,ssl,ip,std::min(expires,now+std::chrono::seconds(4))});
        }
    }
    for(auto& p:pending)dispose(p);return {INVALID_SOCKET,nullptr};
}
static void receive(SOCKET listener, SSL_CTX* ctx, std::string token, bool audioEnabled, int maxSize, int fps) {
    bool authenticated=false;
    auto expires=std::chrono::steady_clock::now()+std::chrono::seconds(180);
    while(!stopping && std::chrono::steady_clock::now()<expires && !authenticated) {
        auto session=authenticate(listener,ctx,token,expires);SOCKET client=session.first;SSL* ssl=session.second;
        if(!ssl)break;connection=client;closesocket(listener);listener=INVALID_SOCKET;
        authenticated=true; std::fill(token.begin(),token.end(),char(0));
        unsigned char ack[17]{};memcpy(ack,"YANDAOK\n",8);ack[8]=audioEnabled?1:0;
        uint32_t size=htonl(maxSize),rate=htonl(fps);memcpy(ack+9,&size,4);memcpy(ack+13,&rate,4);
        if(!writeExact(ssl,ack,sizeof ack)) { SSL_free(ssl);closesocket(client);connection=INVALID_SOCKET;break; }
        marker("YANDA_COMPANION_CONNECTED");
        SDL_AudioDeviceID audio=0;
        try {
            Decoder decoder;
            while(!stopping) {
                const auto packetDeadline=std::chrono::steady_clock::now()+std::chrono::seconds(10);
                unsigned char header[13];if(!readExact(ssl,header,sizeof header,packetDeadline)) break;
                unsigned type=header[0];uint32_t count=be32(header+1);auto pts=be64(header+5);
                if(type==3 && count==0) break;
                require((type==1 && count>0 && count<=8*1024*1024) || (type==2 && count>0 && count<=192000 && count%4==0) || (type==4 && count==0) || (type==5 && count==0));
                if(type==4){if(audioEnabled){marker("YANDA_AUDIO_UNAVAILABLE");audioEnabled=false;}continue;}
                if(type==5){if(!writeExact(ssl,"\1",1))break;continue;} // heartbeat for otherwise static/silent screen
                std::vector<uint8_t> bytes(count);if(!readExact(ssl,bytes.data(),count,packetDeadline))break;
                if(type==1) decoder.decode(bytes,static_cast<int64_t>(pts));
                if(type==2 && audioEnabled) {
                    if(!audio) {
                        SDL_AudioSpec desired{};desired.freq=48000;desired.format=AUDIO_S16LSB;desired.channels=2;desired.samples=512;
                        audio=SDL_OpenAudioDevice(nullptr,0,&desired,nullptr,0);
                        if(audio){SDL_PauseAudioDevice(audio,0);marker("YANDA_AUDIO");}else marker("YANDA_AUDIO_UNAVAILABLE");
                    }
                    if(audio){if(SDL_GetQueuedAudioSize(audio)>48000)SDL_ClearQueuedAudio(audio);SDL_QueueAudio(audio,bytes.data(),count);}
                }
            }
        } catch(...) { marker("YANDA_ERROR"); }
        if(audio) SDL_CloseAudioDevice(audio);
        SSL_free(ssl);closesocket(client);connection=INVALID_SOCKET;
    }
    if(listener!=INVALID_SOCKET)closesocket(listener);
    if(authenticated)marker("YANDA_COMPANION_DISCONNECTED");else if(!stopping)marker("YANDA_COMPANION_EXPIRED");
    finished=true;
}
int main(int argc,char** argv) {
    setvbuf(stdout,nullptr,_IONBF,0);
    av_log_set_level(AV_LOG_QUIET);
    bool audio=true;int maxSize=1920,fps=30;
    for(int i=1;i<argc;++i){std::string arg=argv[i];if(arg=="--no-audio")audio=false;else if(arg=="--max-size" && i+1<argc)maxSize=std::clamp(atoi(argv[++i]),640,2560);else if(arg=="--fps" && i+1<argc)fps=atoi(argv[++i])==60?60:30;}
    try {
        std::string token;std::getline(std::cin,token);
        require(token.size()==64 && token.find_first_not_of("0123456789abcdef")==std::string::npos);
        WSADATA ws{};require(WSAStartup(MAKEWORD(2,2),&ws)==0);
        SSL_CTX* ctx=SSL_CTX_new(TLS_server_method());require(ctx!=nullptr);SSL_CTX_set_min_proto_version(ctx,TLS1_3_VERSION);
        EVP_PKEY* key=EVP_PKEY_Q_keygen(nullptr,nullptr,"RSA",2048);require(key!=nullptr);
        X509* cert=X509_new();require(cert!=nullptr);X509_set_version(cert,2);ASN1_INTEGER_set(X509_get_serialNumber(cert),1);
        X509_gmtime_adj(X509_get_notBefore(cert),-60);X509_gmtime_adj(X509_get_notAfter(cert),86400);X509_set_pubkey(cert,key);
        X509_NAME* name=X509_get_subject_name(cert);X509_NAME_add_entry_by_txt(name,"CN",MBSTRING_ASC,reinterpret_cast<const unsigned char*>("Y AND A local session"),-1,-1,0);X509_set_issuer_name(cert,name);
        require(X509_sign(cert,key,EVP_sha256())>0);require(SSL_CTX_use_certificate(ctx,cert)==1 && SSL_CTX_use_PrivateKey(ctx,key)==1 && SSL_CTX_check_private_key(ctx)==1);
        unsigned char digest[32];unsigned n=0;require(X509_digest(cert,EVP_sha256(),digest,&n)==1 && n==32);
        std::string fingerprint;const char hex[]="0123456789abcdef";for(auto b:digest){fingerprint+=hex[b>>4];fingerprint+=hex[b&15];}
        X509_free(cert);EVP_PKEY_free(key);
        SOCKET listener=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);require(listener!=INVALID_SOCKET);
        BOOL exclusive=TRUE;require(setsockopt(listener,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,reinterpret_cast<char*>(&exclusive),sizeof exclusive)==0);
        sockaddr_in addr{};addr.sin_family=AF_INET;addr.sin_addr.s_addr=htonl(INADDR_ANY);addr.sin_port=0;
        require(bind(listener,reinterpret_cast<sockaddr*>(&addr),sizeof addr)==0 && listen(listener,4)==0);int alen=sizeof addr;getsockname(listener,reinterpret_cast<sockaddr*>(&addr),&alen);
        u_long listenerNonblocking=1;require(ioctlsocket(listener,FIONBIO,&listenerNonblocking)==0);
        SDL_SetMainReady();
        SDL_SetHint(SDL_HINT_WINDOWS_DPI_AWARENESS,"permonitorv2");
        SDL_SetHint("SDL_BORDERLESS_RESIZABLE_STYLE","1");
        SDL_SetHint(SDL_HINT_RENDER_DRIVER,"direct3d11");
        require(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_AUDIO)==0);
        SDL_Window* window=SDL_CreateWindow("Y AND A media",-32000,-32000,640,480,SDL_WINDOW_HIDDEN|SDL_WINDOW_BORDERLESS|SDL_WINDOW_RESIZABLE);require(window!=nullptr);
        SDL_SysWMinfo wm{};SDL_VERSION(&wm.version);require(SDL_GetWindowWMInfo(window,&wm)==SDL_TRUE);
        SDL_Renderer* renderer=nullptr;
        // This private readiness line is parsed by Rust, never copied into diagnostics.
        marker("YANDA_COMPANION_READY "+std::to_string(ntohs(addr.sin_port))+" "+fingerprint+" "+addresses());
        std::thread worker(receive,listener,ctx,std::move(token),audio,maxSize,fps);
        SDL_Texture* texture=nullptr;int width=0,height=0;unsigned drawn=0;bool announced=false;
        while(!stopping && !finished) {
            SDL_Event event;while(SDL_PollEvent(&event))if(event.type==SDL_QUIT || (event.type==SDL_WINDOWEVENT && event.window.event==SDL_WINDOWEVENT_CLOSE))stopping=true;
            // The Rust supervisor reparents/resizes this foreign HWND. Synchronize
            // SDL's own client/window cache before creating or presenting a renderer.
            // Otherwise borderless WM_NCCALCSIZE can retain the initial 640x480 size.
            if(GetParent(wm.info.win.window)!=nullptr) {
                RECT rect{};GetWindowRect(wm.info.win.window,&rect);
                int targetW=rect.right-rect.left,targetH=rect.bottom-rect.top,sw=0,sh=0;
                SDL_GetWindowSize(window,&sw,&sh);
                if(targetW>1 && targetH>1 && (sw!=targetW || sh!=targetH))SDL_SetWindowSize(window,targetW,targetH);
                if(!renderer && targetW>1 && targetH>1) {
                    SDL_ShowWindow(window);
                    renderer=SDL_CreateRenderer(window,-1,SDL_RENDERER_ACCELERATED);
                    if(!renderer)renderer=SDL_CreateRenderer(window,-1,SDL_RENDERER_SOFTWARE);
                    if(!renderer){marker("YANDA_ERROR");stopping=true;break;}
                }
            }
            // Standalone protocol tests have no parent; allow rendering after data
            // arrives without opening a visible desktop window in the product path.
            if(!renderer && generation.load()>0 && GetParent(wm.info.win.window)==nullptr) {
                renderer=SDL_CreateRenderer(window,-1,SDL_RENDERER_SOFTWARE);if(!renderer){marker("YANDA_ERROR");stopping=true;break;}
            }
            auto current=generation.load();
            if(renderer && current!=drawn) {
                std::lock_guard<std::mutex> lock(frameMutex);
                if(latest.w!=width || latest.h!=height) {
                    if(texture)SDL_DestroyTexture(texture);width=latest.w;height=latest.h;
                    texture=SDL_CreateTexture(renderer,SDL_PIXELFORMAT_ABGR8888,SDL_TEXTUREACCESS_STREAMING,width,height);
                    if(!texture){marker("YANDA_ERROR");stopping=true;break;}
                    if(SDL_RenderSetLogicalSize(renderer,width,height)!=0){marker("YANDA_ERROR");stopping=true;break;}announced=false;
                }
                if(SDL_UpdateTexture(texture,nullptr,latest.rgba.data(),width*4)!=0){marker("YANDA_ERROR");stopping=true;break;}drawn=current;
            }
            if(renderer && texture) {
                SDL_SetRenderDrawColor(renderer,8,8,8,255);
                if(SDL_RenderClear(renderer)!=0 || SDL_RenderCopy(renderer,texture,nullptr,nullptr)!=0){marker("YANDA_ERROR");stopping=true;break;}
                SDL_RenderPresent(renderer);
                if(!announced){marker("YANDA_VIDEO "+std::to_string(width)+"x"+std::to_string(height));announced=true;}
            }
            SDL_Delay(8);
        }
        stopping=true;SOCKET client=connection.load();if(client!=INVALID_SOCKET)shutdown(client,SD_BOTH);
        worker.join();if(texture)SDL_DestroyTexture(texture);if(renderer)SDL_DestroyRenderer(renderer);SDL_DestroyWindow(window);SDL_Quit();SSL_CTX_free(ctx);WSACleanup();return 0;
    } catch(...) { marker("YANDA_ERROR");return 1; }
}
