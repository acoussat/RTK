# RTK Common Dashboard Script
#
# This script contains basic dashboard driver code common to all
# clients.
#
# Put this script in a directory such as "~/Dashboards/Scripts" or
# "c:/Dashboards/Scripts".  Create a file next to this script, say
# 'my_dashboard.cmake', with code of the following form:
#
#   # client maintainer: simon.rit@creatis.insa-lyon.fr
#   set(ctest_site "machine.site")
#   set(ctest_build_name "platform-compiler")
#   set(ctest_build_configuration debug)
#   set(ctest_cmake_generator "unix makefiles")
#   include(${ctest_script_directory}/rtk_common.cmake)
#
# Then run a scheduled task (cron job) with a command line such as
#
#   ctest -S ~/Dashboards/Scripts/my_dashboard.cmake -V
#
# By default the source and build trees will be placed in the path
# "../dashboard_tests/" relative to your script location.
#
# The following variables may be set before including this script
# to configure it:
#
#   dashboard_model           = Nightly | Experimental | Continuous
#   dashboard_loop            = Repeat until N seconds have elapsed
#   dashboard_root_name       = Change name of "dashboard_tests" directory
#   dashboard_source_name     = Name of source directory (RTK)
#   dashboard_binary_name     = Name of binary directory (RTK-build)
#   dashboard_data_name       = Name of ExternalData store (ExternalData)
#   dashboard_cache           = Initial CMakeCache.txt file content
#   dashboard_do_coverage     = True to enable coverage (ex: gcov)
#   dashboard_do_memcheck     = True to enable memcheck (ex: valgrind)
#   dashboard_no_clean        = True to skip build tree wipeout
#   CTEST_UPDATE_COMMAND      = path to svn command-line client
#   CTEST_BUILD_FLAGS         = build tool arguments (ex: -j2)
#   CTEST_DASHBOARD_ROOT      = Where to put source and build trees
#   CTEST_TEST_CTEST          = Whether to run long CTestTest* tests
#   CTEST_TEST_TIMEOUT        = Per-test timeout length
#   CTEST_TEST_ARGS           = ctest_test args (ex: PARALLEL_LEVEL 4)
#   CMAKE_MAKE_PROGRAM        = Path to "make" tool to use
#
# Options to configure builds from experimental git repository:
#   dashboard_git_url      = Custom git clone url
#   dashboard_git_branch   = Custom remote branch to track
#   dashboard_git_crlf     = Value of core.autocrlf for repository
#
# The following macros will be invoked before the corresponding
# step if they are defined:
#
#   dashboard_hook_init       = End of initialization, before loop
#   dashboard_hook_start      = Start of loop body, before ctest_start
#   dashboard_hook_build      = Before ctest_build
#   dashboard_hook_test       = Before ctest_test
#   dashboard_hook_coverage   = Before ctest_coverage
#   dashboard_hook_memcheck   = Before ctest_memcheck
#   dashboard_hook_submit     = Before ctest_submit
#   dashboard_hook_end        = End of loop body, after ctest_submit
#
# For Makefile generators the script may be executed from an
# environment already configured to use the desired compilers.
# Alternatively the environment may be set at the top of the script:
#
#   set(ENV{CC}  /path/to/cc)   # C compiler
#   set(ENV{CXX} /path/to/cxx)  # C++ compiler
#   set(ENV{FC}  /path/to/fc)   # Fortran compiler (optional)
#   set(ENV{LD_LIBRARY_PATH} /path/to/vendor/lib) # (if necessary)

cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

set(dashboard_user_home "$ENV{HOME}")

get_filename_component(dashboard_self_dir ${CMAKE_CURRENT_LIST_FILE} PATH)

# Select the top dashboard directory.
if(NOT DEFINED dashboard_root_name)
  set(dashboard_root_name "dashboard_tests")
endif()
if(NOT DEFINED CTEST_DASHBOARD_ROOT)
  get_filename_component(CTEST_DASHBOARD_ROOT "${CTEST_SCRIPT_DIRECTORY}/../${dashboard_root_name}" ABSOLUTE)
endif()

# Select the model (Nightly, Experimental, Continuous).
if(NOT DEFINED dashboard_model)
  set(dashboard_model Nightly)
endif()
if(NOT "${dashboard_model}" MATCHES "^(Nightly|Experimental|Continuous)$")
  message(FATAL_ERROR "dashboard_model must be Nightly, Experimental, or Continuous")
endif()

