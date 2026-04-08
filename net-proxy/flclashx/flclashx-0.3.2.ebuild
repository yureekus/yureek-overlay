EAPI=8

inherit desktop xdg

DESCRIPTION="Flutter-based Clash.Meta GUI client (FlClashX)"
HOMEPAGE="https://github.com/pluralplay/FlClashX"

XHOMO_COMMIT="b64d7d11580154979aec38b17fd1475393c4135f"

SRC_URI="
	https://github.com/pluralplay/FlClashX/archive/refs/tags/v${PV}.tar.gz -> ${P}.gh.tar.gz
	https://github.com/pluralplay/xHomo/archive/${XHOMO_COMMIT}.tar.gz -> ${P}-xhomo-${XHOMO_COMMIT}.tar.gz
	amd64? ( https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.6-stable.tar.xz -> ${P}-flutter-amd64.tar.xz )
"

S="${WORKDIR}/FlClashX-${PV}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="amd64 ~arm64"
IUSE="+gvisor suid"
RESTRICT="network-sandbox"

DEPEND="
	dev-libs/glib:2
	dev-libs/keybinder
	dev-libs/libayatana-appindicator
	x11-libs/gtk+:3
"
RDEPEND="${DEPEND}"
BDEPEND="
	dev-lang/go
	virtual/pkgconfig
"

QA_PREBUILT="
	opt/${PN}/lib/libflutter_linux_gtk.so
"

src_unpack() {
	default

	cd "${WORKDIR}" || die
	rm -rf "${S}/core/Clash.Meta" || die
	tar -xzf "${DISTDIR}/${P}-xhomo-${XHOMO_COMMIT}.tar.gz" || die "failed to unpack xHomo source"
	mv "${WORKDIR}/xHomo-${XHOMO_COMMIT}" "${S}/core/Clash.Meta" || die
}

src_compile() {
	local goarch flutter_arch core_version build_tags flutter_cmd

	case ${ARCH} in
		amd64)
			goarch="amd64"
			flutter_arch="x64"
			flutter_cmd="${WORKDIR}/flutter/bin/flutter"
			;;
		arm64)
			goarch="arm64"
			flutter_arch="arm64"
			flutter_cmd=$(command -v flutter || true)
			;;
		*) die "unsupported ARCH: ${ARCH}" ;;
	esac

	if use gvisor; then
		build_tags="with_gvisor"
	fi

	core_version=$(sed -n 's/^[[:space:]]*Version[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' core/Clash.Meta/constant/version.go | head -n1)
	[[ -n ${core_version} ]] || die "failed to detect Clash core version"

	mkdir -p libclash/linux || die
	export GOMODCACHE="${T}/go-mod-cache"
	export GOPATH="${T}/go"
	export GOCACHE="${T}/go-build-cache"
	export GODEBUG="netdns=cgo"
	mkdir -p "${GOMODCACHE}" "${GOPATH}" "${GOCACHE}" || die

	pushd core >/dev/null || die
	go mod download || die "go module download failed"
	if [[ -n ${build_tags} ]]; then
		GOOS=linux GOARCH="${goarch}" CGO_ENABLED=0 go build -ldflags='-w -s' -tags="${build_tags}" -o "${S}/libclash/linux/FlClashCore" || die "FlClashCore build failed"
	else
		GOOS=linux GOARCH="${goarch}" CGO_ENABLED=0 go build -ldflags='-w -s' -o "${S}/libclash/linux/FlClashCore" || die "FlClashCore build failed"
	fi
	popd >/dev/null || die

	export HOME="${T}/home"
	export PUB_CACHE="${T}/pub-cache"
	export CI="true"
	export FLUTTER_SUPPRESS_ANALYTICS="true"
	mkdir -p "${HOME}" "${PUB_CACHE}" || die
	[[ -n ${flutter_cmd} && -x ${flutter_cmd} ]] || die "flutter executable not found; amd64 uses bundled SDK, arm64 currently requires flutter in PATH"
	"${flutter_cmd}" config --no-analytics >/dev/null 2>&1 || true

	"${flutter_cmd}" pub get || die "flutter pub get failed"

	# Remove -Werror from plugin CMakeLists to allow deprecated/uninitialized-variable
	# warnings in third-party plugin C++ code (tray_manager, hotkey_manager_linux, etc.)
	find "${PUB_CACHE}" -name "CMakeLists.txt" -exec sed -i 's/ -Werror\b//g; s/\b-Werror //g; s/\b-Werror\b//g' {} +

	"${flutter_cmd}" build linux --release --verbose --dart-define="APP_ENV=stable" --dart-define="CORE_VERSION=${core_version}" || die "flutter build failed"

	[[ -d "build/linux/${flutter_arch}/release/bundle" ]] || die "flutter bundle missing for ${flutter_arch}"
}

src_install() {
	local bundle_dir

	case ${ARCH} in
		amd64) bundle_dir="build/linux/x64/release/bundle" ;;
		arm64) bundle_dir="build/linux/arm64/release/bundle" ;;
		*) die "unsupported ARCH: ${ARCH}" ;;
	esac

	insinto /opt/${PN}
	doins -r "${bundle_dir}"/*

	fperms 0755 /opt/${PN}/FlClashX
	fperms 0755 /opt/${PN}/FlClashCore
	if use suid; then
		fperms 4755 /opt/${PN}/FlClashCore
	fi

	cat > "${T}/${PN}" <<-EOF || die
	#!/bin/sh
	exec /opt/${PN}/FlClashX "$@"
	EOF
	dobin "${T}/${PN}"

	cat > "${T}/${PN}.desktop" <<-EOF || die
	[Desktop Entry]
	Type=Application
	Name=FlClashX
	Comment=FlClashX proxy client based on Clash.Meta
	Exec=${PN}
	Icon=${PN}
	Terminal=false
	Categories=Network;
	StartupWMClass=com.follow.clashx
	EOF
	domenu "${T}/${PN}.desktop"

	newicon -s 256 assets/images/icon.png ${PN}.png

	dodoc README.md README_EN.md CHANGELOG.md
}

pkg_postinst() {
	xdg_pkg_postinst

	if use suid; then
		ewarn "FlClashCore was installed setuid-root due to USE=suid."
		ewarn "Enable this only if you trust the package and need privileged TUN behavior."
	fi
}

pkg_postrm() {
	xdg_pkg_postrm
}
