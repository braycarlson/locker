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

const (
	Context = 27
	Escape  = 93
)

var (
	mouseEvent = map[w32.WPARAM]bool{
		w32.WPARAM(w32.WM_LBUTTONDOWN): true,
		w32.WPARAM(w32.WM_MBUTTONDOWN): true,
		w32.WPARAM(w32.WM_RBUTTONDOWN): true,
		w32.WPARAM(w32.WM_XBUTTONDOWN): true,
		w32.WPARAM(w32.WM_LBUTTONUP):   true,
		w32.WPARAM(w32.WM_MBUTTONUP):   true,
		w32.WPARAM(w32.WM_RBUTTONUP):   true,
		w32.WPARAM(w32.WM_XBUTTONUP):   true,
		w32.WPARAM(w32.WM_MOUSEWHEEL):  true,
	}

	keyboardEvent = map[w32.WPARAM]bool{
		w32.WPARAM(w32.WM_KEYDOWN):    true,
		w32.WPARAM(w32.WM_SYSKEYDOWN): true,
	}

	keypressEvent = map[w32.DWORD]bool{
		Escape:  true,
		Context: true,
	}

	//go:embed asset/lock.ico
	lock []byte

	//go:embed asset/unlock.ico
	unlock []byte
)

type Locker struct {
	LockHotkey   []byte
	UnlockHotkey []byte
	keyboard     w32.HHOOK
	mouse        w32.HHOOK
	queue        *buffer.CircularBuffer
	lock         []byte
	unlock       []byte
	resource     []byte
	logger       chan string
	shutdown     chan bool
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

func (locker *Locker) listener(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	if wparam == w32.WPARAM(w32.WM_KEYDOWN) || wparam == w32.WPARAM(w32.WM_SYSKEYDOWN) {
		var message unsafe.Pointer = unsafe.Pointer(lparam)
		var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

		var key byte = byte(kbdstruct.VkCode)
		locker.queue.Push(key)

		if locker.queue.IsMatch(locker.LockHotkey) {
			locker.logger <- "Attempting to lock..."
			systray.SetIcon(locker.lock)
			locker.toggleHook(true)
		}
	}

	return w32.CallNextHookEx(
		0,
		identifier,
		wparam,
		lparam,
	)
}

func (locker *Locker) blockMouse(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	if mouseEvent[wparam] {
		return 1
	}

	return w32.CallNextHookEx(
		0,
		identifier,
		wparam,
		lparam,
	)
}

func (locker *Locker) blockKeyboard(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	if keyboardEvent[wparam] {
		return 1
	}

	if wparam == w32.WPARAM(w32.WM_KEYUP) || wparam == w32.WPARAM(w32.WM_SYSKEYUP) {
		var message unsafe.Pointer = unsafe.Pointer(lparam)
		var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

		// Disable the esc and context menu
		if keypressEvent[kbdstruct.VkCode] {
			return 1
		}

		var key byte = byte(kbdstruct.VkCode)
		locker.queue.Push(key)

		if locker.queue.IsMatch(locker.UnlockHotkey) {
			locker.logger <- "Attempting to unlock..."
			systray.SetIcon(locker.unlock)
			locker.toggleHook(false)

			return 0
		}
	}

	return w32.CallNextHookEx(
		0,
		identifier,
		wparam,
		lparam,
	)
}

func (locker *Locker) toggleHook(lock bool) {
	w32.UnhookWindowsHookEx(locker.keyboard)
	w32.UnhookWindowsHookEx(locker.mouse)

	if lock {
		locker.keyboard = w32.SetWindowsHookEx(
			w32.WH_KEYBOARD_LL,
			w32.HOOKPROC(locker.blockKeyboard),
			0,
			0,
		)

		locker.mouse = w32.SetWindowsHookEx(
			w32.WH_MOUSE_LL,
			w32.HOOKPROC(locker.blockMouse),
			0,
			0,
		)
	} else {
		locker.keyboard = w32.SetWindowsHookEx(
			w32.WH_KEYBOARD_LL,
			w32.HOOKPROC(locker.listener),
			0,
			0,
		)
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

	w32.UnhookWindowsHookEx(locker.keyboard)
	w32.UnhookWindowsHookEx(locker.mouse)

	locker.shutdown <- true
	close(locker.shutdown)
}

func (locker *Locker) run() {
	locker.keyboard = w32.SetWindowsHookEx(
		w32.WH_KEYBOARD_LL,
		w32.HOOKPROC(locker.listener),
		0,
		0,
	)

	locker.logger <- "Entering message loop..."

	var message w32.MSG

	for w32.GetMessage(&message, 0, 0, 0) != 0 {
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

	var locker *Locker = NewLocker()
	systray.Run(locker.onReady, locker.onExit)
}
