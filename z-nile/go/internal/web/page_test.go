package web_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"znile/internal/web"
)

// tree makes <root>/z-nile/app/<name> with the text, and returns its path.
func tree(t *testing.T, root, name, text string) string {
	t.Helper()
	dir := filepath.Join(root, "z-nile", "app")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func realTemp(t *testing.T) string {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return d
}

func TestPageRules(t *testing.T) {
	root := realTemp(t)
	good := tree(t, root, "index.html", "<p>ok</p>")
	other := filepath.Join(root, "z-nile", "app", "other.html")
	os.WriteFile(other, []byte("x"), 0o600)
	secret := filepath.Join(root, "secret.txt")
	os.WriteFile(secret, []byte("secret"), 0o600)
	link := filepath.Join(realTemp(t), "z-nile", "app", "index.html")
	os.MkdirAll(filepath.Dir(link), 0o700)
	os.Symlink(secret, link)
	big := tree(t, realTemp(t), "index.html", strings.Repeat("a", web.MaxPage+1))
	elsewhere := tree(t, realTemp(t), "index.html", "<p>elsewhere</p>")
	wt := tree(t, filepath.Join(root, ".worktree", "wt"), "index.html", "<p>wt</p>")
	deep := tree(t, filepath.Join(root, "a", "b"), "index.html", "<p>deep</p>")

	free := web.Pages{}
	rooted := web.Pages{Root: root}
	for _, c := range []struct {
		name  string
		pages web.Pages
		path  string
		ok    bool
	}{
		{"good", free, good, true},
		{"good in the root", rooted, good, true},
		{"a worktree of the root", rooted, wt, true},
		{"/etc/hosts", free, "/etc/hosts", false},
		{"relative path", free, "z-nile/app/index.html", false},
		{"unclean path", free, root + "/z-nile/../z-nile/app/index.html", false},
		{"empty", free, "", false},
		{"wrong file name", free, other, false},
		{"symlink out", free, link, false},
		{"oversized", free, big, false},
		{"outside the root", rooted, elsewhere, false},
		{"deep inside the root", rooted, deep, false},
		{"missing", free, filepath.Join(root, "nope", "z-nile", "app", "index.html"), false},
	} {
		_, err := c.pages.Resolve(c.path, "index.html")
		if (err == nil) != c.ok {
			t.Errorf("%s: err %v, want ok=%v", c.name, err, c.ok)
		}
		if err != nil && strings.Contains(err.Error(), root) {
			t.Errorf("%s: the reason names a path: %v", c.name, err)
		}
	}
}

// A file that is replaced by a symlink after it passed is refused at read time.
func TestReadRefusesASymlinkSwappedIn(t *testing.T) {
	root := realTemp(t)
	p := tree(t, root, "index.html", "<p>ok</p>")
	pages := web.Pages{}
	if b, err := pages.Read(p, "index.html"); err != nil || string(b) != "<p>ok</p>" {
		t.Fatalf("%q %v", b, err)
	}
	os.Remove(p)
	os.Symlink("/etc/hosts", p)
	if b, err := pages.Read(p, "index.html"); err == nil {
		t.Fatalf("read through a symlink: %q", b)
	}
}

func TestHandlerSwappedSymlinkAndFallback(t *testing.T) {
	root := realTemp(t)
	main := tree(t, root, "index.html", "<p>main</p>")
	wt := tree(t, filepath.Join(root, ".worktree", "wt"), "index.html", "<p>wt</p>")
	r := newRigPage(t, wt)
	r.h.Pages = web.Pages{Root: root}
	r.h.Fallback = main
	read := func() (int, string) {
		resp := r.get("/", r.host, "")
		return resp.StatusCode, readAll(resp)
	}
	if code, body := read(); code != 200 || body != "<p>wt</p>" {
		t.Fatalf("worktree page: %d %q", code, body)
	}
	// the worktree is deleted: the main checkout's page answers
	os.RemoveAll(filepath.Join(root, ".worktree"))
	if code, body := read(); code != 200 || body != "<p>main</p>" {
		t.Fatalf("fallback: %d %q", code, body)
	}
	// the page is swapped for a symlink to a file outside: nothing of it is sent, and no path is
	os.Remove(main)
	os.Symlink("/etc/hosts", main)
	code, body := read()
	if code != 404 || strings.Contains(body, "localhost") || strings.Contains(body, root) {
		t.Fatalf("swapped symlink: %d %q", code, body)
	}
}

func TestLiveJSIsServedBesideThePage(t *testing.T) {
	root := realTemp(t)
	p := tree(t, root, "index.html", "<p>page</p>")
	tree(t, root, "live.js", "var x = 1;")
	r := newRigPage(t, p)
	resp := r.get("/live.js", r.host, "")
	if resp.StatusCode != 200 || !strings.HasPrefix(resp.Header.Get("Content-Type"), "text/javascript") || readAll(resp) != "var x = 1;" {
		t.Fatalf("live.js: %d %q", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	os.Remove(filepath.Join(root, "z-nile", "app", "live.js"))
	if resp := r.get("/live.js", r.host, ""); resp.StatusCode != 404 {
		t.Fatalf("missing live.js: %d", resp.StatusCode)
	}
}
