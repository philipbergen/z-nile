package web

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// MaxPage is the largest app file (page or script) the daemon reads.
const MaxPage = 4 << 20

// ErrPage is a refused app file. Its text names the rule that was broken and never a path, because it is sent to clients.
type ErrPage struct{ Why string }

func (e *ErrPage) Error() string { return e.Why }

func refusePage(why string) error { return &ErrPage{Why: why} }

// IsPage reports whether err is a refused app file.
func IsPage(err error) bool {
	var p *ErrPage
	return errors.As(err, &p)
}

// Pages is the rule for what the daemon reads and serves as the app. A client names a path, so the daemon decides: the
// path is absolute and clean; after symlinks are resolved it is a regular file of the wanted name, directly in a folder
// z-nile/app, no larger than MaxPage; and with a Root (the default state folder's repository) it lies in that checkout
// or in one of its worktrees, <Root>/.worktree/<name>/.
type Pages struct{ Root string }

// Resolve checks the file called name (index.html, live.js) at path and returns its real path.
func (p Pages) Resolve(path, name string) (string, error) {
	if path == "" || !filepath.IsAbs(path) || filepath.Clean(path) != path {
		return "", refusePage("the page path must be absolute and clean")
	}
	real, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", refusePage("the page cannot be found")
	}
	app := filepath.Dir(real)
	if filepath.Base(real) != name || filepath.Base(app) != "app" || filepath.Base(filepath.Dir(app)) != "z-nile" {
		return "", refusePage("the page must be a file " + name + " directly in a folder z-nile/app")
	}
	st, err := os.Stat(real)
	if err != nil || !st.Mode().IsRegular() {
		return "", refusePage("the page must be a regular file")
	}
	if st.Size() > MaxPage {
		return "", refusePage("the page is over the size limit")
	}
	if p.Root != "" {
		root, err := filepath.EvalSymlinks(p.Root)
		if err != nil {
			return "", refusePage("the repository cannot be found")
		}
		rel, err := filepath.Rel(root, real)
		parts := strings.Split(rel, string(filepath.Separator))
		own := len(parts) == 3 && parts[0] == "z-nile"
		wt := len(parts) == 5 && parts[0] == ".worktree" && parts[2] == "z-nile"
		if err != nil || !(own || wt) {
			return "", refusePage("the page lies outside the repository's checkouts")
		}
	}
	return real, nil
}

// Read resolves the file and reads it, never following a symlink swapped in since, and never more than MaxPage.
func (p Pages) Read(path, name string) ([]byte, error) {
	real, err := p.Resolve(path, name)
	if err != nil {
		return nil, err
	}
	f, err := os.OpenFile(real, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, refusePage("the page cannot be read")
	}
	defer f.Close()
	if st, err := f.Stat(); err != nil || !st.Mode().IsRegular() {
		return nil, refusePage("the page must be a regular file")
	}
	b, err := io.ReadAll(io.LimitReader(f, MaxPage+1))
	if err != nil {
		return nil, refusePage("the page cannot be read")
	}
	if len(b) > MaxPage {
		return nil, refusePage("the page is over the size limit")
	}
	return b, nil
}
