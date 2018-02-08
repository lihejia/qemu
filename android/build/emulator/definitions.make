# Copyright (C) 2008 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

BUILD_SYSTEM_ROOT := $(_BUILD_CORE_DIR)

# We use the GNU Make Standard Library
include $(BUILD_SYSTEM_ROOT)/gmsl/gmsl

include $(_BUILD_CORE_DIR)/core/definitions-tests.mk
include $(_BUILD_CORE_DIR)/core/definitions-init.mk
include $(_BUILD_CORE_DIR)/core/definitions-utils.mk
include $(_BUILD_CORE_DIR)/core/definitions-host.mk
include $(_BUILD_CORE_DIR)/core/definitions-graph.mk
include $(_BUILD_CORE_DIR)/core/definitions-modules.mk
include $(_BUILD_CORE_DIR)/core/definitions-files.mk
#include $(_BUILD_CORE_DIR)/core/definitions-build.mk

# Replace all extensions in files from $1 matching any of
# $(LOCAL_CXX_EXTENSION_PATTERNS) with .o
local-cxx-src-to-obj = $(strip \
    $(eval _local_cxx_src := $1)\
    $(foreach pattern,$(LOCAL_CXX_EXTENSION_PATTERNS),\
        $(eval _local_cxx_src := $$(_local_cxx_src:$(pattern)=%.o)))\
    $(_local_cxx_src))

# Return the directory containing the intermediate files for a given
# kind of executable
# $1 = bitness (32 or 64)
# $2 = module name
intermediates-dir-for = $(BUILD_OBJS_DIR)/build/intermediates$(1)/$(2)

# Return the name of a given build-related variable that can be defined either
# for the build host or build target. I.e. if LOCAL_HOST_BUILD is not defined,
# return $(BUILD_TARGET_$1), or $(BUILD_HOST_$1) instead.
# $1: Variable name suffix (e.g. CC, LD, etc...)
local-build-var = $(if $(strip $(LOCAL_HOST_BUILD)),$(BUILD_HOST_$1),$(BUILD_TARGET_$1))

# If LOCAL_XXX is not defined, set it to the value of BUILD_TARGET_XXX or
# BUILD_HOST_XXX depending on the definition of LOCAL_HOST_BUILD.
local-build-define = $(if $(strip $(LOCAL_$1)),,$(eval LOCAL_$1 := $$(call local-build-var,$1)))

# Return the directory containing the intermediate files for the current
# module. LOCAL_MODULE must be defined before calling this.
local-intermediates-dir = $(call intermediates-dir-for,$(BUILD_TARGET_BITS),$(LOCAL_MODULE))

# Return the directory containing the source files generated by the 'protoc' tool.
# See LOCAL_PROTO_SOURCES for details.
generated-proto-sources-dir = $(call intermediates-dir-for,$(BUILD_TARGET_BITS),proto-sources)

# Location of intermediate static libraries during build.
local-library-path = $(call intermediates-dir-for,$(BUILD_TARGET_BITS),$(1))/$(1).a

# Location of unstripped executables during build.
local-executable-path = $(call intermediates-dir-for,$(BUILD_TARGET_BITS),$(1))/$(1)$(call local-build-var,EXEEXT)

# Location of unstripped shared libraries during build.
local-shared-library-path = $(call intermediates-dir-for,$(BUILD_TARGET_BITS),$(1))/$(1)$(call local-build-var,DLLEXT)

# Location of final (potentially stripped) executables.
local-executable-install-path = $(BUILD_OBJS_DIR)/$(if $(LOCAL_INSTALL_DIR),$(LOCAL_INSTALL_DIR)/)$(1)$(call local-build-var,EXEEXT)

# Location of final (potentially stripped) shared libraries.
local-shared-library-install-path = $(BUILD_OBJS_DIR)/$(if $(LOCAL_INSTALL_DIR),$(LOCAL_INSTALL_DIR),lib$(BUILD_TARGET_SUFFIX))/$(1)$(call local-build-var,DLLEXT)

# Location of final symbol file based on final executable/shared library path
local-symbol-install-path = $(subst $(BUILD_OBJS_DIR),$(_BUILD_SYMBOLS_DIR),$(1)).sym

# Location of final debug info file based on final executable/shared library path
local-debug-info-install-path = $(subst $(BUILD_OBJS_DIR),$(_BUILD_DEBUG_INFO_DIR),$(1))$(if $(findstring darwin,$(BUILD_TARGET_OS)),.dSYM)

