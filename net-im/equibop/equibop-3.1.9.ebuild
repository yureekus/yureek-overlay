EAPI=8

inherit desktop xdg

IUSE="+arrpc +bundled-electron source-libvesktop +venmic"

DESCRIPTION="Custom Discord desktop app from the Equicord project"
HOMEPAGE="https://equicord.org https://github.com/Equicord/Equibop"

SRC_URI="
	https://github.com/Equicord/Equibop/archive/refs/tags/v${PV}.tar.gz -> ${P}.gh.tar.gz
	amd64? ( https://github.com/Equicord/Equibop/releases/download/v${PV}/node_modules-x64.tar.gz -> ${P}-node_modules.tar.gz )
	arm64? ( https://github.com/Equicord/Equibop/releases/download/v${PV}/node_modules-arm64.tar.gz -> ${P}-node_modules.tar.gz )
	amd64? ( https://github.com/oven-sh/bun/releases/download/bun-v1.3.0/bun-linux-x64.zip -> ${P}-bun.zip )
	arm64? ( https://github.com/oven-sh/bun/releases/download/bun-v1.3.0/bun-linux-aarch64.zip -> ${P}-bun.zip )
	https://github.com/Equicord/Equibop/releases/download/v${PV}/org.equicord.equibop.metainfo.xml -> ${P}.metainfo.xml
"

S="${WORKDIR}/Equibop-${PV}"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

DEPEND="
	dev-libs/glib:2
"
RDEPEND="
	${DEPEND}
"
BDEPEND="
	app-arch/unzip
	net-libs/nodejs
	virtual/pkgconfig
	virtual/python
"

QA_PREBUILT="
	opt/${PN}/static/dist/venmic-*.node
	opt/${PN}/static/dist/libvesktop-*.node
	opt/${PN}/electron/*.so
	opt/${PN}/electron/electron
	opt/${PN}/electron/chrome-sandbox
	opt/${PN}/electron/chrome_crashpad_handler
"

src_unpack() {
	default

	cd "${S}" || die
	tar -xzf "${DISTDIR}/${P}-node_modules.tar.gz" || die "failed to unpack bundled node_modules"
}

src_compile() {
	local bun_dir
	case ${ARCH} in
		amd64) bun_dir="${WORKDIR}/bun-linux-x64" ;;
		arm64) bun_dir="${WORKDIR}/bun-linux-aarch64" ;;
		*) die "unsupported ARCH for bundled bun: ${ARCH}" ;;
	esac

	export PATH="${bun_dir}:${S}/node_modules/.bin:${PATH}"
	export npm_config_update_notifier=false
	export BUN_INSTALL_CACHE="${T}/bun-install-cache"

	command -v bun >/dev/null || die "bundled bun not found after unpack"

	if use source-libvesktop; then
		command -v node >/dev/null || die "node not found in PATH; source-libvesktop requires net-libs/nodejs"
		pushd packages/libvesktop >/dev/null || die
		node "${S}/node_modules/node-gyp/bin/node-gyp.js" configure build || die "libvesktop build failed"
		popd >/dev/null || die
	fi

	if use arrpc; then
		bun run compileArrpc || die "arRPC build failed"
	fi

	bun run build || die "application build failed"

	if ! use venmic; then
		rm -f static/dist/venmic-*.node || die
	fi

	if ! use arrpc; then
		rm -f static/dist/arrpc-* || die
	fi
}

src_install() {
	insinto /opt/${PN}
	doins -r dist static package.json

	if use bundled-electron; then
		insinto /opt/${PN}/electron
		doins -r node_modules/electron/dist/*
	fi

	if [[ -f "${ED}/opt/${PN}/static/dist/arrpc-linux-x64" ]]; then
		fperms 0755 /opt/${PN}/static/dist/arrpc-linux-x64
	fi

	if [[ -f "${ED}/opt/${PN}/static/dist/arrpc-linux-arm64" ]]; then
		fperms 0755 /opt/${PN}/static/dist/arrpc-linux-arm64
	fi

	if use bundled-electron; then
		fperms 0755 /opt/${PN}/electron/electron
		fperms 0755 /opt/${PN}/electron/chrome-sandbox
		fperms 0755 /opt/${PN}/electron/chrome_crashpad_handler
	fi

	dodoc LICENSE README.md

	newicon -s scalable build/icon.svg org.equicord.equibop.svg
	newicon -s 256 static/icon.png org.equicord.equibop.png
	domenu build/org.equicord.equibop.desktop

	insinto /usr/share/metainfo
	newins "${DISTDIR}/${P}.metainfo.xml" org.equicord.equibop.metainfo.xml

	cat > "${T}/${PN}" <<-EOF || die
	#!/bin/sh
	if [[ -x /opt/${PN}/electron/electron ]]; then
		exec /opt/${PN}/electron/electron /opt/${PN} "$@"
	fi

	if command -v electron >/dev/null 2>&1; then
		exec electron /opt/${PN} "$@"
	fi

	if command -v electron-40 >/dev/null 2>&1; then
		exec electron-40 /opt/${PN} "$@"
	fi

	echo "No suitable Electron runtime found for Equibop." >&2
	exit 1
	EOF
	dobin "${T}/${PN}"
}

pkg_postinst() {
	xdg_pkg_postinst

	if ! use bundled-electron; then
		ewarn "bundled-electron is disabled; you need an 'electron' or 'electron-40' executable in PATH at runtime."
	fi

	if ! use arrpc; then
		einfo "The bundled arRPC helper was not installed because the arrpc USE flag is disabled."
	fi

	if ! use venmic; then
		einfo "Virtual microphone support was omitted because the venmic USE flag is disabled."
	fi
}

pkg_postrm() {
	xdg_pkg_postrm
}