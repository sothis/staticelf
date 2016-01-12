#!/bin/bash

WD="`pwd`"
cd musl && CFLAGS=-O2 ./configure --prefix="$WD/local" --enable-shared=no > /dev/null && cd .. && make -s -j2 -C musl && make -s -C musl install

gcc -specs=./local/lib/musl-gcc.specs -static -O2 -fomit-frame-pointer -o test main.c

strip -x -X --strip-unneeded test
objcopy --remove-section .comment test
objcopy --remove-section .eh_frame test
objcopy --remove-section .jcr test
