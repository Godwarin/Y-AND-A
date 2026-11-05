#pragma once
#include <openssl/rand.h>
#include <openssl/sha.h>
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#endif

namespace ap::airplay {
// Approval is tied to a verified Ed25519 client key AND peer address. RAM only.
// The only authority is the inherited private stdin pipe from the Rust parent.
class Approval {
    std::mutex mutex_;
    std::condition_variable changed_;
    std::string id_, fingerprint_, peer_, allowed_key_, allowed_peer_, input_;
    std::chrono::steady_clock::time_point expires_;
    bool stopped_=false;
    bool discard_input_=false;
    void end_locked() {
        if(!id_.empty()){std::fprintf(stderr,"YANDA_APPROVAL_END %s\n",id_.c_str());std::fflush(stderr);}
        id_.clear();changed_.notify_all();
    }
public:
    static Approval& instance(){static Approval value;return value;}
    static std::string fingerprint(const std::vector<unsigned char>& key) {
        if(key.size()!=32)return {};
        unsigned char digest[SHA256_DIGEST_LENGTH];SHA256(key.data(),key.size(),digest);
        std::string out;constexpr char hex[]="0123456789abcdef";
        for(auto b:digest){out+=hex[b>>4];out+=hex[b&15];}return out;
    }
    bool allowed(const std::string& key,const std::string& peer) {
        std::lock_guard<std::mutex> lock(mutex_);
        return !stopped_ && !key.empty() && key==allowed_key_ && peer==allowed_peer_;
    }
    bool request(const std::string& key,const std::string& peer) {
        std::unique_lock<std::mutex> lock(mutex_);
        if(stopped_ || key.empty())return false;
        if(!allowed_key_.empty())return key==allowed_key_ && peer==allowed_peer_;
        if(!id_.empty())return false; // one pending request; no prompt/queue flooding
        unsigned char random[16];if(RAND_bytes(random,sizeof random)!=1)return false;
        constexpr char hex[]="0123456789abcdef";id_.clear();for(auto b:random){id_+=hex[b>>4];id_+=hex[b&15];}
        fingerprint_=key;peer_=peer;expires_=std::chrono::steady_clock::now()+std::chrono::seconds(20);
        std::fprintf(stderr,"YANDA_APPROVAL %s %s %s\n",id_.c_str(),key.c_str(),peer.c_str());std::fflush(stderr);
        const auto requestId=id_;
        changed_.wait_until(lock,expires_,[&]{return id_!=requestId || stopped_;});
        if(id_==requestId)end_locked();
        return !stopped_ && key==allowed_key_ && peer==allowed_peer_;
    }
    void command(const std::string& line) {
        std::istringstream stream(line);std::string action,id,extra;stream>>action>>id;
        if(stream>>extra)return;
        std::lock_guard<std::mutex> lock(mutex_);
        if(stopped_ || id_.empty() || id!=id_ || std::chrono::steady_clock::now()>=expires_)return;
        if(action=="ALLOW"){allowed_key_=fingerprint_;allowed_peer_=peer_;end_locked();}
        else if(action=="DENY")end_locked();
    }
    void poll() {
#ifdef _WIN32
        HANDLE pipe=GetStdHandle(STD_INPUT_HANDLE);DWORD available=0;
        if(!PeekNamedPipe(pipe,nullptr,0,nullptr,&available,nullptr))return;
        if(available){char data[256];DWORD got=0;if(ReadFile(pipe,data,std::min<DWORD>(available,sizeof data),&got,nullptr)){
            for(DWORD i=0;i<got;++i){if(data[i]=='\r')continue;if(data[i]=='\n'){if(!discard_input_)command(input_);input_.clear();discard_input_=false;}else if(!discard_input_){if(input_.size()<128)input_+=data[i];else{input_.clear();discard_input_=true;}}}
        }}
#endif
    }
    void stop(){std::lock_guard<std::mutex> lock(mutex_);stopped_=true;end_locked();allowed_key_.clear();allowed_peer_.clear();}
};
}
