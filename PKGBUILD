# Maintainer: qlfahey
pkgname=omaspaces
pkgver=0.2.2
pkgrel=1
pkgdesc="Design, launch, and navigate Hyprland workspaces — a native Quickshell spaces system for Omarchy"
arch=('any')
url="https://github.com/qlfahey/omaspaces"
license=('MIT')
depends=('python' 'quickshell' 'jq' 'grim' 'hyprland' 'inotify-tools' 'wl-clipboard')
optdepends=('chromium: web builder fallback (omaspaces build --web)'
            'ttf-jetbrains-mono-nerd: matches the default Omarchy font')
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')

package() {
  cd "$srcdir/$pkgname-$pkgver"
  install -Dm755 bin/omaspaces "$pkgdir/usr/bin/omaspaces"
  install -Dm644 omaspaces.desktop "$pkgdir/usr/share/applications/omaspaces.desktop"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
  # UI assets (read-only); the tool resolves these from /usr/share/omaspaces.
  install -dm755 "$pkgdir/usr/share/omaspaces"
  cp -r share/qml share/qml-dock "$pkgdir/usr/share/omaspaces/"
  install -Dm644 share/builder.html "$pkgdir/usr/share/omaspaces/builder.html"
}
