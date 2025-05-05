package main

import (
	_ "embed"
	"log"
	"os"
	"path/filepath"
	"unsafe"

	"github.com/JamesHovious/w32"
	"github.com/braycarlson/locker/buffer"
	"github.com/getlantern/systray"
)

/*
#cgo LDFLAGS: -Ldll -lhook
#include "dll/hook.h"
*/
import "C"

const (
	Context = 93
	Escape  = 27
	Space   = 32
)

var (
	mouseEvent = map[C.WPARAM]bool{
		C.WPARAM(w32.WM_LBUTTONDOWN): true,
		C.WPARAM(w32.WM_MBUTTONDOWN): true,
		C.WPARAM(w32.WM_RBUTTONDOWN): true,
		C.WPARAM(w32.WM_XBUTTONDOWN): true,
		C.WPARAM(w32.WM_LBUTTONUP):   true,
		C.WPARAM(w32.WM_MBUTTONUP):   true,
		C.WPARAM(w32.WM_RBUTTONUP):   true,
		C.WPARAM(w32.WM_XBUTTONUP):   true,
		C.WPARAM(w32.WM_MOUSEWHEEL):  true,
	}

	keyboardEvent = map[C.WPARAM]bool{
		C.WPARAM(w32.WM_KEYDOWN):    true,
		C.WPARAM(w32.WM_SYSKEYDOWN): true,
	}

	keypressEvent = map[w32.DWORD]bool{
		Escape:  true,
		Context: true,
		Space:   true,
	}

	//go:embed asset/lock.ico
	lock []byte

	//go:embed asset/unlock.ico
	unlock []byte
)

type Locker struct {
	LockHotkey   []byte
	UnlockHotkey []byte
	queue        *buffer.CircularBuffer
	lock         []byte
	unlock       []byte
	logger       chan string
	shutdown     chan bool
	isLocked     bool
}

func NewLocker() *Locker {
	return &Locker{
		LockHotkey:   []byte{162, 164, 76},
		UnlockHotkey: []byte{85, 78, 76, 79, 67, 75},
		lock:         lock,
		unlock:       unlock,
		queue:        buffer.NewCircularBuffer(7),
		logger:       make(chan string, 1000),
		shutdown:     make(chan bool),
	}
}

var locker *Locker

//export GoKeyboardProc
func GoKeyboardProc(nCode C.int, wParam C.WPARAM, lParam C.LPARAM) C.LRESULT {
	if nCode >= 0 {
		if wParam == C.WPARAM(w32.WM_KEYDOWN) || wParam == C.WPARAM(w32.WM_SYSKEYDOWN) {
			var message unsafe.Pointer = unsafe.Pointer(uintptr(lParam))
			var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

			var key byte = byte(kbdstruct.VkCode)
			locker.queue.Push(key)

			if locker.queue.IsMatch(locker.LockHotkey) {
				locker.logger <- "Attempting to lock..."
				systray.SetIcon(locker.lock)
				locker.toggleHook(true)
				return 1
			}

			if locker.queue.IsMatch(locker.UnlockHotkey) {
				locker.logger <- "Attempting to unlock..."
				systray.SetIcon(locker.unlock)
				locker.toggleHook(false)
				return 1
			}
		}

		if locker.isLocked {
			var message unsafe.Pointer = unsafe.Pointer(uintptr(lParam))
			var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

			if keypressEvent[kbdstruct.VkCode] || keyboardEvent[wParam] {
				return 1
			}
		}
	}

	return C.callNextHookEx(nCode, wParam, lParam)
}

//export GoMouseProc
func GoMouseProc(nCode C.int, wParam C.WPARAM, lParam C.LPARAM) C.LRESULT {
	if nCode >= 0 && locker.isLocked && mouseEvent[wParam] {
		return 1
	}

	return C.callNextHookEx(nCode, wParam, lParam)
}

func (locker *Locker) toggleHook(lock bool) {
	if lock {
		locker.logger <- "Locking input"
		locker.isLocked = true
		C.setGoKeyboardProc(C.HOOKPROC(C.GoKeyboardProc))
		C.setGoMouseProc(C.HOOKPROC(C.GoMouseProc))
		C.setKeyboardHook(C.getModuleHandle())
		C.setMouseHook(C.getModuleHandle())
	} else {
		locker.logger <- "Unlocking input"
		locker.isLocked = false
		C.removeHook()
		C.setGoKeyboardProc(C.HOOKPROC(C.GoKeyboardProc))
		C.setKeyboardHook(C.getModuleHandle())
	}
}

func (locker *Locker) logging() {
	for {
		select {
		case message, ok := <-locker.logger:
			if !ok {
				return
			}
			log.Println(message)
		case <-locker.shutdown:
			close(locker.logger)
			return
		}
	}
}

func (locker *Locker) onReady() {
	go locker.logging()

	locker.logger <- "Starting..."

	systray.SetIcon(locker.unlock)
	systray.SetTitle("Peripheral Locker")
	systray.SetTooltip("Peripheral Locker")

	var quit *systray.MenuItem
	quit = systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	locker.run()
}

func (locker *Locker) onExit() {
	locker.logger <- "Exiting..."

	C.removeHook()

	locker.shutdown <- true
	close(locker.shutdown)
}

func (locker *Locker) run() {
	C.setGoKeyboardProc(C.HOOKPROC(C.GoKeyboardProc))
	C.setGoMouseProc(C.HOOKPROC(C.GoMouseProc))
	C.setKeyboardHook(C.getModuleHandle())

	locker.logger <- "Entering message loop..."

	var message w32.MSG

	for {
		var status int
		status = w32.GetMessage(&message, 0, 0, 0)

		if status == 0 || status == -1 {
			break
		}

		w32.TranslateMessage(&message)
		w32.DispatchMessage(&message)
	}
}

func main() {
	var err error

	var configuration, _ = os.UserConfigDir()
	var home = filepath.Join(configuration, "locker")
	var path = filepath.Join(home, "locker.log")

	if err = os.MkdirAll(home, os.ModeDir); err != nil {
		log.Fatalln(err)
	}

	var file *os.File

	file, err = os.OpenFile(
		path,
		os.O_CREATE|os.O_WRONLY|os.O_APPEND,
		0666,
	)

	if err != nil {
		log.Println(err)
	}

	log.SetOutput(file)

	defer file.Close()

	locker = NewLocker()
	systray.Run(locker.onReady, locker.onExit)
}
