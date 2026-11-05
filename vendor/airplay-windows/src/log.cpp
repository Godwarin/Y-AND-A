#include "log.h"

#include <atomic>
#include <chrono>
#include <ctime>
#include <cstdio>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <sstream>
#include <regex>

namespace ap {
namespace {

std::mutex& log_mutex() {
    static std::mutex m;
    return m;
}

// Off by default. The CLI (--log / --verbose) flips this on.
std::atomic<bool> g_log_enabled{false};

const char* level_tag(LogLevel lvl) {
    switch (lvl) {
        case LogLevel::Debug: return "DEBUG";
        case LogLevel::Info:  return "INFO ";
        case LogLevel::Warn:  return "WARN ";
        case LogLevel::Error: return "ERROR";
    }
    return "?";
}

std::string timestamp() {
    using namespace std::chrono;
    auto now = system_clock::now();
    auto t   = system_clock::to_time_t(now);
    auto ms  = duration_cast<milliseconds>(now.time_since_epoch()) % 1000;
    std::tm tm{};
#if defined(_WIN32)
    localtime_s(&tm, &t);
#else
    localtime_r(&t, &tm);
#endif
    std::ostringstream os;
    os << std::put_time(&tm, "%H:%M:%S") << '.'
       << std::setfill('0') << std::setw(3) << ms.count();
    return os.str();
}

} // namespace

void log_write(LogLevel level, const std::string& msg) {
    if (!g_log_enabled.load(std::memory_order_relaxed)) return;
    // Embedded mode emits only non-sensitive lifecycle events.
    static const std::regex lifecycle(R"(YANDA_(READY|BIND_ERROR|AUDIO|DISCONNECTED|MDNS_ERROR|MDNS_(AIRPLAY|RAOP)_(REGISTERED|ERROR [0-9]{1,10})|VIDEO [0-9]{1,4}x[0-9]{1,4}))");
    if (std::getenv("YANDA_EMBEDDED") && !std::regex_match(msg,lifecycle)) {
        if (level == LogLevel::Error) {
            std::lock_guard<std::mutex> lock(log_mutex());
            const bool audio = msg.find("audio") != std::string::npos || msg.find("Audio") != std::string::npos || msg.find("AUDIO") != std::string::npos || msg.find("AAC") != std::string::npos;
            std::fprintf(stderr, audio ? "YANDA_AUDIO_UNAVAILABLE\n" : "YANDA_ERROR\n"); std::fflush(stderr);
        }
        return;
    }
    std::lock_guard<std::mutex> lock(log_mutex());
    std::fprintf(stderr, "[%s] %s  %s\n",
                 timestamp().c_str(), level_tag(level), msg.c_str());
    std::fflush(stderr);
}

void set_log_enabled(bool on) {
    g_log_enabled.store(on, std::memory_order_relaxed);
}

bool is_log_enabled() {
    return g_log_enabled.load(std::memory_order_relaxed);
}

} // namespace ap
