#Find the correct architecture to build for
ifndef ARCH
	ARCH = $(shell getconf LONG_BIT)
endif

UNAME = $(shell uname)

#Set correct flags for build type

ifeq ($(UNAME), Darwin)
	OSNAME = osx
else
	OSNAME = lin
endif

ifdef DEBUG
	BINDIR = bin_d/$(OSNAME)$(ARCH)
	OBJDIR = obj_d/$(OSNAME)$(ARCH)
	LIBDIR = obj_d/$(OSNAME)$(ARCH)

	BUILDTYPE = debug
	OPTFLAGS = -O0 -g
	CXXFLAGS += $(OPTFLAGS)
	CXXFLAGS += -D_DEBUG
else
	BINDIR = bin/$(OSNAME)$(ARCH)
	OBJDIR = obj/$(OSNAME)$(ARCH)
	LIBDIR = obj/$(OSNAME)$(ARCH)
	BUILDTYPE = release
	OPTFLAGS = -Ofast
	CXXFLAGS += $(OPTFLAGS)
ifdef ADD_DBG
	CXXFLAGS += -g
else
	CXXFLAGS += -DNDEBUG
endif
ifndef NLTO
ifeq (,$(findstring g++, $(CC)))
	CXXFLAGS += -flto=6
else
	CXXFLAGS += -flto=thin
endif
else
	CXXFLAGS += -fno-lto
endif
endif

#Set correct flags for architecture
ifeq ($(ARCH), 32)
	#Global
	ARCHFLAGS = -m32 -march=pentium4 -mtune=generic
	CXXFLAGS += $(ARCHFLAGS)

	#Arch name
	ARCHNAME = x86
else
	#Global
	CXXFLAGS += $(ARCHFLAGS)

	#Angelscript
	CXXFLAGS += -DAS_64BIT_PTR

	#Arch name
	ARCHNAME = x64
endif

#Global flags
BIN = StarRuler2.bin
MS_BIN = MasterServer.bin
SRCDIR = source/game

ifndef CC
	CC = g++
endif

CXXFLAGS += -std=c++11
CXXFLAGS += -DLIN_MODE -DGLIBCXX_USE_NANOSLEEP
CXXFLAGS += -Wall -Wno-invalid-offsetof -Wno-switch -Wno-reorder
CXXFLAGS += -Wno-unused-local-typedefs
CXXFLAGS += -Wuninitialized -Wmaybe-uninitialized
CXXFLAGS += -Werror=return-type
CXXFLAGS += -I./source/game -I./source/angelscript/include
CXXFLAGS += -I/usr/include/freetype2 -isystem./source/glfw/include
CXXFLAGS += -I./source/sound/include
CXXFLAGS += -I./source/as_addons/include -I./source/os/include
CXXFLAGS += -I./source/libircclient/include
CXXFLAGS += -I./source/util/include -I./source/network/include
CXXFLAGS += -I./source/rapidjson/include

NSTEAM=1
CXXFLAGS += -DNSTEAM

ifndef GCC48
	CXXFLAGS += -fdiagnostics-color=auto
endif

ifeq ($(UNAME), Darwin)
	CXXFLAGS += -I/usr/local/opt/freetype/include
	CXXFLAGS += -I/usr/local/opt/freetype/include/freetype2
	LDFLAGS += -L/usr/local/opt/freetype/lib

	CXXFLAGS += -I/usr/local/Cellar/libpng/1.6.12/include
	LDFLAGS += -L/usr/local/Cellar/libpng/1.6.12/lib

	CXXFLAGS += -I/usr/local/Cellar/glew/1.10.0/include
	LDFLAGS += -L/usr/local/Cellar/glew/1.10.0/lib
	
	CXXFLAGS += -framework OpenGL -framework Cocoa -framework IOKit
	CXXFLAGS += -framework OpenAL

	LDFLAGS += -lcurl
else
	ifndef DEBUG
		LDFLAGS += -Lsource/lib/lin$(ARCH)
	endif
	LDFLAGS += -lGL -lGLU -lX11 -lXrandr -lXxf86vm -lXi -lopenal -lcurl

