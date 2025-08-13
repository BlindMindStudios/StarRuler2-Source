# Modern AngelScript Makefile for Linux/Unix-like systems
# Usage samples:
#   make                      # Release static lib (default)
#   make SHARED=1 VERSION=2.37.0        # Build shared lib with SONAME + symlinks
#   make BUILD=debug V=1                  # Debug build, verbose output
#   make LTO=1 SHARED=1                   # Shared lib with LTO (uses gcc-ar/gcc-ranlib)
#   make install PREFIX=/usr DESTDIR=/pkgroot
#   make uninstall PREFIX=/usr

# -----------------------
# Configuration (tweak here or via env)
# -----------------------
# Back-compat: allow LOCAL to override PREFIX if provided
PREFIX ?= /usr/local
ifneq ($(origin LOCAL), undefined)
  PREFIX := $(LOCAL)
endif

DESTDIR ?=
INCLUDEDIR ?= $(PREFIX)/include
LIBDIR ?= $(PREFIX)/lib
PKGCONFIGDIR ?= $(LIBDIR)/pkgconfig

# Source tree layout (relative to this Makefile)
SRCDIR ?= ../../source
INCDIR ?= ../../include
INC     = angelscript.h

# Build layout (out-of-tree)
OBJDIR ?= build/obj
OUTDIR ?= build/lib

# Build mode: release|debug
BUILD ?= release

# Build type: static (default) or shared if SHARED=1
SHARED ?= 0
# Optional version, e.g. 2.37.0. Enables SONAME and symlinks for shared libs.
VERSION ?=

# Optional features
LTO ?= 0
PTHREAD ?= 1

# Toolchain
CXX ?= g++
AR  ?= ar
RANLIB ?= ranlib
INSTALL ?= install
LN ?= ln -sf
MKDIR ?= mkdir -p
RM ?= rm -f

# Quiet vs verbose (V=1 for verbose)
V ?= 0
ifeq ($(V),1)
  Q :=
else
  Q := @
endif

# -----------------------
# Flags
# -----------------------
CPPFLAGS += -I$(INCDIR)
CXXFLAGS += -fPIC -Wall -Wextra -fno-strict-aliasing
LDFLAGS  +=

# Build mode flags
ifeq ($(BUILD),debug)
  CPPFLAGS += -DDEBUG
  CXXFLAGS += -O0 -g
else
  CPPFLAGS += -DNDEBUG
  CXXFLAGS += -O2
endif

# Threads (AngelScript uses threading on POSIX)
ifeq ($(PTHREAD),1)
  CXXFLAGS += -pthread
  LDFLAGS  += -pthread
endif

# LTO
ifeq ($(LTO),1)
  CXXFLAGS += -flto
  LDFLAGS  += -flto
  AR := gcc-ar
  RANLIB := gcc-ranlib
endif

# Shared/static selection
LIBNAME := angelscript
ifeq ($(SHARED),1)
  # Shared library
  ifneq ($(strip $(VERSION)),)
    MAJOR := $(firstword $(subst ., ,$(VERSION)))
    LIB     := lib$(LIBNAME).so.$(VERSION)
    SONAME  := lib$(LIBNAME).so.$(MAJOR)
  else
    LIB     := lib$(LIBNAME).so
    SONAME  := $(LIB)
  endif
  LDFLAGS += -shared -Wl,-soname,$(SONAME)
else
  # Static library
  LIB := lib$(LIBNAME).a
endif

OUT := $(OUTDIR)/$(LIB)

# -----------------------
# Sources
# (Preserve original explicit list; safer than wildcard for arch-specific files)
# -----------------------
SRCNAMES = \
  as_atomic.cpp \
  as_builder.cpp  \
  as_bytecode.cpp \
  as_callfunc.cpp \
  as_callfunc_arm.cpp \
  as_callfunc_mips.cpp \
  as_callfunc_ppc.cpp \
  as_callfunc_ppc_64.cpp \
  as_callfunc_sh4.cpp \
  as_callfunc_x86.cpp \
  as_callfunc_x64_gcc.cpp \
  as_callfunc_x64_mingw.cpp \
  as_compiler.cpp \
  as_context.cpp \
  as_configgroup.cpp \
  as_datatype.cpp \
  as_generic.cpp \
  as_gc.cpp \
  as_globalproperty.cpp \
  as_memory.cpp \
  as_module.cpp \
  as_objecttype.cpp \
  as_outputbuffer.cpp \
  as_parser.cpp \
  as_restore.cpp \
  as_scriptcode.cpp \
  as_scriptengine.cpp \
  as_scriptfunction.cpp \
  as_scriptnode.cpp \
  as_scriptobject.cpp \
  as_string.cpp \
  as_string_util.cpp \
  as_thread.cpp \
  as_tokenizer.cpp \
  as_typeinfo.cpp \
  as_variablescope.cpp

SRCS := $(addprefix $(SRCDIR)/,$(SRCNAMES))
OBJS := $(patsubst $(SRCDIR)/%.cpp,$(OBJDIR)/%.o,$(SRCS))
DEPS := $(OBJS:.o=.d)

# -----------------------
# Top-level targets
# -----------------------
.PHONY: all clean distclean install uninstall help
all: $(OUT)

help:
	@echo "Targets:"
	@echo "  make [SHARED=0|1] [VERSION=X.Y.Z] [BUILD=release|debug] [LTO=0|1] [V=0|1]"
	@echo "  make install PREFIX=/usr/local [DESTDIR=/staging]"
	@echo "  make uninstall PREFIX=/usr/local"
	@echo "Notes:"
	@echo "  - SHARED=1 builds a shared library with proper SONAME if VERSION is set."
	@echo "  - LTO=1 uses gcc-ar/gcc-ranlib automatically."
	@echo "  - Headers are installed from $(INCDIR)/$(INC)."

