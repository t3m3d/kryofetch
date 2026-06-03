# Maintainer: Brian <brian@krypton-lang.org>
pkgname=kryofetch
pkgver=0.1.0
pkgrel=1
pkgdesc="Pure-Krypton system-info CLI (a neofetch-class, no-deps fastfetch alternative)"
arch=('x86_64' 'aarch64')
url="https://github.com/t3m3d/kryofetch"
license=('MIT')
depends=()                          # static syscall-only ELF — no runtime deps
makedepends=('git')                 # plus krypton (see below)
source=("git+$url.git#branch=main")
sha256sums=('SKIP')

# Krypton isn't (yet) packaged for Arch. Find kcc.sh via, in order:
#   $KRYPTON_ROOT/kcc.sh   ->   PATH/kcc.sh   ->   /opt/krypton/kcc.sh
_find_kcc() {
    if [[ -n "${KRYPTON_ROOT:-}" && -x "$KRYPTON_ROOT/kcc.sh" ]]; then
        echo "$KRYPTON_ROOT/kcc.sh"; return
    fi
    if command -v kcc.sh >/dev/null 2>&1; then
        command -v kcc.sh; return
    fi
    if [[ -x /opt/krypton/kcc.sh ]]; then
        echo /opt/krypton/kcc.sh; return
    fi
    echo "PKGBUILD: cannot find kcc.sh — set KRYPTON_ROOT to your krypton checkout" >&2
    return 1
}

build() {
    cd "$srcdir/$pkgname"
    local kcc; kcc=$(_find_kcc) || return 1
    msg2 "compiling via $kcc"
    "$kcc" -o "$srcdir/kryofetch" run_linux.k
}

package() {
    install -Dm755 "$srcdir/kryofetch" "$pkgdir/usr/bin/kryofetch"
    install -Dm644 "$srcdir/$pkgname/LICENSE" \
        "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    install -Dm644 "$srcdir/$pkgname/README.md" \
        "$pkgdir/usr/share/doc/$pkgname/README.md"
}
