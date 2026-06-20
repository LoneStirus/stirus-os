#!/usr/bin/env bash

# .------------------------------------------------------------------------.
# |   ____ _____ ___ ____  _   _ ____     ___  ____                        |
# |  / ___|_   _|_ _|  _ \| | | / ___|   / _ \/ ___|                       |
# |  \___ \ | |  | || |_) | | | \___ \  | | | \___ \                       |
# |   ___) || |  | ||  _ <| |_| |___) | | |_| |___) |                      |
# |  |____/ |_| |___|_| \_\\___/|____/   \___/|____/                       |
# |       ____          _                     ____  _   _                  |
# |      | __ ) _   _  | |    ___  _ __   ___/ ___|| |_(_)_ __ _   _ ___   |
# |      |  _ \| | | | | |   / _ \| '_ \ / _ \___ \| __| | '__| | | / __|  |
# |      | |_) | |_| | | |__| (_) | | | |  __/___) | |_| | |  | |_| \__ \  |
# |      |____/ \__, | |_____\___/|_| |_|\___|____/ \__|_|_|   \__,_|___/  |
# |             |___/                                                      |
# '------------------------------------------------------------------------'

#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
#	ERROR TRIGGER
#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
# Stop script if error
set -euo pipefail

#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
#	VARS OF THE SCRIPT - MODIFY THIS!!
#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
# Target disk
DISK="/dev/nvme0n1"

# Partitions size
# ESP_SIZE=""
# SWAP_SIZE=""

# System identity [DON'T MODIFY THIS!!]
BOOT_MODE=""
# MNT="/mnt/void"

#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
#	COLORS AND CAPTIONS
#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
# Color codes
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[1;33m'
CYAN=$'\e[0;36m'
WHITE=$'\e[1;37m'
NC=$'\e[0m'

# Caption codes
BOLD=$'\e[1m'
CHECK=$'\uf4a7'
INFO=$'\uf449'
LOG=$'\uf4ed'
WARN=$'\uea6c'
ERROR=$'\uea87'

# Titles
title() {
	# Vars for title prompt
	local text="$*"
	local width=60
	local text_len=${#text}
	# Security: If the text is larger than the border, it will only print the text
	if (( text_len >= width )); then
		printf "\n"
		printf "${YELLOW}${BOLD%s${NC}}" "$text"
		printf "\n\n"
		return
	fi
	# It calculates the exact amount of space needed to center the text
	local pad_len=$(( ( width - text_len ) / 2 ))
	local pad_spaces=$( printf '%*s' "$pad_len" "" )
	# Generates the horizontal line with 'chosed' caracter Ascii
	local border=$( printf '%*s' "$width" "" | tr ' ' '=' )
	# Print the block on the screen
	printf "\n"
	printf "${CYAN}${BOLD}%s${NC}\n" "$border"
	printf "${YELLOW}${BOLD}%s%s${NC}\n" "$pad_spaces" "$text"
	printf "${CYAN}${BOLD}%s${NC}\n" "$border"
	printf "\n"
}

# Debugs
check() { printf "%s%s%s %s" "${GREEN}" "${CHECK}" "${NC}" "$*"; }
info() { printf "%s%s%s %s" "${CYAN}" "${INFO}" "${NC}" "$*"; }
log() { printf "%s%s%s %s" "${WHITE}" "${LOG}" "${NC}" "$*"; }
warn() { printf "%s%s%s %s" "${YELLOW}" "${WARN}" "${NC}" "$*"; }
error() { printf "%s%s ERROR:%s %s" "${RED}" "${ERROR}" "${NC}" "$*" >&2; exit 1; }

#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
#	INITIAL CHECKS
#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
# Check if the script is running as superuser
verify_root() {
	[[ $EUID -ne 0 ]] && error "Execute this script as super user (sudo or sudo -s)!"
}

# Check if dependencies is installed
verify_deps() {
	info "Checking for system dependencies..."
	printf "\n"
	# An array containing the names of the commands/packages that the script needs
	local deps=( "gptfdisk" "terminus-font" )
	local missing=()
	# Checks each dependency silently
	for pkg in "${deps[@]}"; do
		if ! command -v "$pkg" > /dev/null 2>&1; then
			missing+=("$pkg")
		fi
	done
	# Checks if the missing array is not empty
	if
		[[ ${#missing[@]} -ne 0 ]]; then
		warn "The following tools/packages are missing:"
			printf "\n"
			# Prints each missing item in the correct format
			for m in "${missing[@]}"; do
				printf "\n"
				printf "	${RED}${ERROR} ${WHITE}%s${NC}" "$m"
			done
			printf "\n\n"
		error "Please install the missing dependencies before continuing!"
	fi
	log "All dependencies is present!"
	printf "\n\n"
}

# Check if the system is connected to the internet
verify_net() {
	info "Checking for connection in the internet..."
	printf "\n"
	ping -q -c 1 -W 3 8.8.8.8 > /dev/null 2>&1 || error "No internet connected or unknown address. Configure the network before continue!"
	log "Connection estabilished!"
	printf "\n\n"
}

# Check if is uefi or bios <- Melhor planejamento recomendado!
verify_uefi() {
	info "Checking boot mode (UEFI or BIOS)..."
	printf "\n"
	if [[ -d "/sys/firmware/efi" ]]; then
		BOOT_MODE="UEFI"
		log "System booted in UEFI mode!"
	else
		BOOT_MODE="BIOS"
		log "System booted in BIOS (Legacy) mode!"
	fi
	printf "\n\n"
	warn "ATTENTION!! Are you sure you want to proceed with the installation in '$BOOT_MODE' mode?"
	printf "\n"
	read -r -p "$(printf "%s" "${YELLOW}")Enter 'y' to continue, any for cancel: $(printf "%s" "${NC}")" confirm
	[[ "${confirm}" != "y" ]] && { error "Operation canceled!"; }
	printf "\n"
}

# Check the selected disk
verify_disk() {
	info "Checking the selected disk..."
	printf "\n"
	[[ ! -b "${DISK}" ]] && error "Disk '${DISK}' is invalid. Verify with 'lsblk' and edit the var 'DISK' on the script 'voidinstall.sh'"
	log "Disk selected!"
	printf "\n\n"
	warn "ATTENTION!! The disk '${DISK}' it will be completely erased, risk of loss all data!"
	printf "\n"
	read -r -p "$(printf "%s" "${YELLOW}")Enter 'y' to continue, any for cancel: $(printf "%s" "${NC}")" confirm
	[[ "${confirm}" != "y" ]] && { error "Operation canceled!"; }
	return 0
}

#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
#	STEP BY STEP PROCESS
#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|

#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
#	SCRIPT EXECUTE
#	|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|=|
main() {
  # Master checks
  verify_root
	# Paving
	clear
	title "STIRUS OS Installer - By LoneStirus"
	# Start script
	MODE="${1:-complete}"
	case "$MODE" in
		complete|"")
			# Sub-checks
			verify_deps
			verify_net
			verify_uefi
			verify_disk
			# Execs
			# create_partitions
			# format_and_mount
			# install_base_system
			# configure_chroot
			# Gran Finale!!
			clear
			title "INSTALLATION COMPLETE!"
			info "You can now reboot your system!" # <- Seria legal adicionar uma func perguntando se quer reiniciar o sistema
			;;
		*)
			error "Unknown mode: '$MODE'. Use --help for help ;)"
		;;
	esac
}

main "$@"