endif

#Libraries
LDFLAGS += -lstdc++ -lGLEW -lpng -lz -lpthread
LDFLAGS += -lm -lfreetype
LDFLAGS += -lvorbisfile

LIB_FILES += $(LIBDIR)/libangelscript.a
LIB_FILES += $(LIBDIR)/libglfw3.a
LIB_FILES += $(LIBDIR)/libsound.a
LIB_FILES += $(LIBDIR)/libas_addons.a
LIB_FILES += $(LIBDIR)/libircclient.a
LIB_FILES += $(LIBDIR)/libos.a
LIB_FILES += $(LIBDIR)/libnetwork.a
LIB_FILES += $(LIBDIR)/libutil.a

NOCOPYLIBS=1
ifndef NOCOPYLIBS
ifeq ($(UNAME), Darwin)
	COPY_LIBS += lib/libGLEW.1.10.0.dylib
	COPY_LIBS += opt/libpng/lib/libpng16.16.dylib
	COPY_LIBS += opt/freetype/lib/libfreetype.6.dylib
	COPY_LIBS += lib/gcc/x86_64-apple-darwin11.4.2/4.8.3/libstdc++.6.dylib
	COPY_LIBS += lib/libvorbisfile.3.dylib
	COPY_LIBS += lib/libogg.0.dylib
	COPY_LIBS += Cellar/gcc/4.8.3_1/lib/gcc/x86_64-apple-darwin11.4.2/4.8.3/libgcc_s.1.dylib
	COPY_LIBS += Cellar/libvorbis/1.3.4/lib/libvorbis.0.dylib
else
	COPY_LIBS += libstdc++.so
	COPY_LIBS += libpng.so
	COPY_LIBS += libz.so
	COPY_LIBS += libGLEW.so
	COPY_LIBS += libGLU.so
	COPY_LIBS += libfreetype.so
	COPY_LIBS += libvorbisfile.so
	COPY_LIBS += libvorbis.so
	COPY_LIBS += libogg.so
	COPY_LIBS += libopenal.so
	COPY_LIBS += libgcc_s.so
	COPY_LIBS += libbz2.so
	COPY_LIBS += libharfbuzz.so
	COPY_LIBS += libgraphite2.so
	COPY_LIBS += libglib-2.0.so
	COPY_LIBS += libpcre.so
	#COPY_LIBS += libcurl.so #customized without ssl/ssh deps
endif
endif

