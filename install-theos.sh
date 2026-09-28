#!/usr/bin/env bash

# Error codes:
# 1 - Running as root
# 2 - Unsupported platform
# 3 - Dependency issue
# 4 - Unsupported shell
# 5 - Setting $THEOS failed
# 6 - Theos clone failed
# 7 - Toolchain install failed
# 8 - SDK install failed
# 9 - Checkra1n '/opt' setup failed
# 10 - fakeroot adjustment failed

# Don't run this as root.
if [[ $EUID -eq 0 ]]; then
	error "Theos should NOT be installed as root!"
	error "Please run the installer as your normal user."
	exit 1
fi

special() {
	printf "\e[0;34m==> \e[1;34mTheos Installer:\e[m %s\n" "$1"
}

update() {
	printf "\n\e[0;36m==> \e[1;36m%s\e[m\n" "$1"
}

common() {
	printf "\n\e[0;37m==> \e[1;37m%s\e[m\n" "$1"
}

error() {
	printf "\e[0;31m==> \e[1;31m%s\e[m\n" "$1"
}

PLATFORM="$(uname)"
ARCH="$(uname -m)"
CSHELL="${SHELL##*/}"
SHELL_ENV="unknown"

if [[ $CSHELL == sh || $CSHELL == bash || $CSHELL == dash ]]; then
	if [[ -f "$HOME/.bashrc" ]]; then
		SHELL_ENV="$HOME/.bashrc"
	elif [[ -f "$HOME/.bash_profile" ]]; then
		SHELL_ENV="$HOME/.bash_profile"
	else
		SHELL_ENV="$HOME/.profile"
	fi
elif [[ $CSHELL == zsh ]]; then
	zdot="${ZDOTDIR:-$HOME}"

	if [[ -f "$zdot/.zshenv" ]]; then
		SHELL_ENV="$zdot/.zshenv"
	elif [[ -f "$zdot/.zprofile" ]]; then
		SHELL_ENV="$zdot/.zprofile"
	else
		SHELL_ENV="$zdot/.zshrc"
	fi
fi

theos_bool() {
	case "${1,,}" in
		y|yes|true)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

set_theos() {
	update "Checking for \$THEOS environment variable..."

	if [[ -n $THEOS ]]; then
		update "\$THEOS is already set to '$THEOS'. Nothing to do here."
		return
	fi

	if [[ $SHELL_ENV == unknown ]]; then
		error "Your shell ($CSHELL) is not supported by this installer."
		error "Please set THEOS manually to ~/theos."
		exit 4
	fi

	update "Setting \$THEOS..."

	THEOS="$HOME/theos"
	export THEOS

	if ! grep -q 'export THEOS=' "$SHELL_ENV" 2>/dev/null; then
		echo 'export THEOS="$HOME/theos"' >> "$SHELL_ENV"
	fi

	update "\$THEOS has been set to '$THEOS'."
}

get_theos() {
	update "Checking for Theos install..."

	if [[ -d "$THEOS" ]] && [[ -n "$(ls -A "$THEOS" 2>/dev/null)" ]]; then
		update "Theos appears to already be installed. Checking for updates..."

		if [[ -x "$THEOS/bin/update-theos" ]]; then
			"$THEOS/bin/update-theos" || true
		fi
	else
		update "Theos does not appear to be installed. Cloning now..."

		if git clone --recursive https://github.com/theos/theos.git "$THEOS"; then
			update "Git clone of Theos was successful!"
		else
			error "Theos git clone command failed."
			exit 6
		fi
	fi
}

get_sdks() {
	update "Checking for patched SDKs..."

	if [[ -d "$THEOS/sdks" ]] &&
		ls -A "$THEOS/sdks" 2>/dev/null | grep -q sdk; then
		update "SDKs appear to already be installed."
		return
	fi

	update "SDKs do not appear to be installed. Installing now..."

	if ! "$THEOS/bin/install-sdk" latest; then
		error "Failed to install the latest SDK."
		exit 8
	fi

	if ! "$THEOS/bin/install-sdk" latest-tv; then
		error "Failed to install the latest tvOS SDK."
		exit 8
	fi

	if ls -A "$THEOS/sdks" 2>/dev/null | grep -q sdk; then
		update "SDKs successfully installed!"
	else
		error "Something went wrong while installing the SDKs."
		exit 8
	fi
}

