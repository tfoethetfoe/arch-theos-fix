
#!/usr/bin/env bash

# Error codes + association:
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
# 11 - Enabling Linux binary compat on FreeBSD failed

set -e

# Pretty print
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


# Root is no bueno
if [[ $EUID -eq 0 ]]; then
	error "Theos should NOT be installed with or run as root (su/sudo)!"
	error "  - Please re-run the installer as a non-root user."
	exit 1
fi


# Common vars
PLATFORM=$(uname)
ARCH=$(uname -m)
CSHELL="${SHELL##*/}"
SHELL_ENV="unknown"

if [[ $CSHELL == sh || $CSHELL == bash || $CSHELL == dash ]]; then
	# Bash prioritizes bashrc > bash_profile > profile
	if [[ -f $HOME/.bashrc ]]; then
		SHELL_ENV="$HOME/.bashrc"
	elif [[ -f $HOME/.bash_profile ]]; then
		SHELL_ENV="$HOME/.bash_profile"
	else
		SHELL_ENV="$HOME/.profile"
	fi
elif [[ $CSHELL == zsh ]]; then
	# Zsh prioritizes zshenv > zprofile > zshrc
	zdot="${ZDOTDIR:-$HOME}"

	if [[ -f $zdot/.zshenv ]]; then
		SHELL_ENV="$zdot/.zshenv"
	elif [[ -f $zdot/.zprofile ]]; then
		SHELL_ENV="$zdot/.zprofile"
	else
		SHELL_ENV="$zdot/.zshrc"
	fi
fi


# The work
theos_bool() {
	local affirmative=(Y y YES yes TRUE true)

	if [[ ${affirmative[*]} =~ $1 ]]; then
		return 0
	else
		return 1
	fi
}


set_theos() {
	# Check for $THEOS env var
	update "Checking for \$THEOS environment variable..."

	if [[ -n $THEOS ]]; then
		update "\$THEOS is already set to '$THEOS'. Nothing to do here."
		return
	fi

	update "\$THEOS has not been set. Setting now..."

	if [[ $SHELL_ENV == unknown ]]; then
		error "Current shell ($CSHELL) is unsupported by this installer."
		error "Please set the THEOS environment variable to '~/theos' manually before proceeding."
		exit 4
	fi

	# Set $THEOS
	if [[ $PLATFORM == Darwin && ! -x $(command -v xcode-select) && -f /.bootstrapped ]]; then
		echo "export THEOS=/opt/theos" >> "$SHELL_ENV"
		export THEOS=/opt/theos

		if [[ -d /opt ]]; then
			update "'/opt' already exists. Checking its ownership..."

			OWNER="$(stat -c '%U' /opt)"

			if [[ $OWNER == root ]]; then
				update "Owner of '/opt' is root. Attempting to switch owner to mobile..."

				sudo chown mobile /opt \
					&& update "Owner of '/opt' successfully transferred to mobile!" \
					|| {
						error "Failed to transfer ownership of '/opt' to mobile."
						exit 9
					}
			else
				update "Owner of '/opt' is not root. We should be good to go!"
			fi
		else
			update "Creating a special directory to house Theos..."

			sudo install -d -o mobile -g mobile /opt \
				&& update "Special directory for Theos created successfully!" \
				|| {
					error "Special directory creation failed."
					exit 9
				}
		fi
	else
		echo "export THEOS=~/theos" >> "$SHELL_ENV"
		export THEOS=~/theos
	fi
}


get_theos() {
	update "Checking for Theos install..."

	if [[ -d $THEOS && $(ls -A "$THEOS") ]]; then
		update "Theos appears to already be installed. Checking for updates..."
		"$THEOS/bin/update-theos"
	else
		update "Theos does not appear to be installed. Cloning now..."

		git clone --recursive https://github.com/theos/theos.git "$THEOS" \
			&& update "Git clone of Theos was successful!" \
			|| {
				error "Theos git clone command failed."
				exit 6
			}
	fi
}


get_sdks() {
	update "Checking for patched SDKs..."

	if [[ -d $THEOS/sdks/ && $(ls -A "$THEOS/sdks/" | grep sdk) ]]; then
		update "SDKs appear to already be installed."
		return
	fi

	update "SDKs do not appear to be installed. Installing now..."

	"$THEOS/bin/install-sdk" latest &&
	"$THEOS/bin/install-sdk" latest-tv

	if [[ -n $(ls -A "$THEOS/sdks/" | grep sdk) ]]; then
		update "SDKs successfully installed!"
	else
		error "Something appears to have gone wrong while installing the SDKs."
		exit 8
	fi
}


