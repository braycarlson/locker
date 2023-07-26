package main

import (
	"bytes"
	_ "embed"
	"log"
	"os"
	"path/filepath"
	"unsafe"

	"github.com/JamesHovious/w32"
	"github.com/getlantern/systray"
)

const (
	Context = 27
	Escape  = 93
)

var (
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
	queue        []byte
	lock         []byte
	unlock       []byte
	resource     []byte
}

func NewLocker() *Locker {
	return &Locker{
		LockHotkey:   []byte{162, 164, 76},
		UnlockHotkey: []byte{85, 78, 76, 79, 67, 75},
		lock:         lock,
		unlock:       unlock,
	}
}

func (locker *Locker) listener(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case
		w32.WPARAM(w32.WM_KEYDOWN),
		w32.WPARAM(w32.WM_SYSKEYDOWN):

		var message unsafe.Pointer = unsafe.Pointer(lparam)
		var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

		var key byte = byte(kbdstruct.VkCode)

		if len(locker.queue) == 3 {
			locker.queue = locker.queue[1:]
		}

		locker.queue = append(locker.queue, key)

		if bytes.Equal(locker.queue, locker.LockHotkey) {
			log.Println("Locking...")

			systray.SetIcon(locker.lock)

			w32.UnhookWindowsHookEx(locker.keyboard)

			locker.queue = nil

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
		}
	}

	return w32.CallNextHookEx(
		w32.HHOOK(locker.keyboard),
		identifier,
		wparam,
		lparam,
	)
}

func (locker *Locker) blockMouse(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case
		w32.WPARAM(w32.WM_LBUTTONDOWN),
		w32.WPARAM(w32.WM_MBUTTONDOWN),
		w32.WPARAM(w32.WM_RBUTTONDOWN),
		w32.WPARAM(w32.WM_XBUTTONDOWN):

		return 1
	case
		w32.WPARAM(w32.WM_LBUTTONUP),
		w32.WPARAM(w32.WM_MBUTTONUP),
		w32.WPARAM(w32.WM_RBUTTONUP),
		w32.WPARAM(w32.WM_XBUTTONUP):

		return 1
	}

	return w32.CallNextHookEx(
		w32.HHOOK(locker.mouse),
		identifier,
		wparam,
		lparam,
	)
}

func (locker *Locker) blockKeyboard(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case
		w32.WPARAM(w32.WM_KEYDOWN),
		w32.WPARAM(w32.WM_SYSKEYDOWN):

		return 1
	case
		w32.WPARAM(w32.WM_KEYUP),
		w32.WPARAM(w32.WM_SYSKEYUP):

		var message unsafe.Pointer = unsafe.Pointer(lparam)
		var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

		// Disable the esc and context menu
		if kbdstruct.VkCode == Escape || kbdstruct.VkCode == Context {
			return 1
		}

		var key byte = byte(kbdstruct.VkCode)

		if len(locker.queue) == 6 {
			locker.queue = locker.queue[1:]
		}

		locker.queue = append(locker.queue, key)

		if bytes.Equal(locker.queue, locker.UnlockHotkey) {
			log.Println("Unlocking...")

			systray.SetIcon(locker.unlock)

			w32.UnhookWindowsHookEx(locker.keyboard)
			w32.UnhookWindowsHookEx(locker.mouse)

			locker.queue = nil

			locker.keyboard = w32.SetWindowsHookEx(
				w32.WH_KEYBOARD_LL,
				w32.HOOKPROC(locker.listener),
				0,
				0,
			)

			return w32.CallNextHookEx(
				w32.HHOOK(locker.keyboard),
				identifier,
				wparam,
				lparam,
			)
		}

		return w32.CallNextHookEx(
			w32.WM_NULL,
			identifier,
			wparam,
			lparam,
		)
	}

	return w32.CallNextHookEx(
		w32.HHOOK(locker.keyboard),
		identifier,
		wparam,
		lparam,
	)
}

func (locker *Locker) onReady() {
	log.Println("Starting...")

	systray.SetIcon(locker.unlock)
	systray.SetTitle("Peripheral Locker")
	systray.SetTooltip("Peripheral Locker")
	quit := systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	locker.run()
}

func (locker *Locker) onExit() {
	log.Println("Exiting...")

	w32.UnhookWindowsHookEx(locker.keyboard)
	w32.UnhookWindowsHookEx(locker.mouse)
}

func (locker *Locker) run() {
	locker.queue = make([]byte, 0, 6)

	locker.keyboard = w32.SetWindowsHookEx(
		w32.WH_KEYBOARD_LL,
		w32.HOOKPROC(locker.listener),
		0,
		0,
	)

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

	file, err := os.OpenFile(
		path,
		os.O_CREATE|os.O_WRONLY|os.O_APPEND,
		0666,
	)

	if err != nil {
		log.Println(err)
	}

	log.SetOutput(file)

	var locker *Locker = NewLocker()
	systray.Run(locker.onReady, locker.onExit)
}