# Location of resource files
local-resource-install-path = $(BUILD_OBJS_DIR)/$(if $(LOCAL_INSTALL_DIR),$(LOCAL_INSTALL_DIR)/)resources/$(1)

ldlibs_start_whole := -Wl,--whole-archive
ldlibs_end_whole := -Wl,--no-whole-archive
ldlibs_force_load := -Wl,-force_load,

# Return the list of local static libraries
local-static-libraries-ldlibs-darwin = $(strip \
   $(foreach lib,$(LOCAL_WHOLE_STATIC_LIBRARIES),\
       $(ldlibs_force_load)$(call local-library-path,$(lib)))\
   $(foreach lib,$(LOCAL_STATIC_LIBRARIES),\
       $(call local-library-path,$(lib))))

local-static-libraries-ldlibs-linux = $(strip \
    $(if $(LOCAL_WHOLE_STATIC_LIBRARIES), \
        $(ldlibs_start_whole) \
        $(foreach lib,$(LOCAL_WHOLE_STATIC_LIBRARIES),$(call local-library-path,$(lib))) \
        $(ldlibs_end_whole) \
    ) \
    $(foreach lib,$(LOCAL_STATIC_LIBRARIES),$(call local-library-path,$(lib))) \
    )

local-static-libraries-ldlibs-windows =  $(local-static-libraries-ldlibs-linux)

# TODO(zyy): add -Wl,--start-group / end-group here for gcc builds after
# migrating our Mac build to LLVM linker.
local-static-libraries-ldlibs = $(local-static-libraries-ldlibs-$(BUILD_TARGET_OS))

# Expand to a shell statement that changes the runtime library search path.
# Note that this is only used for Qt-related stuff, and on Windows, the
# Windows libraries are placed under bin/ instead of lib/ so there is no
# point in changing the PATH variable.
set-host-library-search-path = $(call set-host-library-search-path-$(BUILD_TARGET_OS),$1)
set-host-library-search-path-linux = LD_LIBRARY_PATH=$1
set-host-library-search-path-darwin = DYLD_LIBRARY_PATH=$1
set-host-library-search-path-windows =

# Toolchain control support.
# It's possible to switch between the regular toolchain and the host one
# in certain cases.

# Compile a C source file
#
define  compile-c-source
SRC:=$(1)
OBJ:=$$(LOCAL_OBJS_DIR)/$$(SRC:%.c=%.o)
LOCAL_OBJECTS += $$(OBJ)
_BUILD_DEPENDENCY_DIRS += $$(dir $$(OBJ))
$$(OBJ): PRIVATE_CFLAGS := $$(LOCAL_CFLAGS) -I$$(LOCAL_PATH) -I$$(LOCAL_OBJS_DIR)
$$(OBJ): PRIVATE_CC     := $$(LOCAL_CC)
$$(OBJ): PRIVATE_OBJ    := $$(OBJ)
$$(OBJ): PRIVATE_MODULE := $$(LOCAL_MODULE)
$$(OBJ): PRIVATE_SRC    := $$(LOCAL_PATH)/$$(SRC)
$$(OBJ): PRIVATE_SRC0   := $$(SRC)
$$(OBJ): $$(LOCAL_PATH)/$$(SRC)
	@mkdir -p $$(dir $$(PRIVATE_OBJ))
	@echo "Compile: $$(PRIVATE_MODULE) <= $$(PRIVATE_SRC0)"
	$(hide) $$(PRIVATE_CC) $$(PRIVATE_CFLAGS) -c -o $$(PRIVATE_OBJ) -MMD -MP -MF $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_SRC)
	$(hide) $$(_BUILD_CORE_DIR)/core/mkdeps.sh $$(PRIVATE_OBJ) $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_OBJ).d
endef