darwin() {
	# Check for Xcode
	XCODE="$(xcode-select -p)"

	if [[ $XCODE == /Library/Developer/CommandLineTools && ! -d /Applications/Xcode.app/Contents/Developer/ ]]; then
		error "Xcode, not just the Command Line Tools, is required for Theos to function properly."
		common "Please install Xcode before continuing with the installation."
		exit 3
	elif [[ $XCODE == /Library/Developer/CommandLineTools && -d /Applications/Xcode.app/Contents/Developer/ ]]; then
		common "Xcode developer directory is currently $XCODE."
		common "Switching to /Applications/Xcode.app/Contents/Developer/..."

		sudo xcode-select -s /Applications/Xcode.app/Contents/Developer/
	elif [[ $XCODE != *.app/Contents/Developer ]]; then
		error "Xcode is required for Theos to function properly."
		common "Check the output of 'xcode-select -p'."
		exit 3
	fi

	# Dependencies
	update "Preparing to install dependencies..."

	if [[ -x $(command -v apt) && -f /opt/procursus/.procursus_strapped ]]; then
		sudo apt update || true

		sudo apt install -y ldid xz-utils \
			&& update "Dependencies have been successfully installed!" \
			|| {
				error "Dependency installation failed."
				exit 3
			}

	elif [[ -x $(command -v port) ]]; then
		sudo port selfupdate || true

		yes | sudo port install ldid xz \
			&& update "Dependencies have been successfully installed!" \
			|| {
				error "Dependency installation failed."
				exit 3
			}

	elif [[ -x $(command -v brew) ]]; then
		brew update || true

		brew install ldid xz \
			&& update "Dependencies have been successfully installed!" \
			|| {
				error "Dependency installation failed."
				exit 3
			}

	else
		read -p "Homebrew is not installed. Would you like to have it installed? [y/n] " hbrew

		if theos_bool "$hbrew"; then
			bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
				&& update "Homebrew has been successfully installed!" \
				|| {
					error "Homebrew installation failed."
					exit 3
				}

			brew install ldid xz
		else
			error "Homebrew provides tools Theos depends on."
			error "Please install Homebrew before proceeding."
			exit 3
		fi
	fi

	set_theos
	get_theos
	get_sdks
}


darwin_mobile() {
	LEGACY=0

	KERNEL_VER=$(sysctl kern.osrelease | sed 's/[^0-9]*//g')

	if [[ $KERNEL_VER < 1800 ]]; then
		LEGACY=1
	fi

	if ! [[ -x $(command -v sudo) ]]; then
		error "Please install 'sudo' before proceeding."
		exit 3
	fi

	if ! [[ -x $(command -v head) ]]; then
		error "Please install 'coreutils' before proceeding."
		exit 3
	fi

	if ! [[ -x $(command -v xz) ]]; then
		error "Please install 'xz-utils' before proceeding."
		exit 3
	fi

	if ! [[ -x $(command -v apt-get) ]]; then
		error "Please install 'apt' before proceeding."
		exit 3
	fi

	APTVER="$(apt-get --version | head -n1 | cut -d' ' -f2)"

	if dpkg --compare-versions "$APTVER" ge 1.1; then
		uFLAGS=(--allow-insecure-repositories)
		iFLAGS=(--allow-unauthenticated --allow-downgrades)
	elif dpkg --compare-versions "$APTVER" ge 0.6.8; then
		uFLAGS=()
		iFLAGS=(--allow-unauthenticated)
	else
		uFLAGS=()
		iFLAGS=()
	fi

	update "Preparing to install dependencies. Please enter your password if prompted:"

	if [[ $LEGACY -eq 1 ]]; then
		read -p "Do you have the required jailbreak repositories installed? [y/n] " ready

		if theos_bool "$ready"; then
			sudo apt-get update "${uFLAGS[@]}" || true

			sudo apt-get install -y "${iFLAGS[@]}" org.theos.dependencies \
				&& update "Dependencies have been successfully installed!" \
				|| {
					error "Dependency installation failed."
					exit 3
				}
		else
			error "Please install the required repositories before proceeding."
			exit 3
		fi
	else
		if [[ -f /.procursus_strapped || -f /var/jb/.procursus_strapped ]]; then
			read -p "Do you have 'https://apt.procurs.us' installed? [y/n] " ready

			if theos_bool "$ready"; then
				sudo apt update "${uFLAGS[@]}" || true

				sudo apt install -y "${iFLAGS[@]}" theos-dependencies \
					&& update "Dependencies have been successfully installed!" \
					|| {
						error "Dependency installation failed."
						exit 3
					}
			else
				error "Please install the required repository before proceeding."
				exit 3
			fi
		else
			read -p "Do you have 'https://apt.bingner.com' installed? [y/n] " ready

			if theos_bool "$ready"; then
				sudo apt update "${uFLAGS[@]}" || true

				sudo apt install -y "${iFLAGS[@]}" \
					ca-certificates clang coreutils curl dpkg git grep ldid make \
					odcctools perl com.bingner.plutil rsync xz \
					&& update "Dependencies have been successfully installed!" \
					|| {
						error "Dependency installation failed."
						exit 3
					}
			else
				error "Please install the required repository before proceeding."
				exit 3
			fi
		fi

		update "Checking desire for Swift support..."

		read -p "Would you like to be able to work with Swift? [y/n] " confirm

		if theos_bool "$confirm"; then
			if [[ -f /.procursus_strapped || -f /var/jb/.procursus_strapped ]]; then
				sudo apt install -y "${iFLAGS[@]}" swift
			else
				sudo apt install -y "${iFLAGS[@]}" com.kabiroberai.swift-toolchain
			fi
		else
			update "Skipping Swift support."
		fi
	fi

	set_theos
	get_theos
	get_sdks
}


