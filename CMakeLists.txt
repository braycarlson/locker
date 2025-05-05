cmake_minimum_required(VERSION 3.29)

# Project name
project(locker)

# Directories
set(SRC_DIR src)
set(INC_DIR include)
set(OBJ_DIR ${CMAKE_SOURCE_DIR}/obj)
set(BIN_DIR bin)

# Output targets
set(TARGET_EXE ${CMAKE_SOURCE_DIR}/${BIN_DIR}/locker.exe)
set(TARGET_DLL ${CMAKE_SOURCE_DIR}/${BIN_DIR}/hook.dll)

# Source files
file(GLOB SRC_FILES ${CMAKE_SOURCE_DIR}/${SRC_DIR}/*.c)
set(RC_SRC ${CMAKE_SOURCE_DIR}/${SRC_DIR}/resources.rc)

# Include directories
include_directories(${CMAKE_SOURCE_DIR}/${INC_DIR})

# Compiler flags
set(CMAKE_C_FLAGS "-DUNICODE -g")
set(CMAKE_EXE_LINKER_FLAGS "-mwindows")

# Output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/${BIN_DIR})
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/${BIN_DIR})

# Resource compilation
find_program(WINDRES_EXECUTABLE windres)

if(WINDRES_EXECUTABLE)
    add_custom_command(
        OUTPUT ${OBJ_DIR}/resources.o
        COMMAND ${CMAKE_COMMAND} -E make_directory ${OBJ_DIR}
        COMMAND ${WINDRES_EXECUTABLE} ${RC_SRC} -I${CMAKE_SOURCE_DIR}/${INC_DIR} -o ${OBJ_DIR}/resources.o
        DEPENDS ${RC_SRC}
    )
    set(RC_OBJ ${OBJ_DIR}/resources.o)
else()
    message(FATAL_ERROR "windres not found")
endif()

# Object files
set(OBJ_FILES)

foreach(SRC_FILE ${SRC_FILES})
    get_filename_component(FILENAME_WE ${SRC_FILE} NAME_WE)
    set(OBJ_FILE ${OBJ_DIR}/${FILENAME_WE}.o)

    add_custom_command(
        OUTPUT ${OBJ_FILE}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${OBJ_DIR}
        COMMAND ${CMAKE_C_COMPILER} ${CMAKE_C_FLAGS} -c ${SRC_FILE} -o ${OBJ_FILE}
        DEPENDS ${SRC_FILE}
    )
    list(APPEND OBJ_FILES ${OBJ_FILE})
endforeach()

add_custom_target(locker_exe ALL
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_SOURCE_DIR}/${BIN_DIR}
    COMMAND ${CMAKE_C_COMPILER} ${CMAKE_C_FLAGS} -o ${TARGET_EXE} ${OBJ_FILES} ${RC_OBJ} -Wl,-subsystem,windows
    DEPENDS ${OBJ_FILES} ${RC_OBJ}
)

add_custom_target(hook_dll ALL
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_SOURCE_DIR}/${BIN_DIR}
    COMMAND ${CMAKE_C_COMPILER} ${CMAKE_C_FLAGS} -shared -o ${TARGET_DLL} ${OBJ_FILES} ${RC_OBJ}
    DEPENDS ${OBJ_FILES} ${RC_OBJ}
)

add_custom_target(custom_clean
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${OBJ_DIR}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_SOURCE_DIR}/${BIN_DIR}
)