# Compile a C++ source file
#
define  compile-cxx-source
SRC:=$(1)
OBJ:=$$(LOCAL_OBJS_DIR)/$$(call local-cxx-src-to-obj,$$(SRC))
LOCAL_OBJECTS += $$(OBJ)
_BUILD_DEPENDENCY_DIRS += $$(dir $$(OBJ))
$$(OBJ): PRIVATE_CFLAGS := $$(LOCAL_CFLAGS) $$(LOCAL_CXXFLAGS) -I$$(LOCAL_PATH) -I$$(LOCAL_OBJS_DIR)
$$(OBJ): PRIVATE_CXX    := $$(LOCAL_CXX)
$$(OBJ): PRIVATE_OBJ    := $$(OBJ)
$$(OBJ): PRIVATE_MODULE := $$(LOCAL_MODULE)
$$(OBJ): PRIVATE_SRC    := $$(LOCAL_PATH)/$$(SRC)
$$(OBJ): PRIVATE_SRC0   := $$(SRC)
$$(OBJ): $$(LOCAL_PATH)/$$(SRC)
	@mkdir -p $$(dir $$(PRIVATE_OBJ))
	@echo "Compile: $$(PRIVATE_MODULE) <= $$(PRIVATE_SRC0)"
	$(hide) $$(PRIVATE_CXX) $$(PRIVATE_CFLAGS) -c -o $$(PRIVATE_OBJ) -MMD -MP -MF $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_SRC)
	$(hide) $$(_BUILD_CORE_DIR)/core/mkdeps.sh $$(PRIVATE_OBJ) $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_OBJ).d
endef

# Compile an Objective-C source file
#
define  compile-objc-source
SRC:=$(1)
OBJ:=$$(LOCAL_OBJS_DIR)/$$(notdir $$(SRC:%.m=%.o))
LOCAL_OBJECTS += $$(OBJ)
_BUILD_DEPENDENCY_DIRS += $$(dir $$(OBJ))
$$(OBJ): PRIVATE_CFLAGS := $$(LOCAL_CFLAGS) -I$$(LOCAL_PATH) -I$$(LOCAL_OBJS_DIR)
$$(OBJ): PRIVATE_CC     := $$(LOCAL_CC)
$$(OBJ): PRIVATE_OBJ    := $$(OBJ)
$$(OBJ): PRIVATE_MODULE := $$(LOCAL_MODULE)
$$(OBJ): PRIVATE_SRC    := $$(LOCAL_PATH)/$$(SRC)
$$(OBJ): PRIVATE_SRC0   := $$(SRC)
$$(OBJ): $$(LOCAL_PATH)/$$(SRC)
	@mkdir -p $$(dir $$(PRIVATE_OBJ))
	@echo "Compile: $$(PRIVATE_MODULE) <= $$(PRIVATE_SRC0)"
	$(hide) $$(PRIVATE_CC) $$(PRIVATE_CFLAGS) -c -o $$(PRIVATE_OBJ) -MMD -MP -MF $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_SRC)
	$(hide) $$(_BUILD_CORE_DIR)/core/mkdeps.sh $$(PRIVATE_OBJ) $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_OBJ).d
endef

# Compile an Objective-C source file
#
define  compile-objcxx-source
SRC:=$(1)
OBJ:=$$(LOCAL_OBJS_DIR)/$$(notdir $$(SRC:%.mm=%.o))
LOCAL_OBJECTS += $$(OBJ)
_BUILD_DEPENDENCY_DIRS += $$(dir $$(OBJ))
$$(OBJ): PRIVATE_CFLAGS := $$(LOCAL_CFLAGS) $$(LOCAL_CXXFLAGS) -I$$(LOCAL_PATH) -I$$(LOCAL_OBJS_DIR)
$$(OBJ): PRIVATE_CC     := $$(LOCAL_CXX)
$$(OBJ): PRIVATE_OBJ    := $$(OBJ)
$$(OBJ): PRIVATE_MODULE := $$(LOCAL_MODULE)
$$(OBJ): PRIVATE_SRC    := $$(LOCAL_PATH)/$$(SRC)
$$(OBJ): PRIVATE_SRC0   := $$(SRC)
$$(OBJ): $$(LOCAL_PATH)/$$(SRC)
	@mkdir -p $$(dir $$(PRIVATE_OBJ))
	@echo "Compile: $$(PRIVATE_MODULE) <= $$(PRIVATE_SRC0)"
	$(hide) $$(PRIVATE_CC) $$(PRIVATE_CFLAGS) -c -o $$(PRIVATE_OBJ) -MMD -MP -MF $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_SRC)
	$(hide) $$(_BUILD_CORE_DIR)/core/mkdeps.sh $$(PRIVATE_OBJ) $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_OBJ).d
endef

