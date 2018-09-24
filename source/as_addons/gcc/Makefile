#Find the correct architecture to build for
ifndef ARCH
	ARCH = $(shell getconf LONG_BIT)
endif

#Set correct flags for architecture
ifeq ($(ARCH), 32)
	#Global
	CXXFLAGS += -m32 -march=pentium4 -mtune=generic

	#Arch name
	ARCHNAME = x86
else
	#Global

	#Arch name
	ARCHNAME = x64
endif

#Global flags
BIN = libas_addons.a
SRCDIR = source/as_addons/source

ifeq ($(origin AR), default)
	AR = gcc-ar
endif

UNAME = $(shell uname)
ifeq ($(UNAME), Darwin)
	OSNAME = osx
else
	OSNAME = lin
endif

ifdef DEBUG
	OBJDIR = obj_d/$(OSNAME)$(ARCH)/as_addons
	BINDIR = obj_d/$(OSNAME)$(ARCH)

	CXXFLAGS += -O0 -g
	CXXFLAGS += -D_DEBUG
else
	OBJDIR = obj/$(OSNAME)$(ARCH)/as_addons
	BINDIR = obj/$(OSNAME)$(ARCH)

	CXXFLAGS += -Wno-unused-variable -Wno-unused-but-set-variable
	CXXFLAGS += -Ofast
	CXXFLAGS += -DNDEBUG
ifndef NLTO
	CXXFLAGS += -flto
else
	CXXFLAGS += -fno-lto
endif
endif

ifndef CC
	CC = g++
endif

CXXFLAGS += -std=c++11
CXXFLAGS += -Wall -Wno-invalid-offsetof -Wno-switch -Wno-reorder
CXXFLAGS += -I./source/as_addons/include -I./source/as_addons/source
CXXFLAGS += -isystem./source/angelscript/include

#Source code files
SOURCES = \
	scriptany.cpp \
	scriptarray.cpp \
	scriptdictionary.cpp \
	scriptmap.cpp \
	scripthandle.cpp \
	scriptmath.cpp \
	scriptstdstring.cpp \
	scriptstdstring_utils.cpp \
	scripthelper.cpp

CPP_FILES = $(addprefix $(SRCDIR)/, $(SOURCES))
OBJ_FILES = $(addprefix $(OBJDIR)/, $(SOURCES:.cpp=.o))
DEP_FILES = $(addprefix $(OBJDIR)/, $(SOURCES:.cpp=.d))

-include $(DEP_FILES)

compile: $(DEP_FILES) $(BINDIR)/$(BIN)

#Dependency files to take care of header changes
$(OBJDIR)/%.d: $(SRCDIR)/%.cpp
	@mkdir -p $(dir $@)
	@$(CC) $(CXXFLAGS) -MM -MT "$(@:.d=.o)" $< >> $@

#Object files are compiled separately
$(OBJDIR)/%.o: $(SRCDIR)/%.cpp
	@mkdir -p $(dir $@)
	@echo $<
	@$(CC) $(CXXFLAGS) $< -c -o $@

#Complete binary compile
$(BINDIR)/$(BIN): $(OBJ_FILES)
	@mkdir -p $(BINDIR)
	$(AR) rcs $@ $^

clean:
	@rm -rf $(OBJDIR)
	@rm -f ./.depend