#Source code files
SOURCES = \
	as/as_jit.cpp \
	\
	design/design.cpp \
	design/effect.cpp \
	design/effector.cpp \
	design/effector_functions.cpp \
	design/hull.cpp \
	design/subsystem.cpp \
	design/projectiles.cpp \
	\
	gui/skin.cpp \
	\
	main/initialization.cpp \
	main/input_handling.cpp \
	main/logging.cpp \
	main/profiler.cpp \
	main/references.cpp \
	main/tick.cpp \
	main/console.cpp \
	main/save_load.cpp \
	\
	mods/mod_manager.cpp \
	\
	network/network_manager.cpp \
	\
	obj/blueprint.cpp \
	obj/lock.cpp \
	obj/object.cpp \
	obj/obj_group.cpp \
	obj/universe.cpp \
	obj/object_saving.cpp \
	\
	os/glfw_driver.cpp \
	\
	physics/physics_world.cpp \
	\
	profile/keybinds.cpp \
	profile/settings.cpp \
	\
	render/camera.cpp \
	render/font_fnt.cpp \
	render/font_ft2.cpp \
	render/gl_driver.cpp \
	render/gl_framebuffer.cpp \
	render/gl_mesh.cpp \
	render/gl_shader.cpp \
	render/gl_texture.cpp \
	render/gl_vertexBuffer.cpp \
	render/lighting.cpp \
	render/obj_loader.cpp \
	render/ogex_loader.cpp \
	render/render_state.cpp \
	render/spritesheet.cpp \
	render/x_loader.cpp \
	render/bmf_loader.cpp \
	render/shader_states.cpp \
	\
	resource/library.cpp \
	resource/load_font.cpp \
	resource/load_material.cpp \
	resource/load_model.cpp \
	resource/load_shader.cpp \
	resource/load_skin.cpp \
	resource/load_sound.cpp \
	resource/locale.cpp \
	resource/hot_loading.cpp \
	\
	scene/animation/anim_linear.cpp \
	scene/animation/anim_group.cpp \
	scene/animation/anim_node_sync.cpp \
	scene/animation/anim_projectile.cpp \
	\
	scene/particle_system.cpp \
	scene/billboard_node.cpp \
	scene/beam_node.cpp \
	scene/line_trail_node.cpp \
	scene/frame_line.cpp \
	scene/mesh_node.cpp \
	scene/plane_node.cpp \
	scene/mesh_icon_node.cpp \
	scene/icon_node.cpp \
	scene/scripted_node.cpp \
	scene/culling_node.cpp \
	scene/node.cpp \
	\
	scripts/bind_creation.cpp \
	scripts/bind_data.cpp \
	scripts/bind_design.cpp \
	scripts/bind_empire.cpp \
	scripts/bind_general.cpp \
	scripts/bind_gui.cpp \
	scripts/bind_inspection.cpp \
	scripts/bind_joystick.cpp \
	scripts/bind_menu.cpp \
	scripts/bind_object.cpp \
	scripts/bind_profile.cpp \
	scripts/bind_render.cpp \
	scripts/bind_threading.cpp \
	scripts/bind_events.cpp \
	scripts/bind_formula.cpp \
	scripts/bind_sound.cpp \
	scripts/bind_dynamic.cpp \
	scripts/bind_network.cpp \
	scripts/bind_savefile.cpp \
	scripts/bind_datafile.cpp \
	scripts/bind_json.cpp \
	scripts/bind_web.cpp \
	scripts/bind_irc.cpp \
	scripts/binds.cpp \
	scripts/context_cache.cpp \
	scripts/manager.cpp \
	scripts/script_bind.cpp \
	scripts/generic_call.cpp \
	scripts/script_type.cpp \
	scripts/script_components.cpp \
	scripts/script_hooks.cpp \
	\
	util/format.cpp \
	util/formula.cpp \
	util/generic.cpp \
	util/mesh_generation.cpp \
	util/random.cpp \
	util/threaded_loader.cpp \
	util/elevation_map.cpp \
	util/name_generator.cpp \
	util/stat_history.cpp \
	util/bbcode.cpp \
	util/save_file.cpp \
	\
	empire.cpp \
	empire_stats.cpp \
	general_states.cpp \
	processing.cpp \
	main.cpp

CPP_FILES = $(addprefix $(SRCDIR)/, $(SOURCES))
OBJ_FILES = $(addprefix $(OBJDIR)/, $(SOURCES:.cpp=.o))
DEP_FILES = $(addprefix $(OBJDIR)/, $(SOURCES:.cpp=.d))

-include $(DEP_FILES)

compile: $(DEP_FILES) $(BINDIR)/$(BIN)
master_server: $(BINDIR)/$(MS_BIN)

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
$(BINDIR)/$(BIN): makelibs $(OBJ_FILES) $(LIB_FILES) $(COPY_LIBS)
	@mkdir -p $(BINDIR)
	@$(CC) $(CXXFLAGS) $(OBJ_FILES) $(LIB_FILES) $(LDFLAGS) -o $@

makelibs:
	@mkdir -p $(BINDIR)
	@$(MAKE) -s -f ./source/os/gcc/Makefile compile
	@$(MAKE) -s -f ./source/sound/gcc/Makefile compile
	@$(MAKE) -s -f ./source/as_addons/gcc/Makefile compile
	@$(MAKE) -s -f ./source/libircclient/gcc/Makefile compile
	@$(MAKE) -s -f ./source/network/gcc/Makefile compile
	@$(MAKE) -s -f ./source/util/gcc/Makefile compile