darwin() {
	XCODE="$(xcode-select -p 2>/dev/null || true)"

	if [[ $XCODE == /Library/Developer/CommandLineTools ]] &&
		[[ ! -d /Applications/Xcode.app/Contents/Developer ]]; then
		error "Full Xcode is required for Theos."
		error "The Command Line Tools alone aren't enough."
		exit 3
	fi

	if [[ $XCODE == /Library/Developer/CommandLineTools ]] &&
		[[ -d /Applications/Xcode.app/Contents/Developer ]]; then
		update "Switching to the full Xcode installation..."

		sudo xcode-select -s /Applications/Xcode.app/Contents/Developer/
	fi

	update "Preparing to install dependencies..."

	if command -v apt >/dev/null 2>&1 &&
		[[ -f /opt/procursus/.procursus_strapped ]]; then

		sudo apt update || true

		sudo apt install -y ldid xz-utils
	elif command -v port >/dev/null 2>&1; then
		sudo port selfupdate || true
		sudo port install ldid xz
	elif command -v brew >/dev/null 2>&1; then
		brew update || true
		brew install ldid xz
	else
		read -r -p "Homebrew is not installed. Install it? [y/n] " hbrew

		if theos_bool "$hbrew"; then
			/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
			brew install ldid xz
		else
			error "Homebrew is required."
			exit 3
		fi
	fi

	update "Dependencies have been successfully installed!"

	set_theos
	get_theos
	get_sdks
}

darwin_mobile() {
	if ! command -v sudo >/dev/null 2>&1; then
		error "Please install sudo before proceeding."
		exit 3
	fi

	if ! command -v apt-get >/dev/null 2>&1; then
		error "Please install apt before proceeding."
		exit 3
	fi

	if ! command -v xz >/dev/null 2>&1; then
		error "Please install xz before proceeding."
		exit 3
	fi

	update "Preparing to install dependencies..."

	sudo apt-get update || true

	if [[ -f /.procursus_strapped ]] ||
		[[ -f /var/jb/.procursus_strapped ]]; then

		sudo apt-get install -y \
			ca-certificates \
			clang \
			coreutils \
			curl \
			git \
			ldid \
			make \
			perl \
			rsync \
			xz
	else
		sudo apt-get install -y \
			ca-certificates \
			clang \
			coreutils \
			curl \
			dpkg \
			git \
			grep \
			ldid \
			make \
			perl \
			rsync \
			xz
	fi

	set_theos
	get_theos
	get_sdks
}

