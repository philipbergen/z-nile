// Package store keeps the live layer's event log and snapshot in one state directory.
package store

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"

	"znile/internal/live"
)

// Store appends events to events.jsonl and writes snapshot.json.
type Store struct {
	dir  string
	path string // events.jsonl, named in every write error
	mu   sync.Mutex
	f    *os.File
	size int64
	// Repaired is 1 when a torn last line was cut off at Open; Skipped counts other lines that did not parse.
	Repaired int
	Skipped  int
}

// Open reads the snapshot (nil when there is none or it does not parse) and every event of the log, repairs a torn
// last line by truncating to the last newline, and opens the log for appending.
func Open(dir string) (*Store, *live.Snapshot, []live.Event, error) {
	path := filepath.Join(dir, "events.jsonl")
	s := &Store{dir: dir, path: path}
	events, good, err := s.read(path)
	if err != nil {
		return nil, nil, nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, nil, nil, err
	}
	st, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, nil, nil, err
	}
	if st.Size() != good {
		if err := f.Truncate(good); err != nil {
			f.Close()
			return nil, nil, nil, fmt.Errorf("repair %s: %w", path, err)
		}
	}
	if _, err := f.Seek(good, io.SeekStart); err != nil {
		f.Close()
		return nil, nil, nil, err
	}
	s.f, s.size = f, good
	var snap *live.Snapshot
	if b, err := os.ReadFile(filepath.Join(dir, "snapshot.json")); err == nil {
		var v live.Snapshot
		if json.Unmarshal(b, &v) == nil {
			snap = &v
		}
	}
	return s, snap, events, nil
}

// read parses the log. good is the offset after the last whole line; an unterminated tail is never acknowledged (the
// reply follows the whole write), so it is not counted in good, and dropping it is the one repair.
func (s *Store) read(path string) (events []live.Event, good int64, err error) {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, 0, nil
	} else if err != nil {
		return nil, 0, err
	}
	defer f.Close()
	r := bufio.NewReaderSize(f, 1<<16)
	var last int64
	for {
		line, rerr := r.ReadBytes('\n')
		if rerr != nil && rerr != io.EOF {
			return nil, 0, rerr
		}
		whole := len(line) > 0 && line[len(line)-1] == '\n'
		if len(line) > 0 {
			var e live.Event
			switch {
			case whole && json.Unmarshal(line, &e) == nil && e.Seq > last && e.Kind != "":
				events, last = append(events, e), e.Seq
				good += int64(len(line))
			case whole:
				s.Skipped++
				good += int64(len(line))
			default:
				s.Repaired = 1 // the torn tail: dropped
			}
		}
		if rerr == io.EOF {
			return events, good, nil
		}
	}
}

// Append writes one event as one whole line in one write(2), with no fsync. A failed write is cut back.
func (s *Store) Append(e live.Event) error {
	b, err := json.Marshal(e)
	if err != nil {
		return err
	}
	b = append(b, '\n')
	s.mu.Lock()
	defer s.mu.Unlock()
	n, err := s.f.Write(b)
	if err != nil {
		err = fmt.Errorf("cannot write %s: %w", s.path, err)
		if n > 0 {
			if terr := s.f.Truncate(s.size); terr != nil {
				return errors.Join(err, terr)
			}
			if _, serr := s.f.Seek(s.size, io.SeekStart); serr != nil {
				return errors.Join(err, serr)
			}
		}
		return err
	}
	s.size += int64(n)
	return nil
}

// WriteSnapshot writes snapshot.json through a renamed temporary file, fsynced.
func (s *Store) WriteSnapshot(snap live.Snapshot) error {
	b, err := json.Marshal(snap)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(s.dir, ".snapshot-*")
	if err != nil {
		return err
	}
	_, werr := tmp.Write(b)
	serr := tmp.Sync()
	cerr := tmp.Close()
	if err := errors.Join(werr, serr, cerr); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	if err := os.Rename(tmp.Name(), filepath.Join(s.dir, "snapshot.json")); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return nil
}

// Close fsyncs and closes the log.
func (s *Store) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return errors.Join(s.f.Sync(), s.f.Close())
}
