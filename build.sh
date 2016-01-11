#!/bin/bash

#echo `pwd`/lib

PREFIX="`pwd`/local"

cd musl && ./configure --prefix=$PREFIX --enable-shared=no > /dev/null && cd .. && make -j2 -s -C musl && make -s -C musl install

gcc -specs=./local/lib/musl-gcc.specs -static -O2 -fomit-frame-pointer -o test main.c

strip -x -X --strip-unneeded test
objcopy --remove-section .comment test
objcopy --remove-section .eh_frame test
objcopy --remove-section .jcr test
