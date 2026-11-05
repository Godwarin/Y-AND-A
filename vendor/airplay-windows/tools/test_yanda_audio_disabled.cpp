#include "audio/audio_output.h"
#include <SDL.h>
#include <cstdio>
#include <cstdlib>

void disabled(const char* value) {
#if defined(_WIN32)
    _putenv_s("YANDA_AUDIO_DISABLED", value);
#else
    setenv("YANDA_AUDIO_DISABLED", value, 1);
#endif
}

int main() {
    SDL_setenv("SDL_AUDIODRIVER", "dummy", 1);
    disabled("1");
    ap::audio::SdlAudioOutput output;
    if (!output.start(48000, 2) || SDL_WasInit(SDL_INIT_AUDIO) != 0) return 1;
    const int16_t pcm[8] = {1, -1, 2, -2, 3, -3, 4, -4};
    output.push(pcm, 8);
    if (output.queued_bytes() != 0 || output.pending_ns() != 0) return 2;
    output.stop();
    disabled("0");
    if (!output.start(48000, 2) || SDL_WasInit(SDL_INIT_AUDIO) == 0) return 3;
    output.stop(); SDL_Quit();
    std::puts("PASS: disabled audio never opens a device; normal mode opens dummy output");
    return 0;
}
