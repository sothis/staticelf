PROJECT_NAME		:= static
C_STD			:= c99

VERSION		:= $(shell ./version)
MAKEFILE_DIR	:= $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
UNAMEEXISTS	:= $(shell uname > /dev/null 2>&1; echo $$?)
GCCEXISTS	:= $(shell gcc --version > /dev/null 2>&1; echo $$?)
#CLANGEXISTS	:= $(shell clang --version > /dev/null 2>&1; echo $$?)

# NOTE: using absolute paths here (like MAKEFILE_DIR) brakes header dependency
# paths on windows
PREFIX		:= ./build

ifeq ($(VERSION),)
$(error can't determine version string)
endif
ifeq ($(CONF), debug)
	DEBUG		:= Yes
endif
ifeq ($(CONF), release)
	RELEASE		:= Yes
endif

ifeq ($(TOOLCHAIN), gcc)
	TOOLCHAIN	:= TOOLCHAIN_GCC
else ifeq ($(TOOLCHAIN), clang)
	TOOLCHAIN	:= TOOLCHAIN_CLANG
else
	TOOLCHAIN	:= TOOLCHAIN_UNDEFINED
endif

ifeq ($(CLANGEXISTS), 0)
	HAVE_CLANG	:= Yes
endif
ifeq ($(GCCEXISTS), 0)
	HAVE_GCC	:= Yes
endif
ifneq ($(UNAMEEXISTS), 0)
$(error 'uname' not found)
endif

ifndef HAVE_GCC
ifndef HAVE_CLANG
$(error neither 'gcc', nor 'clang' found)
endif
endif

# tools
STRIP		:=  $(CROSS)strip
ifeq ($(TOOLCHAIN), gcc)
	CC	:= $(CROSS)gcc
	LD	:= $(CROSS)gcc
endif
ifeq ($(TOOLCHAIN), clang)
	CC	:= $(CROSS)clang
	LD	:= $(CROSS)clang
endif

ARCHITECTURE	:= $(shell uname -m)
PLATFORM	:= $(shell uname)

ifeq ($(PLATFORM), Linux)
	PLAT_LINUX	:= Yes
	PLATFORM	:= LINUX
	SO_EXT		:= so
else
$(error unsupported platform: $(PLATFORM))
endif

ifndef VERBOSE
	VERB		:= -s
endif

################################################################################

INCLUDES	+= -I./src

SRC		+= ./src/main.c

################################################################################


# preprocessor definitions
DEFINES		+= -DVERSION='"$(VERSION)"'
DEFINES		+= -D$(PLATFORM)=1
DEFINES		+= -D$(TOOLCHAIN)=1

ifdef RELEASE
DEFINES		+= -DNDEBUG=1
endif
DEFINES		+= -D_GNU_SOURCE=1
DEFINES		+= -D_POSIX_C_SOURCE=200809L
DEFINES		+= -D_BSD_SOURCE=1
DEFINES		+= -D_DEFAULT_SOURCE=1
DEFINES		+= -D_FILE_OFFSET_BITS=64
DEFINES		+= -D_LARGEFILE64_SOURCE=1
DEFINES		+= -D_LARGEFILE_SOURCE=1
DEFINES		+= -D_REENTRANT=1

# toolchain configuration

OUTDIR		:= $(PREFIX)
BUILDDIR	:= $(OUTDIR)/$(TOOLCHAIN)_$(CONF)
MUSLPREFIX	:= $(abspath $(BUILDDIR)/.musl)

# common flags
CFLAGS		:= -specs=$(MUSLPREFIX)/lib/musl-gcc.specs
CFLAGS		+= -std=$(C_STD)
CFLAGS		+= -Wall
CFLAGS		+= -g
CFLAGS		+= -march=native
CFLAGS		+= -static
CFLAGS		+= -fomit-frame-pointer

ifdef DEBUG
CFLAGS		+= -O0
endif
ifdef RELEASE
CFLAGS		+= -O3
endif

LDFLAGS		:= $(CFLAGS)

# determine intermediate object filenames
C_SRC		:= $(filter %.c, $(SRC))
DEPS		:= $(patsubst %.c, $(BUILDDIR)/.obj/%_C.dep, $(C_SRC))
OBJECTS		:= $(patsubst %.c, $(BUILDDIR)/.obj/%_C.o, $(C_SRC))

print_ld	:= echo $(eflags) "LD   "
print_cc	:= echo $(eflags) "CC   "
print_strip	:= echo $(eflags) "STRIP"
print_build	:= echo $(eflags) "BUILD"

# targets
.PHONY: all help debug release Debug Release clean
.PHONY: all-recursive clean-recursive final-all-recursive
all: release

help:
	@echo "following make targets are available:"
	@echo "  help        - print this"
	@echo "  release     - build release version of $(PROJECT_NAME) (*)"
	@echo "  debug       - build debug version of $(PROJECT_NAME)"
	@echo "  clean       - recursively delete the output directories"
	@echo ""
	@echo "(*) denotes the default target if none or 'all' is specified"

debug:
	@$(MAKE) $(VERB) -C '$(MAKEFILE_DIR)' CONF=debug all-recursive

release:
	@$(MAKE) $(VERB) -C '$(MAKEFILE_DIR)' CONF=release all-recursive

Release: release
Debug: debug

clean:
	@$(MAKE) $(VERB) -C '$(MAKEFILE_DIR)' clean-recursive

clean-recursive:
	@echo "deleting '$(OUTDIR)'"
	@-rm -rf $(OUTDIR)
	@echo "cleaning './musl'"
	@GIT_DIR=./musl/.git git reset --hard > /dev/null
	@GIT_DIR=./musl/.git git clean -xdff > /dev/null

$(MUSLPREFIX)/lib/musl-gcc.specs:
	$(print_build) ./musl
	cd musl && \
	CFLAGS="-O3 -fomit-frame-pointer -march=native" \
	./configure --prefix="$(MUSLPREFIX)" \
	--enable-shared=no > /dev/null && \
	cd .. && \
	$(MAKE) $(VERB) -C musl && \
	$(MAKE) $(VERB) -C musl install

all-recursive:
ifdef HAVE_GCC
	$(MAKE) $(VERB) -C '$(MAKEFILE_DIR)' TOOLCHAIN=gcc musl-recursive
endif
ifdef HAVE_CLANG
	$(MAKE) $(VERB) -C '$(MAKEFILE_DIR)' TOOLCHAIN=clang musl-recursive
endif

musl-recursive: $(MUSLPREFIX)/lib/musl-gcc.specs
ifdef HAVE_GCC
	$(MAKE) $(VERB) -C '$(MAKEFILE_DIR)' TOOLCHAIN=gcc final-all-recursive
endif
ifdef HAVE_CLANG
	$(MAKE) $(VERB) -C '$(MAKEFILE_DIR)' TOOLCHAIN=clang final-all-recursive
endif

final-all-recursive: $(BUILDDIR)/$(PROJECT_NAME)

$(BUILDDIR)/$(PROJECT_NAME): $(OBJECTS)
	$(print_ld) $(subst $(PWD)/,./,$(abspath $(@)))
	@-mkdir -p $(dir $(@))
	@export LD_RUN_PATH='$${ORIGIN}' && $(LD) $(LDFLAGS) -o $(@) \
	$(^) $(LIBRARIES)
ifdef RELEASE
	$(print_strip) $(subst $(PWD)/,./,$(abspath $(@)))
	@$(STRIP) -x -X --strip-unneeded $(subst $(PWD)/,./,$(abspath $(@)))
	@objcopy --remove-section .comment $(subst $(PWD)/,./,$(abspath $(@)))
	@objcopy --remove-section .eh_frame $(subst $(PWD)/,./,$(abspath $(@)))
	@objcopy --remove-section .jcr $(subst $(PWD)/,./,$(abspath $(@)))
endif

$(BUILDDIR)/.obj/%_C.o: %.c
	$(print_cc) $(subst $(PWD)/,./,$(abspath $(<)))
	-mkdir -p $(dir $(@))
	$(CC) $(CFLAGS) $(DEFINES) $(INCLUDES) -E -M -MT \
		"$(@) $(@:.o=.dep)" -o $(@:.o=.dep) $(<)
	$(CC) $(CFLAGS) $(DEFINES) $(INCLUDES) -c -o $(@) $(<)

-include $(DEPS)