# Compile a generated C source files#
#
define compile-generated-c-source
SRC:=$(1)
OBJ:=$$(LOCAL_OBJS_DIR)/$$(SRC:%.c=%.o)
LOCAL_OBJECTS += $$(OBJ)
_BUILD_DEPENDENCY_DIRS += $$(dir $$(OBJ))
$$(OBJ): PRIVATE_CFLAGS := $$(LOCAL_CFLAGS) -I$$(LOCAL_PATH) -I$$(LOCAL_OBJS_DIR)
$$(OBJ): PRIVATE_CC     := $$(LOCAL_CC)
$$(OBJ): PRIVATE_OBJ    := $$(OBJ)
$$(OBJ): PRIVATE_MODULE := $$(LOCAL_MODULE)
$$(OBJ): PRIVATE_SRC    := $$(SRC)
$$(OBJ): PRIVATE_SRC0   := $$(SRC)
$$(OBJ): $$(SRC)
	@mkdir -p $$(dir $$(PRIVATE_OBJ))
	@echo "Compile: $$(PRIVATE_MODULE) <= $$(PRIVATE_SRC0)"
	$(hide) $$(PRIVATE_CC) $$(PRIVATE_CFLAGS) -c -o $$(PRIVATE_OBJ) -MMD -MP -MF $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_SRC)
	$(hide) $$(_BUILD_CORE_DIR)/core/mkdeps.sh $$(PRIVATE_OBJ) $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_OBJ).d
endef

define compile-generated-cxx-source
SRC:=$(1)
OBJ:=$$(LOCAL_OBJS_DIR)/$$(call local-cxx-src-to-obj,$$(notdir $$(SRC)))
LOCAL_OBJECTS += $$(OBJ)
_BUILD_DEPENDENCY_DIRS += $$(dir $$(OBJ))
$$(OBJ): PRIVATE_CFLAGS := $$(LOCAL_CFLAGS) $$(LOCAL_CXXFLAGS) -I$$(LOCAL_PATH) -I$$(LOCAL_OBJS_DIR)
$$(OBJ): PRIVATE_CXX    := $$(LOCAL_CXX)
$$(OBJ): PRIVATE_OBJ    := $$(OBJ)
$$(OBJ): PRIVATE_MODULE := $$(LOCAL_MODULE)
$$(OBJ): PRIVATE_SRC    := $$(SRC)
$$(OBJ): PRIVATE_SRC0   := $$(SRC)
$$(OBJ): $$(SRC)
	@mkdir -p $$(dir $$(PRIVATE_OBJ))
	@echo "Compile: $$(PRIVATE_MODULE) <= $$(PRIVATE_SRC0)"
	$(hide) $$(PRIVATE_CXX) $$(PRIVATE_CFLAGS) -c -o $$(PRIVATE_OBJ) -MMD -MP -MF $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_SRC)
	$(hide) $$(_BUILD_CORE_DIR)/core/mkdeps.sh $$(PRIVATE_OBJ) $$(PRIVATE_OBJ).d.tmp $$(PRIVATE_OBJ).d
endef

# Install a file
#
define install-target
SRC:=$(1)
DST:=$(2)
$$(DST): PRIVATE_SRC := $$(SRC)
$$(DST): PRIVATE_DST := $$(DST)
$$(DST): PRIVATE_DST_NAME := $$(notdir $$(DST))
$$(DST): PRIVATE_SRC_NAME := $$(SRC)
$$(DST): $$(SRC)
	@mkdir -p $$(dir $$(PRIVATE_DST))
	@echo "Install: $$(PRIVATE_DST_NAME) <= $$(PRIVATE_SRC_NAME)"
	$(hide) cp -f $$(PRIVATE_SRC) $$(PRIVATE_DST)
install: $$(DST)
endef

define  create-dir
$(1):
	mkdir -p $(1)
endef

define transform-generated-source
@echo "Generated: $(PRIVATE_MODULE) <= $<"
@mkdir -p $(dir $@)
$(hide) $(PRIVATE_CUSTOM_TOOL)
endef

# Installs a file to a new destination
define install-file
_SRC := $(1)
_DST := $(2)
LOCAL_ADDITIONAL_DEPENDENCIES += $$(_DST)
$$(_DST): PRIVATE_DST := $$(_DST)
$$(_DST): PRIVATE_SRC := $$(_SRC)
$$(_DST): $$(_SRC)
	@mkdir -p $$(dir $$(PRIVATE_DST))
	@echo "Install: $$(PRIVATE_DST)"
	$(hide) cp -f $$(PRIVATE_SRC) $$(PRIVATE_DST)
endef

