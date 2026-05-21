EAPI=8

DESCRIPTION="TypeScript/Bun port of arRPC for Discord Rich Presence bridging"
HOMEPAGE="https://github.com/Creationsss/arrpc-bun"

SRC_URI="
	https://registry.npmjs.org/${PN}/-/${P}.tgz
	amd64? ( https://github.com/oven-sh/bun/releases/download/bun-v1.3.0/bun-linux-x64.zip )
	arm64? ( https://github.com/oven-sh/bun/releases/download/bun-v1.3.0/bun-linux-aarch64.zip )
"

S="${WORKDIR}/package"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

QA_PREBUILT="
	opt/${PN}/bun/bun
"

BDEPEND="
	app-arch/unzip
"

src_install() {
	insinto /opt/${PN}
	doins -r src scripts
	doins detectable.json detectable_fixes.json package.json

	local bun_dist bun_dir
	case ${ARCH} in
		amd64)
			bun_dist="bun-linux-x64.zip"
			bun_dir="bun-linux-x64"
			;;
		arm64)
			bun_dist="bun-linux-aarch64.zip"
			bun_dir="bun-linux-aarch64"
			;;
		*)
			die "unsupported ARCH for bundled bun: ${ARCH}"
			;;
	esac

	unzip -q "${DISTDIR}/${bun_dist}" -d "${T}" || die "failed to unpack bundled bun"

	insinto /opt/${PN}/bun
	doins "${T}/${bun_dir}/bun"
	fperms 0755 /opt/${PN}/bun/bun

	dodoc LICENSE README.md

	cat > "${T}/${PN}" <<-EOF || die
	#!/bin/sh
	exec /opt/${PN}/bun/bun /opt/${PN}/src/index.ts "\$@"
	EOF
	dobin "${T}/${PN}"
}