# Default to a Debug build.
if(NOT DEFINED CTEST_CONFIGURATION_TYPE AND DEFINED CTEST_BUILD_CONFIGURATION)
  set(CTEST_CONFIGURATION_TYPE ${CTEST_BUILD_CONFIGURATION})
endif()

if(NOT DEFINED CTEST_CONFIGURATION_TYPE)
  set(CTEST_CONFIGURATION_TYPE Debug)
endif()

# Choose CTest reporting mode.
if(NOT DEFINED CTEST_USE_LAUNCHERS)
  if(NOT "${CTEST_CMAKE_GENERATOR}" MATCHES "Make")
    # Launchers work only with Makefile generators.
    set(CTEST_USE_LAUNCHERS 0)
  elseif(NOT DEFINED CTEST_USE_LAUNCHERS)
    # The setting is ignored by CTest < 2.8 so we need no version test.
    set(CTEST_USE_LAUNCHERS 1)
  endif()
endif()

# Configure testing.
if(NOT DEFINED CTEST_TEST_CTEST)
  set(CTEST_TEST_CTEST 1)
endif()
if(NOT CTEST_TEST_TIMEOUT)
  set(CTEST_TEST_TIMEOUT 1500)
endif()


# Select Git source to use.
if(NOT DEFINED dashboard_git_url)
set(dashboard_git_url "git://github.com/SimonRit/RTK.git")
endif()
if(NOT DEFINED dashboard_git_branch)
  if("${dashboard_model}" STREQUAL "Nightly")
    set(dashboard_git_branch nightly-master)
  else()
    set(dashboard_git_branch master)
  endif()
endif()
if(NOT DEFINED dashboard_git_crlf)
  if(UNIX)
    set(dashboard_git_crlf false)
  else(UNIX)
    set(dashboard_git_crlf true)
  endif(UNIX)
endif()

# Look for a GIT command-line client.
if(NOT DEFINED CTEST_GIT_COMMAND)
  find_program(CTEST_GIT_COMMAND NAMES git git.cmd)
endif()

if(NOT DEFINED CTEST_GIT_COMMAND)
  message(FATAL_ERROR "No Git Found.")
endif()

# Select a source directory name.
if(NOT DEFINED CTEST_SOURCE_DIRECTORY)
  if(DEFINED dashboard_source_name)
    set(CTEST_SOURCE_DIRECTORY ${CTEST_DASHBOARD_ROOT}/${dashboard_source_name})
  else()
    set(CTEST_SOURCE_DIRECTORY ${CTEST_DASHBOARD_ROOT}/RTK)
  endif()
endif()

# Select a build directory name.
if(NOT DEFINED CTEST_BINARY_DIRECTORY)
  if(DEFINED dashboard_binary_name)
    set(CTEST_BINARY_DIRECTORY ${CTEST_DASHBOARD_ROOT}/${dashboard_binary_name})
  else()
    set(CTEST_BINARY_DIRECTORY ${CTEST_SOURCE_DIRECTORY}-build)
  endif()
endif()

# Select a data store.
if(NOT DEFINED ExternalData_OBJECT_STORES)
  if(DEFINED dashboard_data_name)
    set(ExternalData_OBJECT_STORES ${CTEST_DASHBOARD_ROOT}/${dashboard_data_name})
  else()
    set(ExternalData_OBJECT_STORES ${CTEST_DASHBOARD_ROOT}/ExternalData)
  endif()
endif()

