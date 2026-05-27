EAPI=8

DOTNET_PKG_COMPAT="10.0"

inherit desktop dotnet-pkg-base xdg

DESCRIPTION="Canary builds of the Ryujinx Nintendo Switch emulator from the Ryubing project"
HOMEPAGE="https://git.ryujinx.app/projects/Ryubing https://www.ryujinxcanary.org"

RYUBING_COMMIT="fb7c1fde11d33e0884bee192d4b95083181d500c"

SRC_URI="https://git.ryujinx.app/projects/Ryubing/archive/Canary-${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/ryubing"

LICENSE="MIT BSD LGPL-3"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="+desktop +gamemode +mime updater"
RESTRICT="network-sandbox strip test"

RDEPEND="
	${DOTNET_PKG_RDEPS}
	app-arch/brotli
	dev-libs/expat
	gamemode? ( games-util/gamemode )
	media-libs/fontconfig
	media-libs/freetype
	media-libs/harfbuzz
	media-libs/libglvnd
	media-libs/libsdl3
	media-libs/libsoundio
	media-libs/openal
	>=media-video/ffmpeg-5:=
	<media-video/ffmpeg-7:=
	x11-libs/libICE
	x11-libs/libSM
	x11-libs/libX11
	x11-libs/libXau
	x11-libs/libXcursor
	x11-libs/libXdmcp
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXi
	x11-libs/libXrandr
	x11-libs/libXrender
	x11-libs/libxcb
	x11-libs/libxkbcommon
"
DEPEND="${RDEPEND}"
BDEPEND="${DOTNET_PKG_BDEPS}"

DOCS=( CHANGELOG.md COMPILING.md README.md distribution/legal/THIRDPARTY.md )

pkg_setup() {
	dotnet-pkg-base_setup
}

src_prepare() {
	default

	local short_commit="${RYUBING_COMMIT:0:7}"

	sed -i \
		-e "s/%%RYUJINX_BUILD_VERSION%%/${PV}/g" \
		-e "s/%%RYUJINX_BUILD_GIT_HASH%%/${short_commit}/g" \
		-e "s/%%RYUJINX_TARGET_RELEASE_CHANNEL_NAME%%/canary/g" \
		-e "s/%%RYUJINX_CONFIG_FILE_NAME%%/Config.json/g" \
		src/Ryujinx.Common/ReleaseInformation.cs || die "failed to patch release metadata"

	sed -i \
		-e '/Ryujinx.Graphics.Nvdec.Dependencies.AllArch/d' \
		src/Ryujinx/Ryujinx.csproj || die "failed to remove bundled FFmpeg dependency"

	sed -i \
		-e '/Native\\libsoundio\\libs\\libsoundio.so/,+3d' \
		src/Ryujinx.Audio.Backends.SoundIo/Ryujinx.Audio.Backends.SoundIo.csproj ||
		die "failed to remove bundled libsoundio dependency"

	rm -f \
		src/Ryujinx.Audio.Backends.SoundIo/Native/libsoundio/libs/libsoundio.so ||
		die "failed to remove unused bundled native libraries"

	sed -i \
		-e 's/^Name=Ryujinx$/Name=Ryujinx Canary/' \
		-e "s/^Exec=Ryujinx.sh/Exec=${PN}/" \
		-e "s/^Icon=Ryujinx$/Icon=${PN}/" \
		distribution/linux/Ryujinx.desktop || die "failed to patch desktop entry"
}

_ryubing_dotnet_args() {
	local -n args_ref=$1

	args_ref=(
		-p:Version="${PV}"
		-p:SourceRevisionId="${RYUBING_COMMIT:0:7}"
	)

	if ! use updater; then
		args_ref+=( -p:ExtraDefineConstants=DISABLE_UPDATER )
	fi
}

src_configure() {
	local -a restore_args
	_ryubing_dotnet_args restore_args

	dotnet-pkg-base_info
	edotnet restore \
		--runtime "${DOTNET_PKG_RUNTIME}" \
		--verbosity "${DOTNET_VERBOSITY}" \
		-maxCpuCount:$(makeopts_jobs) \
		"${restore_args[@]}" \
		src/Ryujinx/Ryujinx.csproj || die "dotnet restore failed"
}

src_compile() {
	local -a build_args
	_ryubing_dotnet_args build_args

	edotnet build \
		--configuration "${DOTNET_PKG_CONFIGURATION}" \
		--no-restore \
		--no-self-contained \
		--output "${DOTNET_PKG_OUTPUT}" \
		--runtime "${DOTNET_PKG_RUNTIME}" \
		--verbosity "${DOTNET_VERBOSITY}" \
		-maxCpuCount:$(makeopts_jobs) \
		"${build_args[@]}" \
		src/Ryujinx/Ryujinx.csproj || die "dotnet build failed"

	rm -f "${DOTNET_PKG_OUTPUT}/libarmeilleure-jitsupport.dylib" ||
		die "failed to remove unused macOS JIT helper"
}

src_install() {
	dotnet-pkg-base_install /opt/${PN}

	fperms 0755 /opt/${PN}/Ryujinx

	cat > "${T}/${PN}" <<-EOF || die
	#!/bin/sh
	for __dotnet_root in \\
		"${EPREFIX}/usr/$(get_libdir)/dotnet-sdk-${DOTNET_PKG_COMPAT}" \\
		"${EPREFIX}/opt/dotnet-sdk-bin-${DOTNET_PKG_COMPAT}" ; do
		[ -d "\${__dotnet_root}" ] && break
	done

	export DOTNET_ROOT="\${__dotnet_root}"
	export DOTNET_EnableAlternateStackCheck=1
	export LANG="\${LANG:-C.UTF-8}"

	if [ -x "${EPREFIX}/opt/${PN}/Ryujinx" ]; then
		set -- "${EPREFIX}/opt/${PN}/Ryujinx" "\$@"
	else
		set -- "\${DOTNET_ROOT}/dotnet" "${EPREFIX}/opt/${PN}/Ryujinx.dll" "\$@"
	fi

	if $(usex gamemode true false) && command -v gamemoderun >/dev/null 2>&1; then
		exec gamemoderun "\$@"
	fi

	exec "\$@"
	EOF
	dobin "${T}/${PN}"

	if use desktop; then
		domenu distribution/linux/Ryujinx.desktop
		newicon -s scalable distribution/misc/Logo.svg ${PN}.svg
	fi

	if use mime; then
		insinto /usr/share/mime/packages
		newins distribution/linux/mime/Ryujinx.xml ${PN}.xml
	fi

	einstalldocs
}

pkg_postinst() {
	xdg_pkg_postinst

	if ! use updater; then
		einfo "The upstream in-app updater was disabled; update ${CATEGORY}/${PN} through Portage."
	fi
}

pkg_postrm() {
	xdg_pkg_postrm
}