# Installs a binary to a new destination
# If required, will strip the binary
define install-binary
_SRC := $(1)
_DST := $(2)
_BUILD_EXECUTABLES += $$(_DST)
$$(_DST): PRIVATE_DST := $$(_DST)
$$(_DST): PRIVATE_SRC := $$(_SRC)
$$(_DST): PRIVATE_OBJCOPY := $$(BUILD_TARGET_OBJCOPY)
$$(_DST): PRIVATE_OBJCOPY_FLAGS := $(3)
$$(_DST): $$(_SRC)
	@mkdir -p $$(dir $$(PRIVATE_DST))
	@echo "Install: $$(PRIVATE_DST)"
ifeq (true,$$(BUILD_STRIP_BINARIES))
ifeq (darwin,$$(BUILD_TARGET_OS))
	$(hide) strip -S -o $$(PRIVATE_DST) $$(PRIVATE_SRC)
else  # BUILD_TARGET_OS != darwin
	$(hide) $$(PRIVATE_OBJCOPY) $$(PRIVATE_OBJCOPY_FLAGS) $$(PRIVATE_SRC) $$(PRIVATE_DST)
endif  # BUILD_TARGET_OS != darwin
else  # BUILD_STRIP_BINARIES != true
	$(hide) cp -f $$(PRIVATE_SRC) $$(PRIVATE_DST)
endif # BUILD_STRIP_BINARIES != true
endef

# Installs a prebuilt library
# If required, will generates symbols and debug info
define install-prebuilt
_PAIR := $(subst :, ,$(1))
_SRC := $$(word 1, $$(_PAIR))
_DST := $$(word 2, $$(_PAIR))
$(call install-binary,$$(_SRC),$$(_DST),--strip-unneeded)
ifeq (true,$(BUILD_GENERATE_SYMBOLS))
$$(eval $$(call build-install-debug-info,$$(_SRC),$$(_DST)))
$$(eval $$(call build-install-symbol,$$(_SRC),$$(_DST)))
endif
endef

# Installs a prebuilt symlink
# If required, will generate symbols
define install-prebuilt-symlink
_PAIR := $(subst :, ,$(1))
_SRC := $$(word 1, $$(_PAIR))
_DST := $$(word 2, $$(_PAIR))
_BUILD_EXECUTABLES += $$(_DST)
$$(_DST): PRIVATE_DST := $$(_DST)
$$(_DST): PRIVATE_SRC := $$(_SRC)
$$(_DST): $$(_SRC)
	@echo "Installing symlink: $$(PRIVATE_DST)"
	$(hide) cp -fa $$(PRIVATE_SRC) $$(PRIVATE_DST)
ifeq (true,$(BUILD_GENERATE_SYMBOLS))
$$(eval $$(call build-install-symbol,$$(_SRC),$$(_DST)))

# also copy over debug-info link
ifeq (darwin,$(BUILD_TARGET_OS))
_DEBUG_INFO_SRC := $$(_SRC).dSYM
else
_DEBUG_INFO_SRC := $$(_SRC)
endif # BUILD_TARGET_OS=darwin
_DEBUG_INFO := $$(call local-debug-info-install-path,$$(_DST))
_BUILD_DEBUG_INFOS += $$(_DEBUG_INFO)
$$(_DEBUG_INFO): PRIVATE_DEBUG_INFO := $$(_DEBUG_INFO)
$$(_DEBUG_INFO): PRIVATE_DEBUG_INFO_SRC := $$(_DEBUG_INFO_SRC)
$$(_DEBUG_INFO): $$(_SRC)
	@echo "Installing symlink debug info: $$(PRIVATE_DEBUG_INFO)"
	$(hide) cp -fa $$(PRIVATE_DEBUG_INFO_SRC) $$(PRIVATE_DEBUG_INFO)

endif # BUILD_GENERATE_SYMBOLS
endef

# Builds and installs the debug-info for a binary to a debug destination
define build-install-debug-info
_INTERMEDIATE_MODULE := $(1)
_MODULE := $(2)
_DEBUG_INFO := $$(call local-debug-info-install-path,$$(_MODULE))
_BUILD_DEBUG_INFOS += $$(_DEBUG_INFO)
$$(_DEBUG_INFO): PRIVATE_DEBUG_INFO := $$(_DEBUG_INFO)
$$(_DEBUG_INFO): PRIVATE_INTERMEDIATE_MODULE := $$(_INTERMEDIATE_MODULE)
$$(_DEBUG_INFO): PRIVATE_OBJCOPY := $$(BUILD_TARGET_OBJCOPY)
$$(_DEBUG_INFO): $$(_INTERMEDIATE_MODULE)
	@echo "Build debug info: $$(PRIVATE_DEBUG_INFO)"
	@mkdir -p $$(dir $$(PRIVATE_DEBUG_INFO))
