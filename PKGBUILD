# Maintainer: Daniel Zilli
pkgname=sqmate
pkgver=1.0.0
pkgrel=1
pkgdesc="A lightweight command-line utility that simplifies management of portable MySQL and MariaDB installations for local development."
arch=('any')
url="https://github.com/dlzi/sqmate"
license=('MIT')
depends=('bash>=4.4')
optdepends=(
    'bash-completion: for command-line completion'
    'mysql: for MySQL database engine support'
    'mariadb: for MariaDB database engine support'
)
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP') # Replace 'SKIP' with the actual sha256 checksum

package() {
    cd "$srcdir/$pkgname-$pkgver"

    # Install main script
    install -Dm755 src/sqmate.sh "$pkgdir/usr/bin/sqmate"

    # Install documentation
    install -d "$pkgdir/usr/share/doc/sqmate"
    install -Dm644 README.md "$pkgdir/usr/share/doc/sqmate/"
    install -Dm644 CHANGELOG.md "$pkgdir/usr/share/doc/sqmate/"

    # Install license
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"

    # Install man page
    install -Dm644 docs/man/sqmate.1 "$pkgdir/usr/share/man/man1/sqmate.1"
    
    # Install bash completion
    install -Dm644 completion/bash/sqmate "$pkgdir/usr/share/bash-completion/completions/sqmate"
}
