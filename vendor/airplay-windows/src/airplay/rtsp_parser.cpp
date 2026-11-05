#include "airplay/rtsp_parser.h"
#include "net/socket.h"
#include "log.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <sstream>
#include <charconv>
#include <limits>

namespace ap::airplay {
namespace {

std::string to_lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    return s;
}

std::string trim(const std::string& s) {
    auto a = s.find_first_not_of(" \t");
    auto b = s.find_last_not_of(" \t");
    if (a == std::string::npos) return "";
    return s.substr(a, b - a + 1);
}

} // namespace

std::string Request::header(const std::string& key) const {
    auto it = headers.find(to_lower(key));
    return it == headers.end() ? std::string{} : it->second;
}

std::size_t Request::content_length() const {
    auto v = header("content-length");
    if (v.empty()) return 0;
    std::size_t result=0;const auto parsed=std::from_chars(v.data(),v.data()+v.size(),result);
    return parsed.ec==std::errc{} && parsed.ptr==v.data()+v.size()?result:std::numeric_limits<std::size_t>::max();
}

void Response::set_header(std::string key, std::string value) {
    headers[std::move(key)] = std::move(value);
}

std::string Response::serialize() const {
    std::ostringstream os;
    os << version << ' ' << status_code << ' ' << status_text << "\r\n";
    for (const auto& [k, v] : headers) {
        os << k << ": " << v << "\r\n";
    }
    os << "Content-Length: " << body.size() << "\r\n";
    os << "\r\n";
    std::string head = os.str();
    head.append(reinterpret_cast<const char*>(body.data()), body.size());
    return head;
}

int RequestReader::receive(socket_t fd,char* data,int count) {
    while(!cancelled_ || !cancelled_->load()) {
        if(!idle_ && std::chrono::steady_clock::now()>=deadline_)return -1;
        fd_set fds;FD_ZERO(&fds);FD_SET(fd,&fds);timeval wait{0,100000};
        int ready=::select(static_cast<int>(fd)+1,&fds,nullptr,nullptr,&wait);
        if(ready<0)return -1;
        if(ready>0){int got=::recv(fd,data,count,0);if(idle_){idle_=false;deadline_=std::chrono::steady_clock::now()+std::chrono::seconds(10);}return got;}
    }
    return -1;
}
bool RequestReader::fill(socket_t fd, std::size_t need) {
    char tmp[4096];
    while (buffer_.size() < need) {
        int n = receive(fd, tmp, static_cast<int>(std::min(sizeof(tmp),need-buffer_.size())));
        if (n <= 0) return false;
        buffer_.append(tmp, n);
    }
    return true;
}

bool RequestReader::read_headers(socket_t fd, Request& out, std::size_t& body_offset) {
    // Grow buffer_ until we see CRLFCRLF.
    char tmp[4096];
    while (true) {
        auto pos = buffer_.find("\r\n\r\n");
        if (pos != std::string::npos) {
            body_offset = pos + 4;
            break;
        }
        int n = receive(fd, tmp, sizeof(tmp));
        if (n <= 0) return false;
        buffer_.append(tmp, n);
        if (buffer_.size() > 64 * 1024) {
            LOG_WARN << "header section too large, dropping connection";
            return false;
        }
    }

    // Parse request line.
    auto line_end = buffer_.find("\r\n");
    std::string line = buffer_.substr(0, line_end);
    std::istringstream ls(line);
    if (!(ls >> out.method >> out.uri >> out.version)) {
        LOG_WARN << "malformed request line: " << line;
        return false;
    }

    // Normalise absolute URIs. iOS sometimes sends
    //   POST rtsp://192.168.1.5:7000/pair-verify RTSP/1.0
    // rather than a path-only URI. Strip scheme://host[:port] so the
    // dispatcher can keep matching on req.uri == "/pair-verify".
    if (out.uri.rfind("rtsp://", 0) == 0 || out.uri.rfind("http://", 0) == 0) {
        auto scheme_end = out.uri.find("://");
        auto path_start = out.uri.find('/', scheme_end + 3);
        out.uri = (path_start == std::string::npos) ? "/"
                                                    : out.uri.substr(path_start);
    }

    // Parse headers.
    std::size_t p = line_end + 2;
    while (p < body_offset - 2) {
        auto eol = buffer_.find("\r\n", p);
        if (eol == std::string::npos || eol > body_offset - 2) break;
        std::string h = buffer_.substr(p, eol - p);
        p = eol + 2;
        if (h.empty()) break;
        auto colon = h.find(':');
        if (colon == std::string::npos || colon==0) return false;
        std::string key   = to_lower(trim(h.substr(0, colon)));
        std::string value = trim(h.substr(colon + 1));
        if(key=="transfer-encoding" || (key=="content-length" && out.headers.count(key)))return false;
        out.headers[key] = value;
    }
    return true;
}

bool RequestReader::read(socket_t fd, Request& out) {
    out = {};
    idle_=authorized_ && buffer_.empty();
    deadline_=std::chrono::steady_clock::now()+std::chrono::seconds(5);
    if (cancelled_ && cancelled_->load()) return false;

    std::size_t body_offset = 0;
    if (!read_headers(fd, out, body_offset)) return false;

    std::size_t clen = out.content_length();
    if(out.headers.count("content-length") && out.header("content-length").empty())return false;
    const std::size_t limit=authorized_ && out.method=="SET_PARAMETER" && out.header("content-type").rfind("image/",0)==0?8*1024*1024:64*1024;
    if(clen>limit || body_offset>64*1024 || clen>std::numeric_limits<std::size_t>::max()-body_offset)return false;
    std::size_t need = body_offset + clen;
    if (buffer_.size() < need) {
        if (!fill(fd, need)) return false;
    }

    out.body.assign(
        reinterpret_cast<const unsigned char*>(buffer_.data() + body_offset),
        reinterpret_cast<const unsigned char*>(buffer_.data() + body_offset + clen));

    // Shift leftover bytes (pipelined requests) to the front.
    buffer_.erase(0, need);
    return true;
}

} // namespace ap::airplay