ifeq (darwin,$(BUILD_TARGET_OS))
ifeq (,$$(wildcard $$(_INTERMEDIATE_MODULE).dSYM))
	$(hide) dsymutil --out=$$(PRIVATE_DEBUG_INFO) $$(PRIVATE_INTERMEDIATE_MODULE)
else # dSYM exists
	$(hide) cp -rf $$(PRIVATE_INTERMEDIATE_MODULE).dSYM $$(PRIVATE_DEBUG_INFO)
endif
else # BUILD_TARGET_OS != darwin
	$(hide) cp -f $$(PRIVATE_INTERMEDIATE_MODULE) $$(PRIVATE_DEBUG_INFO)
endif # BUILD_TARGET_OS
endef

# Builds, then installs a symbol from a module target
define build-install-symbol
_INTERMEDIATE_MODULE := $(1)
_MODULE := $(2)
_SYMBOL := $$(call local-symbol-install-path,$$(_MODULE))
_SYMBOL_DEP := $$(_INTERMEDIATE_MODULE)
_BUILD_SYMBOLS += $$(_SYMBOL)

ifeq (darwin,$(BUILD_TARGET_OS))
_DSYM := $$(call local-debug-info-install-path,$$(_MODULE))
_SYMBOL_DEP += $$(_DSYM)
endif

$$(_SYMBOL): PRIVATE_DSYM := $$(_DSYM)
$$(_SYMBOL): PRIVATE_DUMPSYMS := $$(BUILD_TARGET_DUMPSYMS)
$$(_SYMBOL): PRIVATE_MODULE := $$(_INTERMEDIATE_MODULE)
ifeq (darwin,$(BUILD_TARGET_OS))
$$(_SYMBOL): PRIVATE_MODULE_DSYM := $$(_DSYM)
endif
$$(_SYMBOL): PRIVATE_SYMBOL := $$(_SYMBOL)
$$(_SYMBOL): $$(_SYMBOL_DEP)
	@echo "Build Symbol: $$(PRIVATE_SYMBOL)"
	@mkdir -p $$(dir $$(PRIVATE_SYMBOL))
ifeq (darwin,$(BUILD_TARGET_OS))
	$$(PRIVATE_DUMPSYMS) -g $$(PRIVATE_DSYM) $$(PRIVATE_MODULE) > $$(PRIVATE_SYMBOL)
else
	$(hide) $$(PRIVATE_DUMPSYMS) $$(PRIVATE_MODULE) > $$(PRIVATE_SYMBOL)
endif
endef


install-executable = $(eval $(call install-stripped-binary,$1,$2,--strip-all))
install-shared-library = $(eval $(call install-stripped-binary,$1,$2,--strip-unneeded))

# Generate DLL symbol file
#
# NOTE: The file is always named foo.def
#
define generate-symbol-file
SRC:=$(1)
OBJ:=$$(LOCAL_OBJS_DIR)/$$(notdir $$(SRC:%.entries=%.def))
LOCAL_GENERATED_SYMBOL_FILE:=$$(OBJ)
$$(OBJ): PRIVATE_SRC := $$(SRC)
$$(OBJ): PRIVATE_DST := $$(OBJ)
$$(OBJ): PRIVATE_MODE := $$(GEN_ENTRIES_MODE_$(BUILD_TARGET_OS))
$$(OBJ): $$(SRC)
	@mkdir -p $$(dir $$(PRIVATE_DST))
	@echo "Generate symbol file: $$(notdir $$(PRIVATE_DST))"
	$(hide) android/scripts/gen-entries.py --mode=$$(PRIVATE_MODE) --output=$$(PRIVATE_DST) $$(PRIVATE_SRC)
endef

GEN_ENTRIES_MODE_darwin := _symbols
GEN_ENTRIES_MODE_windows := def
GEN_ENTRIES_MODE_linux := sym

EXPORTED_SYMBOL_LIST_windows :=
EXPORTED_SYMBOL_LIST_darwin := -Wl,-exported_symbols_list,
EXPORTED_SYMBOL_LIST_linux := -Wl,--version-script=

symbol-file-linker-flags = $(EXPORTED_SYMBOL_LIST_$(BUILD_TARGET_OS))$1

