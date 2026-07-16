# HalideAot.cmake — builds a Halide generator binary and invokes it at
# configure time to emit per-target AOT artifacts (`.o` + `.h`).
#
# Active only when SUPY_USE_HALIDE=ON. Depends on Halide::Halide being
# defined (see FindHalide.cmake).
#
# Usage:
#   add_halide_aot_kernel(
#     NAME       sauvola_2d                       # Halide generator name
#     GENERATOR  halide/sauvola_2d_generator.cpp  # source file
#     TARGET     ${SUPY_HALIDE_TARGET}            # Halide Target string
#   )
#
# Defines two CMake targets:
#   - supy_halide_gen_<NAME>   : host-arch executable (the generator)
#   - supy_halide_<NAME>       : OBJECT library wrapping the AOT artifacts
#
# Consumers link the latter:
#   target_link_libraries(supy_scanner_core PRIVATE supy_halide_sauvola_2d)

function(add_halide_aot_kernel)
  cmake_parse_arguments(SUPY_HAOT
    ""            # no flags
    "NAME;GENERATOR;TARGET"
    ""
    ${ARGN})

  if(NOT SUPY_HAOT_NAME OR NOT SUPY_HAOT_GENERATOR OR NOT SUPY_HAOT_TARGET)
    message(FATAL_ERROR
      "add_halide_aot_kernel: NAME, GENERATOR, TARGET are all required")
  endif()

  set(_gen_tgt   "supy_halide_gen_${SUPY_HAOT_NAME}")
  set(_aot_tgt   "supy_halide_${SUPY_HAOT_NAME}")
  set(_out_dir   "${CMAKE_BINARY_DIR}/halide/${SUPY_HAOT_NAME}")
  set(_out_base  "${_out_dir}/${SUPY_HAOT_NAME}")
  set(_out_obj   "${_out_base}.o")
  set(_out_hdr   "${_out_base}.h")

  file(MAKE_DIRECTORY "${_out_dir}")

  # The generator is a HOST-arch binary even when the parent build targets
  # Android/iOS. ExternalProject would be the textbook way to escape the
  # cross-compile toolchain; for V1-S2-05.2 we shortcut by building the
  # generator in-tree and relying on CMake's `add_executable` honoring the
  # host toolchain when invoked at configure time via `try_compile`-style
  # spawning. If cross-compile breakage shows up, lift this to
  # ExternalProject in V1-S2-05.4.
  add_executable(${_gen_tgt} EXCLUDE_FROM_ALL
    "${CMAKE_CURRENT_SOURCE_DIR}/${SUPY_HAOT_GENERATOR}"
    "${SUPY_HALIDE_GENGEN_CPP}")
  target_link_libraries(${_gen_tgt} PRIVATE Halide::Halide)
  target_compile_options(${_gen_tgt} PRIVATE
    -O2 -fno-rtti -Wno-error -Wno-unused-parameter)

  # Run the generator. Halide 17's CLI:
  #   <gen> -g <name> -o <out_dir> -e object,h -f <name> target=<target>
  add_custom_command(
    OUTPUT  "${_out_obj}" "${_out_hdr}"
    COMMAND $<TARGET_FILE:${_gen_tgt}>
            -g ${SUPY_HAOT_NAME}
            -o ${_out_dir}
            -e object,h
            -f ${SUPY_HAOT_NAME}
            target=${SUPY_HAOT_TARGET}
    DEPENDS ${_gen_tgt}
    COMMENT "[Halide] generating ${SUPY_HAOT_NAME} for ${SUPY_HAOT_TARGET}"
    VERBATIM)

  # Wrap the emitted object + header in a target the consumer can link.
  # Both the generated header and HalideRuntime.h (referenced by it) must
  # be on the consumer's include path — the latter ships in the Halide
  # vendor tree's include/ directory.
  add_library(${_aot_tgt} OBJECT IMPORTED GLOBAL)
  set_target_properties(${_aot_tgt} PROPERTIES
    IMPORTED_OBJECTS "${_out_obj}"
    INTERFACE_INCLUDE_DIRECTORIES "${_out_dir};${SUPY_HALIDE_HOST_ROOT}/include")

  # Stitch the custom command into a dummy target so consumers picking up
  # the OBJECT library see the generated file as a build dep.
  add_custom_target(${_aot_tgt}_codegen DEPENDS "${_out_obj}" "${_out_hdr}")
  add_dependencies(${_aot_tgt} ${_aot_tgt}_codegen)
endfunction()