%.so:
	@cp "$$(realpath $$(gcc $(ARCHFLAGS) $(LDFLAGS) --print-file-name=$@))" "$(BINDIR)/$@"
	@mv "$(BINDIR)/$@" "$(BINDIR)/$$(objdump -p $(BINDIR)/$@ | grep SONAME | awk '{print $$2}')"

%.dylib:
	@cp /usr/local/$@ "$(BINDIR)/$$(basename $@)"

$(BINDIR)/$(MS_BIN): $(OBJDIR)/master_server.o $(LIBDIR)/libnetwork.a $(LIBDIR)/libos.a
	@mkdir -p $(BINDIR)
	@$(CC) $(CXXFLAGS) -lstdc++ -lpthread -lm $^ -o $@

patcher: $(LIB_FILES)
	@$(CC) $(CXXFLAGS) source/patcher/patcher/patcher.cpp $(LIB_FILES) $(LDFLAGS) -o $(BINDIR)/Patcher.bin

version:
	bash /source/linux/build.sh version

#Library builds
$(LIBDIR)/libangelscript.a:
	bash source/linux/build.sh $(ARCH) $(BUILDTYPE) angelscript

$(LIBDIR)/libglfw3.a:
	bash source/linux/build.sh $(ARCH) $(BUILDTYPE) glfw

#$(LIBDIR)/libbreakpad_client.a:
	#./source/linux/build.sh $(ARCH) $(BUILDTYPE) breakpad

$(LIBDIR)/libsound.a:
	$(MAKE) -f ./source/sound/gcc/Makefile compile

$(LIBDIR)/libas_addons.a:
	$(MAKE) -f ./source/as_addons/gcc/Makefile compile

$(LIBDIR)/libircclient.a:
	$(MAKE) -f ./source/libircclient/gcc/Makefile compile

$(LIBDIR)/libnetwork.a:
	$(MAKE) -f ./source/network/gcc/Makefile compile

$(LIBDIR)/libos.a:
	$(MAKE) -f ./source/os/gcc/Makefile compile

$(LIBDIR)/libutil.a:
	$(MAKE) -f ./source/util/gcc/Makefile compile

#Explicit rebuilds
clean_angelscript:
	rm -f $(LIBDIR)/libangelscript.a
angelscript: clean_angelscript
	bash source/linux/build.sh $(ARCH) $(BUILDTYPE) angelscript

clean_glfw:
	rm -f $(LIBDIR)/libglfw3.a
glfw:
	bash source/linux/build.sh $(ARCH) $(BUILDTYPE) glfw

#clean_breakpad:
	#rm -f $(LIBDIR)/libbreakpad_client.a
#breakpad:
	#./source/linux/build.sh $(ARCH) $(BUILDTYPE) breakpad

clean_sound:
	rm -f $(LIBDIR)/libsound.a
sound:
	$(MAKE) -f ./source/sound/gcc/Makefile compile

clean_as_addons:
	rm -f $(LIBDIR)/libas_addons.a
as_addons:
	$(MAKE) -f ./source/as_addons/gcc/Makefile compile

clean_libircclient:
	rm -f $(LIBDIR)/libircclient.a
libircclient:
	$(MAKE) -f ./source/libircclient/gcc/Makefile compile

clean_os:
	rm -f $(LIBDIR)/libos.a
os:
	$(MAKE) -f ./source/os/gcc/Makefile compile

clean_util:
	rm -f $(LIBDIR)/libutil.a
util:
	$(MAKE) -f ./source/util/gcc/Makefile compile

clean_network:
	rm -f $(LIBDIR)/libnetwork.a
network:
	$(MAKE) -f ./source/network/gcc/Makefile compile

clean_code:
	@find $(OBJDIR) -iname *.o -delete
	@find $(OBJDIR) -iname *.d -delete
	@rm -f ./.depend

clean:
	@rm -rf $(OBJDIR)
	@rm -f ./.depend