linux() {
	local DISTRO="unknown"

	if command -v pacman >/dev/null 2>&1; then
		DISTRO="arch"
	elif command -v apt >/dev/null 2>&1; then
		DISTRO="debian"
	elif command -v dnf >/dev/null 2>&1; then
		DISTRO="redhat"
	elif command -v zypper >/dev/null 2>&1; then
		DISTRO="suse"
	fi

	update "Detected Linux distribution: $DISTRO"

	if ! command -v sudo >/dev/null 2>&1; then
		error "Please install sudo before proceeding."
		exit 3
	fi

	update "Preparing to install dependencies. Please enter your password if prompted:"

	case $DISTRO in
		arch)
			sudo pacman -Syu --noconfirm || true

			sudo pacman -S --needed --noconfirm \
				base-devel \
				libbsd \
				fakeroot \
				openssl \
				rsync \
				curl \
				perl \
				zip \
				git \
				libxml2
			;;

		debian)
			sudo apt update || true

			sudo apt install -y \
				build-essential \
				fakeroot \
				rsync \
				curl \
				perl \
				zip \
				git \
				libxml2
			;;

		redhat)
			sudo dnf group install -y "c-development" || true

			sudo dnf install -y \
				fakeroot \
				lzma \
				libbsd \
				rsync \
				curl \
				perl \
				zip \
				git \
				libxml2
			;;

		suse)
			sudo zypper refresh || true
			sudo zypper install -y -t pattern devel_basis

			sudo zypper install -y \
				fakeroot \
				libbsd0 \
				rsync \
				curl \
				perl \
				zip \
				git \
				libxml2
			;;

		*)
			error "The dependencies for your Linux distribution are unknown."
			exit 3
			;;
	esac

	update "Dependencies have been successfully installed!"

	# Arch doesn't have fakeroot-sysv or fakeroot-tcp.
	# The fakeroot package already provides the command we need.
	update "Checking fakeroot..."

	if ! command -v fakeroot >/dev/null 2>&1; then
		error "fakeroot could not be found."
		error "Try running: sudo pacman -S fakeroot"
		exit 10
	fi

	update "Using fakeroot at $(command -v fakeroot)."

	update "Checking for WSL..."

	local rel
	rel="$(uname -r)"

	if [[ ${rel,,} == *microsoft* ]]; then
		if [[ ${rel,,} == *wsl2* ]]; then
			update "WSL2 detected. Nothing to do here."
		else
			update "WSL1 detected."

			if [[ $DISTRO == arch ]]; then
				update "Using the native Arch fakeroot setup."
			elif command -v update-alternatives >/dev/null 2>&1 &&
				[[ -x /usr/bin/fakeroot-tcp ]]; then
				sudo update-alternatives --set fakeroot /usr/bin/fakeroot-tcp || true
			else
				update "No WSL1 fakeroot alternative was found."
			fi
		fi
	else
		update "Seems you're not using WSL. Moving on..."
	fi

	set_theos
	get_theos

	update "Checking for iOS toolchain..."

	if [[ -d "$THEOS/toolchain/linux/iphone" ]] &&
		[[ -x "$THEOS/toolchain/linux/iphone/bin/clang" ]]; then
		update "A toolchain appears to already be installed."
	else
		update "A toolchain does not appear to be installed."

		local stoolchain="n"

		if [[ -z $CI ]]; then
			read -r -p \
				"Would you like Swift support? [y/n] " \
				stoolchain
		fi

		if theos_bool "$stoolchain"; then
			case $DISTRO in
				arch)
					sudo pacman -S --needed --noconfirm ncurses
					;;

				debian)
					sudo apt install -y libtinfo6
					;;

				redhat)
					sudo dnf install -y ncurses-libs
					;;

				suse)
					common "Swift toolchain support is not available for SUSE."
					get_sdks
					return
					;;
			esac

			mkdir -p "$THEOS/toolchain"

			if [[ $ARCH == x86_64 ]]; then
				curl -fL \
					https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu20.04.tar.xz \
					| tar -xJf - -C "$THEOS/toolchain"
			elif [[ $ARCH == aarch64 ]]; then
				curl -fL \
					"https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu20.04-$ARCH.tar.xz" \
					| tar -xJf - -C "$THEOS/toolchain"
			else
				common "There is no Swift toolchain available for $ARCH."
				get_sdks
				return
			fi
		else
			case $DISTRO in
				arch)
					sudo pacman -S --needed --noconfirm ncurses
					;;

				debian)
					sudo apt install -y libtinfo6
					;;

				redhat)
					sudo dnf install -y ncurses-libs
					;;

				suse)
					sudo zypper install -y libncurses6
					;;
			esac

			if [[ $ARCH != x86_64 && $ARCH != aarch64 ]]; then
				common "There is no precompiled toolchain available for $ARCH."
				get_sdks
				return
			fi

			mkdir -p "$THEOS/toolchain"

			curl -fL \
				"https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-$ARCH.tar.xz" \
				| tar -xJf - -C "$THEOS/toolchain"
		fi

		if [[ -x "$THEOS/toolchain/linux/iphone/bin/clang" ]]; then
			update "Successfully installed the toolchain!"
		else
			error "The toolchain was downloaded, but clang could not be found."
			exit 7
		fi
	fi

	get_sdks
}

special "Starting install..."
common "Platform: $PLATFORM"

if [[ $PLATFORM == Darwin ]]; then
	if command -v xcode-select >/dev/null 2>&1; then
		darwin
	else
		darwin_mobile
	fi
elif [[ ${PLATFORM,,} == linux ]]; then
	linux
else
	error "'$PLATFORM' is currently unsupported by this installer."
	exit 2
fi

special "Theos has been successfully installed!"
common "Restart your shell and then run \$THEOS/bin/nic.pl to get started."
