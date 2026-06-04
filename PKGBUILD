# Maintainer: Daniel Zilli
pkgname=sqmate
pkgver=1.2.1
pkgrel=1
pkgdesc="A lightweight command-line utility that simplifies management of portable MySQL and MariaDB installations for local development."
arch=('any')
url="https://github.com/dlzi/sqmate"
license=('MIT')
depends=('bash>=4.3' 'libxcrypt-compat')
optdepends=(
    'bash-completion: for command-line completion'
    'mysql: for MySQL database engine support'
    'mariadb: for MariaDB database engine support'
)
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP') # Replace with the release tarball sha256 before publishing.

package() {
    cd "$srcdir/$pkgname-$pkgver"

    local script_path="src/sqmate.sh"
    [[ -f "$script_path" ]] || script_path="sqmate.sh"

    local manpage_path="docs/man/sqmate.1"
    [[ -f "$manpage_path" ]] || manpage_path="sqmate.1"

    # Install main script
    install -Dm755 "$script_path" "$pkgdir/usr/bin/sqmate"

    # Install documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/sqmate/README.md"
    install -Dm644 CHANGELOG.md "$pkgdir/usr/share/doc/sqmate/CHANGELOG.md"
    [[ -f LICENSE ]] && install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    [[ -f "$manpage_path" ]] && install -Dm644 "$manpage_path" "$pkgdir/usr/share/man/man1/sqmate.1"
}
