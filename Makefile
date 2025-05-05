CC = gcc
RC = windres

SRC_DIR = src
INC_DIR = include
OBJ_DIR = obj
BIN_DIR = bin
RES_DIR = res

TARGET_EXE = $(BIN_DIR)/locker.exe
TARGET_DLL = $(BIN_DIR)/hook.dll

SRC = $(wildcard $(SRC_DIR)/*.c)
RC_SRC = $(SRC_DIR)/resources.rc

OBJ = $(patsubst $(SRC_DIR)/%.c, $(OBJ_DIR)/%.o, $(SRC))
RC_OBJ = $(OBJ_DIR)/resources.o

CFLAGS = -Wall -Wextra -Wpedantic -Werror -I$(INC_DIR) -DUNICODE -g -mwindows

all: $(TARGET_EXE) $(TARGET_DLL)

$(TARGET_EXE): $(OBJ) $(RC_OBJ)
	@if not exist $(BIN_DIR) mkdir $(BIN_DIR)
	$(CC) $(CFLAGS) -o $(TARGET_EXE) $(OBJ) $(RC_OBJ)

$(TARGET_DLL): $(OBJ) $(RC_OBJ)
	@if not exist $(BIN_DIR) mkdir $(BIN_DIR)
	$(CC) $(CFLAGS) -shared -o $(TARGET_DLL) $(OBJ) $(RC_OBJ)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	@if not exist $(OBJ_DIR) mkdir $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(RC_OBJ): $(RC_SRC)
	@if not exist $(OBJ_DIR) mkdir $(OBJ_DIR)
	windres $(RC_SRC) -I$(INC_DIR) -o $(RC_OBJ)

clean:
	if exist $(OBJ_DIR) rmdir /S /Q $(OBJ_DIR)
	if exist $(BIN_DIR) del /Q $(BIN_DIR)\*