# Generate and compile source file through the Qt 'moc' tool
# NOTE: This expects QT_MOC_TOOL to be defined.
define compile-qt-moc-source
SRC:=$(1)
MOC_SRC:=$$(LOCAL_OBJS_DIR)/moc_$$(notdir $$(SRC:%.h=%.cpp))
ifeq (,$$(strip $$(QT_MOC_TOOL)))
$$(error QT_MOC_TOOL is not defined when trying to generate $$(MOC_SRC) !!)
endif

# OS X is not happy with the relative include path if the intermediate
# build directory is under a symlink. So we're going to force moc to use the
# absolute path with the path prefix flag (-p).
$$(MOC_SRC): PRIVATE_SRC_DIR := $$(abspath $$(dir $$(LOCAL_PATH)/$$(SRC)))
$$(MOC_SRC): PRIVATE_SRC := $$(LOCAL_PATH)/$$(SRC)
$$(MOC_SRC): PRIVATE_DST := $$(MOC_SRC)
$$(MOC_SRC): $$(LOCAL_PATH)/$$(SRC) $$(MOC_TOOL)
	@mkdir -p $$(dir $$(PRIVATE_DST))
	@echo "Qt moc: $$(notdir $$(PRIVATE_DST)) <-- $$(PRIVATE_SRC)"
	$(hide) $$(call set-host-library-search-path,$$(QT_UIC_TOOL_LDPATH)) $$(QT_MOC_TOOL) -o $$(PRIVATE_DST) $$(PRIVATE_SRC) -p $$(PRIVATE_SRC_DIR)

$$(eval $$(call compile-generated-cxx-source,$$(MOC_SRC)))
endef

# Generate and compile a static Qt resource source file through the 'rcc' tool.
# NOTE: This expects QT_RCC_TOOL to be defined.
define compile-qt-resources
SRC := $(1)
RCC_SRC := $$(LOCAL_OBJS_DIR)/rcc_$$(notdir $$(SRC:%.qrc=%.cpp))
ifeq (,$$(strip $$(QT_RCC_TOOL)))
$$(error QT_RCC_TOOL is not defined when trying to generate $$(RCC_SRC) !!)
endif
$$(RCC_SRC): PRIVATE_SRC := $$(LOCAL_PATH)/$$(SRC)
$$(RCC_SRC): PRIVATE_DST := $$(RCC_SRC)
$$(RCC_SRC): PRIVATE_NAME := $$(notdir $$(SRC:%.qrc=%))
$$(RCC_SRC): $$(LOCAL_PATH)/$$(SRC) $$(QT_RCC_TOOL)
	@mkdir -p $$(dir $$(PRIVATE_DST))
	@echo "Qt rcc (static): $$(notdir $$(PRIVATE_DST)) <-- $$(PRIVATE_SRC)"
	$(hide) $$(call set-host-library-search-path,$$(QT_UIC_TOOL_LDPATH)) $$(QT_RCC_TOOL) -o $$(PRIVATE_DST) --name $$(PRIVATE_NAME) $$(PRIVATE_SRC)

$$(eval $$(call compile-generated-cxx-source,$$(RCC_SRC)))
endef

# Generate and install a separate Qt resource file through the 'rcc' tool.
# NOTE: This expects QT_RCC_TOOL to be defined.
define compile-qt-dynamic-resources
SRC := $(1)
RCC_OUT := $$(LOCAL_OBJS_DIR)/$$(notdir $$(SRC:%.qrc=%.rcc))
ifeq (,$$(strip $$(QT_RCC_TOOL)))
$$(error QT_RCC_TOOL is not defined when trying to generate $$(RCC_OUT) !!)
endif
$$(RCC_OUT): PRIVATE_SRC := $$(LOCAL_PATH)/$$(SRC)
$$(RCC_OUT): PRIVATE_DST := $$(RCC_OUT)
$$(RCC_OUT): PRIVATE_NAME := $$(notdir $$(SRC:%.qrc=%))
$$(RCC_OUT): $$(LOCAL_PATH)/$$(SRC) $$(QT_RCC_TOOL)
	@mkdir -p $$(dir $$(PRIVATE_DST))
	@echo "Qt rcc (dynamic): $$(notdir $$(PRIVATE_DST)) <-- $$(PRIVATE_SRC)"
	$(hide) $$(call set-host-library-search-path,$$(QT_UIC_TOOL_LDPATH)) $$(QT_RCC_TOOL) -binary -o $$(PRIVATE_DST) --name $$(PRIVATE_NAME) $$(PRIVATE_SRC)

