package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"znile/internal/live"
	"znile/internal/web"
)

// appd is the daemon's optional HTTP face (f0437): nothing listens until `serve --http` or the app op asks, and the
// listener serves 127.0.0.1 only. Its address is written to <state>/http for as long as it serves.
type appd struct {
	ctx    context.Context
	core   *live.Core
	dir    string // the state directory's real path
	root   string // the repository of the default state folder; empty for a named (test) folder, where any z-nile/app page may be named
	stderr io.Writer

	mu   sync.Mutex
	h    *web.Handler
	addr string
	wg   sync.WaitGroup
}

// open returns the number of requests and event streams being answered.
func (a *appd) open() int {
	a.mu.Lock()
	h := a.h
	a.mu.Unlock()
	if h == nil {
		return 0
	}
	return h.Open()
}

// ensure starts serving when it does not yet and returns the address. A running app keeps its port; asking for another
// one is refused, and a new page path replaces the page it reads.
func (a *appd) ensure(port int, page string) (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	pages := web.Pages{Root: a.root}
	if page != "" {
		// the daemon decides what it serves, whoever asks and however the request was made; a refusal changes nothing
		if _, err := pages.Resolve(page, "index.html"); err != nil {
			return "", err
		}
	}
	if a.h != nil {
		if port != 0 && fmt.Sprint(port) != portOf(a.addr) {
			return "", fmt.Errorf("the app already serves on %s; stop the daemon to change its port", a.addr)
		}
		if page != "" {
			a.h.SetPage(page)
		}
		return a.addr, nil
	}
	// the port of the last app is asked for first, so a tab left open finds its daemon again; only a request for the app
	// reads it, never the start of a daemon
	var ln net.Listener
	var err error
	if port == 0 {
		if last, e := strconv.Atoi(strings.TrimSpace(readFile(filepath.Join(a.dir, "http.last")))); e == nil && last > 0 && last < 65536 {
			ln, err = web.Listen(last)
		}
	}
	if ln == nil {
		if ln, err = web.Listen(port); err != nil {
			return "", fmt.Errorf("cannot listen on 127.0.0.1 port %d: %v", port, err)
		}
	}
	addr := ln.Addr().String()
	if err := writeAtomic(a.dir, "http", addr); err != nil {
		ln.Close()
		return "", fmt.Errorf("cannot write the app address: %v", err)
	}
	writeAtomic(a.dir, "http.last", portOf(addr)) // best effort: only the next request for the app uses it
	h := &web.Handler{Core: a.core, PagePath: page, Addr: addr, Pages: pages}
	if a.root != "" {
		h.Fallback = filepath.Join(a.root, "z-nile", "app", "index.html")
	}
	a.h, a.addr = h, addr
	a.wg.Add(1)
	go func() { // owner: appd; ends when the daemon's context ends
		defer a.wg.Done()
		if err := h.Serve(a.ctx, ln); err != nil {
			fmt.Fprintf(a.stderr, "znlive serve: the app stopped: %v\n", err)
		}
	}()
	fmt.Fprintf(a.stderr, "znlive serve: the app is on http://%s/\n", addr)
	return addr, nil
}

// close waits for the listener to end (the daemon's context has ended) and removes the address file.
func (a *appd) close() {
	a.wg.Wait()
	os.Remove(filepath.Join(a.dir, "http"))
}

func readFile(p string) string {
	b, _ := os.ReadFile(p)
	return string(b)
}

func portOf(addr string) string {
	for i := len(addr) - 1; i >= 0; i-- {
		if addr[i] == ':' {
			return addr[i+1:]
		}
	}
	return ""
}