linux() {
	local DISTRO="unknown"

	if [[ -x $(command -v apt) ]]; then
		DISTRO="debian"
	elif [[ -x $(command -v pacman) ]]; then
		DISTRO="arch"
	elif [[ -x $(command -v dnf) ]]; then
		DISTRO="redhat"
	elif [[ -x $(command -v zypper) ]]; then
		DISTRO="suse"
	fi

	update "Detected Linux distribution: $DISTRO"

	# Check for sudo
	if ! [[ -x $(command -v sudo) ]]; then
		error "Please install 'sudo' before proceeding."
		exit 3
	fi

	# Dependencies
	update "Preparing to install dependencies. Please enter your password if prompted:"

	case $DISTRO in
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
				libxml2 \
				&& update "Dependencies have been successfully installed!" \
				|| {
					error "Dependency installation failed."
					exit 3
				}
			;;

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
				libxml2 \
				&& update "Dependencies have been successfully installed!" \
				|| {
					error "Dependency installation failed."
					exit 3
				}
			;;

		redhat)
			sudo dnf group install -y "c-development" --refresh

			sudo dnf install -y \
				fakeroot \
				lzma \
				libbsd \
				rsync \
				curl \
				perl \
				zip \
				git \
				libxml2 \
				&& update "Dependencies have been successfully installed!" \
				|| {
					error "Dependency installation failed."
					exit 3
				}
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
				libxml2 \
				&& update "Dependencies have been successfully installed!" \
				|| {
					error "Dependency installation failed."
					exit 3
				}
			;;

		*)
			error "The dependencies for your Linux distribution are unknown."
			exit 3
			;;
	esac


	# Arch/CachyOS uses its own fakeroot packaging.
	# Do NOT use Debian's update-alternatives here.
	update "Checking fakeroot..."

	if ! command -v fakeroot >/dev/null 2>&1; then
		error "fakeroot was not found."
		error "Install it with your package manager and try again."
		exit 10
	fi

	FAKEROOT_PATH="$(command -v fakeroot)"

	if [[ $DISTRO == arch ]]; then
		update "Using Arch/CachyOS fakeroot at $FAKEROOT_PATH."
	else
		# Debian traditionally provides fakeroot-sysv through alternatives.
		# Only attempt it when the executable actually exists.
		if [[ -x /usr/bin/fakeroot-sysv && -x $(command -v update-alternatives) ]]; then
			sudo update-alternatives --set fakeroot /usr/bin/fakeroot-sysv \
				&& update "fakeroot adjusted!" \
				|| update "Could not adjust fakeroot; continuing with the installed version."
		else
			update "No compatible fakeroot alternative found; using $FAKEROOT_PATH."
		fi
	fi


	# Check for WSL
	update "Checking for WSL..."

	local rel
	rel="$(uname -r)"

	if [[ ${rel,,} =~ microsoft ]]; then
		if [[ $rel =~ WSL2 ]]; then
			update "WSL2 detected. Nothing to do here."
		else
			update "WSL1 detected."

			if [[ $DISTRO == arch ]]; then
				update "Using the native Arch/CachyOS fakeroot configuration."
			elif [[ -x /usr/bin/fakeroot-tcp && -x $(command -v update-alternatives) ]]; then
				sudo update-alternatives --set fakeroot /usr/bin/fakeroot-tcp \
					&& update "fakeroot adjusted for WSL1!" \
					|| update "Could not adjust fakeroot for WSL1; continuing."
			else
				update "No WSL1-specific fakeroot alternative is available."
			fi
		fi
	else
		update "Seems you're not using WSL. Moving on..."
	fi


	set_theos
	get_theos


	# Get a toolchain
	update "Checking for iOS toolchain..."

	if [[ -d $THEOS/toolchain/linux/iphone/ && $(ls -A "$THEOS/toolchain/linux/iphone") ]]; then
		update "A toolchain appears to already be installed."
	else
		update "A toolchain does not appear to be installed."

		stoolchain="n"

		if [[ -z $CI ]]; then
			read -p "Would you like your toolchain to support Swift (larger toolchain size) or not (smaller toolchain size)? [y/n] " stoolchain
		fi

		if theos_bool "$stoolchain"; then
			case $DISTRO in
				debian)
					sudo apt install -y libtinfo6
					;;

				arch)
					sudo pacman -S --needed --noconfirm ncurses

					# Toolchain looks for a specific libncurses.
					LATEST_LIBCURSES="$(ls -v /usr/lib/ | grep 'libncurses.*so' | tail -n1)"

					if [[ -n $LATEST_LIBCURSES ]]; then
						sudo ln -sf "/usr/lib/$LATEST_LIBCURSES" /usr/lib/libncurses.so.6
					fi
					;;

				redhat)
					sudo dnf install -y ncurses-libs
					;;

				suse)
					common "Unfortunately, we do not currently provide a SUSE-compatible Swift toolchain."
					get_sdks
					return
					;;
			esac

			if [[ $ARCH == x86_64 ]]; then
				curl -sL \
					https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu20.04.tar.xz \
					| tar -xJvf - -C "$THEOS/toolchain/"
			elif [[ $ARCH == aarch64 ]]; then
				curl -sL \
					"https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu20.04-$ARCH.tar.xz" \
					| tar -xJvf - -C "$THEOS/toolchain/"
			else
				common "Apologies, we do not currently provide precompiled toolchains for $ARCH Linux."
				get_sdks
				return
			fi
		else
			case $DISTRO in
				debian)
					sudo apt install -y libtinfo6
					;;

				arch)
					sudo pacman -S --needed --noconfirm ncurses
					;;

				redhat)
					sudo dnf install -y ncurses-libs
					;;

				suse)
					sudo zypper install -y libncurses6
					;;
			esac

			if [[ $ARCH == aarch64 || $ARCH == x86_64 ]]; then
				curl -sL \
					"https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-$ARCH.tar.xz" \
					| tar -xJvf - -C "$THEOS/toolchain/"
			else
				common "Apologies, we do not currently provide precompiled toolchains for $ARCH Linux."
				get_sdks
				return
			fi
		fi

		# Confirm that toolchain is usable
		if [[ -x $THEOS/toolchain/linux/iphone/bin/clang ]]; then
			update "Successfully installed the toolchain!"
		else
			error "Something appears to have gone wrong -- the toolchain is not accessible."
			exit 7
		fi
	fi


	get_sdks
}


# Determine platform and start work
special "Starting install..."
common "Platform: $PLATFORM"

if [[ $PLATFORM == Darwin ]]; then
	if [[ -x $(command -v xcode-select) ]]; then
		darwin
	else
		darwin_mobile
	fi
elif [[ ${PLATFORM,,} == linux ]]; then
	linux
else
	error "'$PLATFORM' is currently unsupported by this installer and/or Theos."
	exit 2
fi

special "Theos has been successfully installed!"
common "Restart your shell and then run \$THEOS/bin/nic.pl to get started."