$$(eval $$(call install-file,$$(RCC_OUT),$$(call local-resource-install-path,$$(notdir $$(RCC_OUT)))))
endef

# Process a Qt .ui source file through the 'uic' tool to generate a header.
# NOTE: This expects QT_UIC_TOOL and QT_UIC_TOOL_LDPATH to be defined.
define compile-qt-uic-source
SRC := $(1)
UIC_SRC := $$(LOCAL_OBJS_DIR)/ui_$$(notdir $$(SRC:%.ui=%.h))
ifeq (,$$(strip $$(QT_UIC_TOOL)))
$$(error QT_UIC_TOOL is not defined when trying to generate $$(UIC_SRC) !!)
endif
ifeq (,$$(strip $$(QT_UIC_TOOL_LDPATH)))
$$(error QT_UIC_TOOL_LDPATH is not defined when trying to generate $$(UIC_SRC) !!)
endif
$$(UIC_SRC): PRIVATE_SRC := $$(LOCAL_PATH)/$$(SRC)
$$(UIC_SRC): PRIVATE_DST := $$(UIC_SRC)
$$(UIC_SRC): $$(LOCAL_PATH)/$$(SRC) $$(QT_UIC_TOOL)
	@mkdir -p $$(dir $$(PRIVATE_DST))
	@echo "Qt uic: $$(notdir $$(PRIVATE_DST)) <-- $$(PRIVATE_SRC)"
	$(hide) $$(call set-host-library-search-path,$$(QT_UIC_TOOL_LDPATH)) $$(QT_UIC_TOOL) -o $$(PRIVATE_DST) $$(PRIVATE_SRC)

LOCAL_GENERATED_SOURCES += $$(UIC_SRC)
endef

# Generate and compile a .proto Protobuf source file through the 'protoc' tool.
# NOTE: This expects PROTOC_TOOL to be defined.
define compile-proto-source
SRC := $(1)
OUT_SRC := $$(generated-proto-sources-dir)/$$(SRC:%.proto=%.pb.cc)
ifeq (,$$(strip $$(PROTOC_TOOL)))
    $$(error PROTOC_TOOL is not defined when trying to generate $$(OUT_SRC) !!)
endif
$$(OUT_SRC): PRIVATE_SRC := $$(LOCAL_PATH)/$$(SRC)
$$(OUT_SRC): PRIVATE_DST_DIR := $$(dir $$(OUT_SRC))
$$(OUT_SRC): PRIVATE_DST := $$(OUT_SRC)
$$(OUT_SRC): PRIVATE_NAME := $$(notdir $$(SRC:%.proto=%))
$$(OUT_SRC): $$(LOCAL_PATH)/$$(SRC) $$(PROTOC_TOOL)
	@mkdir -p $$(dir $$(PRIVATE_DST))
	@echo "Protoc: $$(notdir $$(PRIVATE_DST)) <-- $$(PRIVATE_SRC)"
	$(hide) $$(PROTOC_TOOL) -I$$(dir $$(PRIVATE_SRC)) --cpp_out=$$(PRIVATE_DST_DIR) $$(PRIVATE_SRC)

$$(eval $$(call compile-generated-cxx-source,$$(OUT_SRC)))
endef


# Call this function to link statically against c++ on Windows.
# On linux it will set the rpath to look for lib64/lib from executable directory.
# On Mac it will merely link
local-link-static-c++lib = $(eval $(ev-local-link-static-c++lib))
define ev-local-link-static-c++lib
    ifeq (linux,$(BUILD_TARGET_OS))
        LOCAL_LDLIBS += $(CXX_STD_LIB)
        LOCAL_LDFLAGS += -Wl,-rpath=\$$$$ORIGIN/lib64:\$$$$ORIGIN/lib
    endif # BUILD_TARGET_OS = linux
    ifeq (darwin,$(BUILD_TARGET_OS))
        LOCAL_LDLIBS += $(CXX_STD_LIB)
    endif # BUILD_TARGET_OS = darwin
    ifeq (windows,$(BUILD_TARGET_OS))
        LOCAL_LDLIBS += -Wl,-Bstatic -lstdc++ -lwinpthread -Wl,-Bdynamic
    endif # BUILD_TARGET_OS = windows
    LOCAL_LD := $(call local-build-var,LD)
endef

ifneq (,$(BUILD_SYSTEM_UNIT_TESTS))
$(call -build-run-all-tests)
endif