# Support initial checkout if necessary.
if(NOT EXISTS "${CTEST_SOURCE_DIRECTORY}"
    AND NOT DEFINED CTEST_CHECKOUT_COMMAND)
  get_filename_component(_name "${CTEST_SOURCE_DIRECTORY}" NAME)
  execute_process(COMMAND ${CTEST_GIT_COMMAND} --version OUTPUT_VARIABLE output)
  string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+(\\.[0-9]+(\\.g[0-9a-f]+)?)?" GIT_VERSION "${output}")
  if(NOT "${GIT_VERSION}" VERSION_LESS "1.6.5")
    # Have "git clone -b <branch>" option.
    set(git_branch_new "-b ${dashboard_git_branch}")
    set(git_branch_old)
  else()
    # No "git clone -b <branch>" option.
    set(git_branch_new)
    set(git_branch_old "-b ${dashboard_git_branch} origin/${dashboard_git_branch}")
  endif()

    # Generate an initial checkout script.
    set(ctest_checkout_script ${CTEST_DASHBOARD_ROOT}/${_name}-init.cmake)
    file(WRITE ${ctest_checkout_script} "# git repo init script for ${_name}
execute_process(
  COMMAND \"${CTEST_GIT_COMMAND}\" clone -n ${git_branch_new} -- \"${dashboard_git_url}\"
          \"${CTEST_SOURCE_DIRECTORY}\"
  )
if(EXISTS \"${CTEST_SOURCE_DIRECTORY}/.git\")
  execute_process(
    COMMAND \"${CTEST_GIT_COMMAND}\" config core.autocrlf ${dashboard_git_crlf}
    WORKING_DIRECTORY \"${CTEST_SOURCE_DIRECTORY}\"
    )
  execute_process(
    COMMAND \"${CTEST_GIT_COMMAND}\" checkout ${git_branch_old}
    WORKING_DIRECTORY \"${CTEST_SOURCE_DIRECTORY}\"
    )
  execute_process(
    COMMAND \"${CTEST_GIT_COMMAND}\" submodule init
    WORKING_DIRECTORY \"${CTEST_SOURCE_DIRECTORY}\"
    )
  execute_process(
    COMMAND \"${CTEST_GIT_COMMAND}\" submodule update --
    WORKING_DIRECTORY \"${CTEST_SOURCE_DIRECTORY}\"
    )
endif()
")
  set(CTEST_CHECKOUT_COMMAND "\"${CMAKE_COMMAND}\" -P \"${ctest_checkout_script}\"")
endif()
  # CTest delayed initialization is broken, so we put the
  # CTestConfig.cmake info here.
  set(CTEST_NIGHTLY_START_TIME "21:00:00 UTC")
  set(CTEST_DROP_METHOD "http")
  set(CTEST_DROP_SITE "my.cdash.org")
  set(CTEST_DROP_LOCATION "/submit.php?project=RTK")
  set(CTEST_DROP_SITE_CDASH TRUE)

#-----------------------------------------------------------------------------

# Send the main script as a note.
list(APPEND CTEST_NOTES_FILES
  "${CTEST_SCRIPT_DIRECTORY}/${CTEST_SCRIPT_NAME}"
  "${CMAKE_CURRENT_LIST_FILE}"
  )

# Check for required variables.
foreach(req
    CTEST_CMAKE_GENERATOR
    CTEST_SITE
    CTEST_BUILD_NAME
    )
  if(NOT DEFINED ${req})
    message(FATAL_ERROR "The containing script must set ${req}")
  endif()
endforeach(req)

# Print summary information.
foreach(v
    CTEST_SITE
    CTEST_BUILD_NAME
    CTEST_SOURCE_DIRECTORY
    CTEST_BINARY_DIRECTORY
    ExternalData_OBJECT_STORES
    CTEST_CMAKE_GENERATOR
    CTEST_BUILD_CONFIGURATION
    CTEST_GIT_COMMAND
    CTEST_CHECKOUT_COMMAND
    CTEST_SCRIPT_DIRECTORY
    CTEST_USE_LAUNCHERS
    )
  set(vars "${vars}  ${v}=[${${v}}]\n")
endforeach(v)
message("Dashboard script configuration:\n${vars}\n")

# Git does not update submodules by default so they appear as local
# modifications in the work tree.  CTest 2.8.2 does this automatically.
# To support CTest 2.8.0 and 2.8.1 we wrap Git in a script.
if(${CMAKE_VERSION} VERSION_LESS 2.8.2)
  if(UNIX)
    configure_file(${dashboard_self_dir}/gitmod.sh.in
                   ${CTEST_DASHBOARD_ROOT}/gitmod.sh
                   @ONLY)
    set(CTEST_GIT_COMMAND ${CTEST_DASHBOARD_ROOT}/gitmod.sh)
  else()
    configure_file(${dashboard_self_dir}/gitmod.bat.in
                   ${CTEST_DASHBOARD_ROOT}/gitmod.bat
                   @ONLY)
    set(CTEST_GIT_COMMAND ${CTEST_DASHBOARD_ROOT}/gitmod.bat)
  endif()
endif()

# Avoid non-ascii characters in tool output.
set(ENV{LC_ALL} C)

# Helper macro to write the initial cache.
macro(write_cache)
  set(cache_build_type "")
  set(cache_make_program "")
  if(CTEST_CMAKE_GENERATOR MATCHES "Make")
    set(cache_build_type CMAKE_BUILD_TYPE:STRING=${CTEST_BUILD_CONFIGURATION})
    if(CMAKE_MAKE_PROGRAM)
      set(cache_make_program CMAKE_MAKE_PROGRAM:FILEPATH=${CMAKE_MAKE_PROGRAM})
    endif()
  endif()
  file(WRITE ${CTEST_BINARY_DIRECTORY}/CMakeCache.txt "
SITE:STRING=${CTEST_SITE}
BUILDNAME:STRING=${CTEST_BUILD_NAME}
CTEST_USE_LAUNCHERS:BOOL=${CTEST_USE_LAUNCHERS}
DART_TESTING_TIMEOUT:STRING=${CTEST_TEST_TIMEOUT}
ExternalData_OBJECT_STORES:STRING=${ExternalData_OBJECT_STORES}
${cache_build_type}
${cache_make_program}
${dashboard_cache}
")
endmacro(write_cache)

# Start with a fresh build tree.
file(MAKE_DIRECTORY "${CTEST_BINARY_DIRECTORY}")
if(NOT "${CTEST_SOURCE_DIRECTORY}" STREQUAL "${CTEST_BINARY_DIRECTORY}"
    AND NOT dashboard_no_clean)
  message("Clearing build tree...")
  ctest_empty_binary_directory(${CTEST_BINARY_DIRECTORY})
endif()

set(dashboard_continuous 0)
if("${dashboard_model}" STREQUAL "Continuous")
  set(dashboard_continuous 1)
endif()
if(NOT DEFINED dashboard_loop)
  if(dashboard_continuous)
    set(dashboard_loop 43200)
  else()
    set(dashboard_loop 0)
  endif()
endif()

# CTest 2.6 crashes with message() after ctest_test.
macro(safe_message)
  if(NOT "${CMAKE_VERSION}" VERSION_LESS 2.8 OR NOT safe_message_skip)
    message(${ARGN})
  endif()
endmacro()

if(COMMAND dashboard_hook_init)
  dashboard_hook_init()
endif()

set(dashboard_done 0)
while(NOT dashboard_done)
  if(dashboard_loop)
    set(START_TIME ${CTEST_ELAPSED_TIME})
  endif()
  set(ENV{HOME} "${dashboard_user_home}")

  # Start a new submission.
  if(COMMAND dashboard_hook_start)
    dashboard_hook_start()
  endif()
  ctest_start(${dashboard_model})

  # Always build if the tree is fresh.
  set(dashboard_fresh 0)
  if(NOT EXISTS "${CTEST_BINARY_DIRECTORY}/CMakeCache.txt")
    set(dashboard_fresh 1)
    safe_message("Starting fresh build...")
    write_cache()
  endif()

  # Look for updates.
  ctest_update(RETURN_VALUE count)
  set(CTEST_CHECKOUT_COMMAND) # checkout on first iteration only
  safe_message("Found ${count} changed files")

  if(dashboard_fresh OR NOT dashboard_continuous OR count GREATER 0)
    ctest_configure(
 BUILD        ${CTEST_BINARY_DIRECTORY}
 SOURCE       ${CTEST_SOURCE_DIRECTORY}
 OPTIONS      "${CONFIGURE_OPTIONS}"
 RETURN_VALUE config_result
     ) 
    ctest_read_custom_files(${CTEST_BINARY_DIRECTORY})

    if(COMMAND dashboard_hook_build)
      dashboard_hook_build()
    endif()
    ctest_build()

    if(COMMAND dashboard_hook_test)
      dashboard_hook_test()
    endif()
    ctest_test(${CTEST_TEST_ARGS})
    set(safe_message_skip 1) # Block furhter messages

    if(dashboard_do_coverage)
      if(COMMAND dashboard_hook_coverage)
        dashboard_hook_coverage()
      endif()
      ctest_coverage()
    endif()
    if(dashboard_do_memcheck)
      if(COMMAND dashboard_hook_memcheck)
        dashboard_hook_memcheck()
      endif()
      ctest_memcheck()
    endif()
    if(COMMAND dashboard_hook_submit)
      dashboard_hook_submit()
    endif()
    if(NOT dashboard_no_submit)
      ctest_submit()
    endif()
    if(COMMAND dashboard_hook_end)
      dashboard_hook_end()
    endif()
  endif()

  if(dashboard_loop)
    # Delay until at least 5 minutes past START_TIME
    ctest_sleep(${START_TIME} 300 ${CTEST_ELAPSED_TIME})
    if(${CTEST_ELAPSED_TIME} GREATER ${dashboard_loop})
      set(dashboard_done 1)
    endif()
  else()
    # Not continuous, so we are done.
    set(dashboard_done 1)
  endif()
endwhile()