# -----------------------
# Build rules
# -----------------------
$(OUT): $(OUTDIR) $(OBJDIR) $(OBJS)
ifeq ($(SHARED),1)
	$(Q)$(CXX) $(LDFLAGS) -o $@ $(OBJS)
else
	$(Q)$(AR) rcs $@ $(OBJS)
	$(Q)$(RANLIB) $@
endif
	@echo "-------------------------------------------------------------------"
	@echo "Built: $@"
	@echo "Run 'make install' to install the library."

$(OBJDIR):
	$(Q)$(MKDIR) $(OBJDIR)

$(OUTDIR):
	$(Q)$(MKDIR) $(OUTDIR)

# C++ sources -> objects with depfiles
$(OBJDIR)/%.o: $(SRCDIR)/%.cpp
	$(Q)$(CXX) $(CPPFLAGS) $(CXXFLAGS) -MMD -MP -MF $(@:.o=.d) -c $< -o $@

# (Optional) Assembly sources
$(OBJDIR)/%.o: $(SRCDIR)/%.S
	$(Q)$(CXX) $(CPPFLAGS) $(CXXFLAGS) -MMD -MP -MF $(@:.o=.d) -c $< -o $@
$(OBJDIR)/%.o: $(SRCDIR)/%.s
	$(Q)$(CXX) $(CPPFLAGS) $(CXXFLAGS) -MMD -MP -MF $(@:.o=.d) -c $< -o $@

# Auto-include depfiles if present
-include $(DEPS)

# -----------------------
# Install / Uninstall
# -----------------------
install: $(OUT)
	@echo "Installing to: $(DESTDIR)$(LIBDIR) and $(DESTDIR)$(INCLUDEDIR)"
	$(Q)$(MKDIR) $(DESTDIR)$(LIBDIR) $(DESTDIR)$(INCLUDEDIR)
	# Install library
	$(Q)$(INSTALL) -m 755 -D $(OUT) $(DESTDIR)$(LIBDIR)/$(notdir $(OUT))
ifeq ($(SHARED),1)
ifneq ($(strip $(VERSION)),)
	# Create SONAME and devel symlinks: .so.$(MAJOR) and .so
	$(Q)cd $(DESTDIR)$(LIBDIR) && $(LN) lib$(LIBNAME).so.$(VERSION) lib$(LIBNAME).so.$(MAJOR)
	$(Q)cd $(DESTDIR)$(LIBDIR) && $(LN) lib$(LIBNAME).so.$(MAJOR) lib$(LIBNAME).so
else
	# Ensure libangelscript.so devel link exists
	$(Q)cd $(DESTDIR)$(LIBDIR) && [ -e lib$(LIBNAME).so ] || $(LN) $(notdir $(OUT)) lib$(LIBNAME).so
endif
endif
	# Install header
	$(Q)$(INSTALL) -m 644 -D $(INCDIR)/$(INC) $(DESTDIR)$(INCLUDEDIR)/$(INC)
	# Install pkg-config file
	$(Q)$(MKDIR) $(DESTDIR)$(PKGCONFIGDIR)
	$(Q)echo "prefix=$(PREFIX)"                                  >  $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)echo "exec_prefix=\$${prefix}"                          >> $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)echo "libdir=\$${exec_prefix}/lib"                      >> $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)echo "includedir=\$${prefix}/include"                   >> $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)echo ""                                                 >> $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)echo "Name: AngelScript"                                >> $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)echo "Description: AngelScript scripting library"       >> $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)echo "Version: $(if $(strip $(VERSION)),$(VERSION),0.0)" >> $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)echo "Libs: -L\$${libdir} -l$(LIBNAME)"                 >> $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)echo "Cflags: -I\$${includedir}"                        >> $(OUTDIR)/lib$(LIBNAME).pc
	$(Q)$(INSTALL) -m 644 -D $(OUTDIR)/lib$(LIBNAME).pc $(DESTDIR)$(PKGCONFIGDIR)/lib$(LIBNAME).pc
	@echo "-------------------------------------------------------------------"
	@echo "AngelScript library installed."

uninstall:
	@echo "Uninstalling from: $(DESTDIR)$(LIBDIR) and $(DESTDIR)$(INCLUDEDIR)"
	$(Q)$(RM) $(DESTDIR)$(INCLUDEDIR)/$(INC)
	$(Q)$(RM) $(DESTDIR)$(PKGCONFIGDIR)/lib$(LIBNAME).pc
ifeq ($(SHARED),1)
ifneq ($(strip $(VERSION)),)
	$(Q)$(RM) $(DESTDIR)$(LIBDIR)/lib$(LIBNAME).so.$(VERSION)
	$(Q)$(RM) $(DESTDIR)$(LIBDIR)/lib$(LIBNAME).so.$(MAJOR)
endif
	$(Q)$(RM) $(DESTDIR)$(LIBDIR)/lib$(LIBNAME).so
endif
	$(Q)$(RM) $(DESTDIR)$(LIBDIR)/lib$(LIBNAME).a
	@echo "-------------------------------------------------------------------"
	@echo "AngelScript library uninstalled."

clean:
	$(Q)$(RM) $(OBJS) $(DEPS)

distclean: clean
	$(Q)$(RM) -r $(OBJDIR) $(OUTDIR)
