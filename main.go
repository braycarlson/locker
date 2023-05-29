package main

import (
	"bytes"
	_ "embed"
	"unsafe"

	"github.com/JamesHovious/w32"
	"github.com/getlantern/systray"
	"golang.design/x/hotkey/mainthread"
)

const (
	Context w32.DWORD = 27
	Escape  w32.DWORD = 93
)

var (
	keyboard w32.HHOOK
	mouse    w32.HHOOK

	queue []byte

	// Ctrl + Alt + L
	LockHotkey = []byte{162, 164, 76}

	// Type "unlock"
	UnlockHotkey = []byte{85, 78, 76, 79, 67, 75}

	//go:embed asset/lock.ico
	lock []byte

	//go:embed asset/unlock.ico
	unlock []byte

	//go:embed rsrc_windows_amd64.syso
	resource []byte
)

func listener(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case
		w32.WPARAM(w32.WM_KEYDOWN),
		w32.WPARAM(w32.WM_SYSKEYDOWN):

		message := unsafe.Pointer(lparam)
		kbdstruct := (*w32.KBDLLHOOKSTRUCT)(message)

		var key byte = byte(kbdstruct.VkCode)

		if len(queue) == 3 {
			queue = queue[1:]
		}

		queue = append(queue, key)

		if bytes.Equal(queue, LockHotkey) {
			systray.SetIcon(lock)

			w32.UnhookWindowsHookEx(keyboard)

			queue = nil

			keyboard = w32.SetWindowsHookEx(
				w32.WH_KEYBOARD_LL,
				w32.HOOKPROC(blockKeyboard),
				0,
				0,
			)

			mouse = w32.SetWindowsHookEx(
				w32.WH_MOUSE_LL,
				w32.HOOKPROC(blockMouse),
				0,
				0,
			)
		}
	}

	return w32.CallNextHookEx(
		w32.HHOOK(keyboard),
		identifier,
		wparam,
		lparam,
	)
}

func blockMouse(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
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
		w32.HHOOK(mouse),
		identifier,
		wparam,
		lparam,
	)
}

func blockKeyboard(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case
		w32.WPARAM(w32.WM_KEYDOWN),
		w32.WPARAM(w32.WM_SYSKEYDOWN):

		return 1
	case
		w32.WPARAM(w32.WM_KEYUP),
		w32.WPARAM(w32.WM_SYSKEYUP):

		message := unsafe.Pointer(lparam)
		kbdstruct := (*w32.KBDLLHOOKSTRUCT)(message)

		// Disable the esc and context menu
		if kbdstruct.VkCode == Escape || kbdstruct.VkCode == Context {
			return 1
		}

		var key byte = byte(kbdstruct.VkCode)

		if len(queue) == 6 {
			queue = queue[1:]
		}

		queue = append(queue, key)

		if bytes.Equal(queue, UnlockHotkey) {
			systray.SetIcon(unlock)

			w32.UnhookWindowsHookEx(keyboard)
			w32.UnhookWindowsHookEx(mouse)

			queue = nil

			keyboard = w32.SetWindowsHookEx(
				w32.WH_KEYBOARD_LL,
				w32.HOOKPROC(listener),
				0,
				0,
			)

			return w32.CallNextHookEx(
				w32.HHOOK(keyboard),
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
		w32.HHOOK(keyboard),
		identifier,
		wparam,
		lparam,
	)
}

func onReady() {
	systray.SetIcon(unlock)
	systray.SetTitle("Peripheral Locker")
	systray.SetTooltip("Peripheral Locker")
	quit := systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	mainthread.Init(start)
}

func onExit() {
	w32.UnhookWindowsHookEx(keyboard)
	w32.UnhookWindowsHookEx(mouse)
}

func start() {
	queue = make([]byte, 0, 6)

	keyboard = w32.SetWindowsHookEx(
		w32.WH_KEYBOARD_LL,
		w32.HOOKPROC(listener),
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
	systray.Run(onReady, onExit)
}
