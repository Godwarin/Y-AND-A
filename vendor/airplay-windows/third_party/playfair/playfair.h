#ifndef PLAYFAIR_H
#define PLAYFAIR_H

#include <stddef.h>

int playfair_decrypt(unsigned char* message3, size_t messageLen,
                     unsigned char* cipherText, size_t cipherLen, unsigned char* keyOut);

#endif
