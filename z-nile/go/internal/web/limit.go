package web

import (
	"net"
	"sync"
)

// limitListener accepts at most n connections at a time; the next waits in the kernel's backlog until one closes.
func limitListener(ln net.Listener, n int) net.Listener {
	return &limited{Listener: ln, sem: make(chan struct{}, n), done: make(chan struct{})}
}

type limited struct {
	net.Listener
	sem  chan struct{}
	done chan struct{}
	once sync.Once
}

// Accept waits for a free slot, then for a connection.
func (l *limited) Accept() (net.Conn, error) {
	select {
	case l.sem <- struct{}{}:
	case <-l.done:
		return nil, net.ErrClosed
	}
	c, err := l.Listener.Accept()
	if err != nil {
		<-l.sem
		return nil, err
	}
	return &slotConn{Conn: c, release: func() { <-l.sem }}, nil
}

// Close closes the listener and wakes an Accept that waits for a slot.
func (l *limited) Close() error {
	l.once.Do(func() { close(l.done) })
	return l.Listener.Close()
}

type slotConn struct {
	net.Conn
	once    sync.Once
	release func()
}

// Close closes the connection and frees its slot, once.
func (c *slotConn) Close() error {
	c.once.Do(c.release)
	return c.Conn.Close()
}
