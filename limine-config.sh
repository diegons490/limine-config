#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[31mThis script must be run as root.\e[0m"
  echo "Usage: sudo $0"
  exit 1
fi

set -e

# Color definitions
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"
BOLD="\e[1m"

BACKUP_SUFFIX=".bak-limine-config"
MANAGED_MARKER="### limine-configurator:managed"

# Search for limine.conf recursively under /boot
find_limine_conf() {
  find /boot -type f -name "limine.conf" 2>/dev/null | head -n 1
}

# Ensure a backup of limine.conf exists
ensure_backup() {
  backup_file="${limine_conf}${BACKUP_SUFFIX}"
  if [[ ! -f "$backup_file" ]]; then
    cp "$limine_conf" "$backup_file"
    echo -e "${GREEN}Backup created:${RESET} $backup_file"
  else
    echo -e "${YELLOW}Backup already exists:${RESET} $backup_file"
  fi
}

# Prompt for reboot
prompt_reboot() {
  echo
  read -rp "$(echo -e "${YELLOW}Do you want to reboot now to apply the changes? [y/N]: ${RESET}")" reboot
  if [[ "$reboot" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}Rebooting...${RESET}"
    reboot
  else
    echo -e "${GREEN}Operation completed. Please reboot later to apply the changes.${RESET}"
  fi
}

# Set a key in limine.conf, replacing it if present or adding it at the top
set_param() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}:" "$limine_conf"; then
    sed -i "s|^${key}:.*|${key}: ${value}|" "$limine_conf"
    echo -e "${GREEN}Updated:${RESET} ${key}: ${value}"
  else
    sed -i "1i ${key}: ${value}" "$limine_conf"
    echo -e "${GREEN}Added:${RESET} ${key}: ${value}"
  fi
}

# Get the current value of a key (empty if not set)
get_param() {
  local key="$1"
  grep "^${key}:" "$limine_conf" 2>/dev/null | head -n 1 | cut -d: -f2- | sed 's/^ *//'
}

# Pause (for consistent user interaction)
pause() {
  echo
  read -r -p "Press Enter to return to the main menu..." < /dev/tty
  clear
}

# Read user input; returns 1 if the user typed 'r' or 'R' (go back)
read_or_return() {
  local prompt="$1"
  local __var="$2"
  local input
  read -rp "$(echo -e "${prompt}")" input
  if [[ "$input" =~ ^[rR]$ ]]; then
    return 1
  fi
  printf -v "$__var" '%s' "$input"
  return 0
}

# Load limine.conf path or return
load_conf() {
  limine_conf=$(find_limine_conf)
  if [[ -z "$limine_conf" ]]; then
    echo -e "${RED}Error:${RESET} limine.conf not found in /boot."
    pause
    return 1
  fi
  echo -e "${GREEN}Using config:${RESET} $limine_conf"
  return 0
}

# --- Managed-entry helpers ------------------------------------------------

# Print entry names (header lines) that contain our marker
list_managed_entries() {
  awk -v marker="$MANAGED_MARKER" '
    /^\// { name=$0; managed=0; next }
    $0 == marker {
      if (!managed && name != "") { print name; managed=1 }
    }
  ' "$limine_conf"
}

# Remove every block listed in the given file (one entry name per line)
remove_entries_by_list() {
  local targets_file="$1"
  local tmp
  tmp=$(mktemp)

  awk -v targets_file="$targets_file" -v marker="$MANAGED_MARKER" '
    BEGIN {
      while ((getline line < targets_file) > 0)
        if (line != "") targets[line] = 1
      close(targets_file)
    }
    /^\// {
      if (in_block) {
        if (!(block_managed && (block_name in targets)))
          printf "%s", block_content
      }
      in_block=1
      block_name=$0
      block_content=$0 "\n"
      block_managed=0
      next
    }
    {
      if (in_block) {
        block_content = block_content $0 "\n"
        if ($0 == marker) block_managed=1
      } else {
        print
      }
    }
    END {
      if (in_block && !(block_managed && (block_name in targets)))
        printf "%s", block_content
    }
  ' "$limine_conf" > "$tmp"

  mv "$tmp" "$limine_conf"
}

# --- Menu actions ---------------------------------------------------------

set_timeout() {
  load_conf || return
  ensure_backup

  current=$(get_param "timeout")
  echo -e "${CYAN}Current timeout:${RESET} ${current:-<not set>} seconds"
  echo -e "${YELLOW}(Type 'r' to return without changes)${RESET}"

  read_or_return "${YELLOW}Enter new timeout in seconds: ${RESET}" value || {
    echo -e "${YELLOW}Returning to main menu.${RESET}"; sleep 1; return
  }

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Invalid value. Must be a non-negative integer.${RESET}"; pause; return
  fi

  set_param "timeout" "$value"
  echo -e "${GREEN}${BOLD}Timeout updated.${RESET}"
  prompt_reboot
}

set_default_entry() {
  load_conf || return
  ensure_backup

  current=$(get_param "default_entry")
  echo -e "${CYAN}Current default_entry:${RESET} ${current:-<not set>}"
  echo -e "${YELLOW}(Type 'r' to return without changes)${RESET}"

  read_or_return "${YELLOW}Enter new default_entry: ${RESET}" value || {
    echo -e "${YELLOW}Returning to main menu.${RESET}"; sleep 1; return
  }

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Invalid value. Must be a non-negative integer.${RESET}"; pause; return
  fi

  set_param "default_entry" "$value"
  echo -e "${GREEN}${BOLD}Default entry updated.${RESET}"
  prompt_reboot
}

set_remember_last_entry() {
  load_conf || return
  ensure_backup

  current=$(get_param "remember_last_entry")
  echo -e "${CYAN}Current 'remember_last_entry':${RESET} ${current:-<not set>}"
  echo

  echo -e "${BOLD}When you reboot, should Limine remember the last entry you booted from?${RESET}"
  echo -e "  ${CYAN}1)${RESET} Yes — reopen the same entry next time"
  echo -e "  ${CYAN}2)${RESET} No  — always use the default entry"
  echo -e "  ${YELLOW}r)${RESET} Return to the main menu without changes"
  echo

  local choice new_value
  while true; do
    read -rp "$(echo -e "${YELLOW}Option [1/2/r]: ${RESET}")" choice
    case "$choice" in
      1) new_value="yes"; break ;;
      2) new_value="no";  break ;;
      [rR]) echo -e "${YELLOW}Returning to main menu.${RESET}"; sleep 1; return ;;
      *) echo -e "${RED}Invalid option. Please choose 1, 2, or r.${RESET}" ;;
    esac
  done

  set_param "remember_last_entry" "$new_value"
  echo -e "${GREEN}${BOLD}Remember last entry set to: ${new_value}${RESET}"
  prompt_reboot
}

# Add multiboot entries via limine-scan and tag the new ones
add_multiboot_entry() {
  load_conf || return
  ensure_backup

  if ! command -v limine-scan >/dev/null 2>&1; then
    echo -e "${RED}'limine-scan' was not found in PATH.${RESET}"
    echo -e "${YELLOW}Install the Limine tools (limine-scan / limine-entry-tool) and try again.${RESET}"
    pause
    return
  fi

  local before_file after_file new_file
  before_file=$(mktemp)
  after_file=$(mktemp)
  new_file=$(mktemp)

  grep '^/' "$limine_conf" | sort > "$before_file"

  echo
  echo -e "${CYAN}Running 'limine-scan' to detect new bootable entries...${RESET}"
  echo -e "${YELLOW}(You may pass extra arguments — e.g. a device path — or press Enter to run it plain.)${RESET}"

  local args
  read_or_return "${YELLOW}Arguments for limine-scan (or 'r' to return): ${RESET}" args || {
    rm -f "$before_file" "$after_file" "$new_file"
    echo -e "${YELLOW}Returning to main menu.${RESET}"; sleep 1; return
  }

  local rc=0
  if [[ -z "$args" ]]; then
    limine-scan || rc=$?
  else
    # shellcheck disable=SC2086
    limine-scan $args || rc=$?
  fi

  if [[ $rc -ne 0 ]]; then
    echo -e "${RED}limine-scan exited with status $rc.${RESET}"
    rm -f "$before_file" "$after_file" "$new_file"
    pause
    return
  fi

  grep '^/' "$limine_conf" | sort > "$after_file"

  local new_entries
  new_entries=$(comm -13 "$before_file" "$after_file")

  if [[ -z "$new_entries" ]]; then
    echo -e "${YELLOW}No new boot entries were detected in limine.conf.${RESET}"
    rm -f "$before_file" "$after_file" "$new_file"
    pause
    return
  fi

  echo
  echo -e "${GREEN}New entries detected:${RESET}"
  echo "$new_entries"
  echo

  printf '%s\n' "$new_entries" > "$new_file"

  local tmp
  tmp=$(mktemp)
  awk -v new_file="$new_file" -v marker="$MANAGED_MARKER" '
    BEGIN {
      while ((getline line < new_file) > 0)
        if (line != "") marked[line] = 1
      close(new_file)
    }
    {
      print
      if ($0 ~ /^\// && ($0 in marked)) print marker
    }
  ' "$limine_conf" > "$tmp"
  mv "$tmp" "$limine_conf"

  rm -f "$before_file" "$after_file" "$new_file"

  echo -e "${GREEN}${BOLD}Marker '${MANAGED_MARKER}' was added to the new entries.${RESET}"
  echo -e "${YELLOW}These entries can now be removed from the main menu.${RESET}"
  prompt_reboot
}

# Remove entries previously created by this script
remove_managed_entry() {
  load_conf || return
  ensure_backup

  local managed
  managed=$(list_managed_entries)

  if [[ -z "$managed" ]]; then
    echo -e "${YELLOW}No entries managed by this script were found in limine.conf.${RESET}"
    pause
    return
  fi

  echo
  echo -e "${BOLD}Entries managed by limine-configurator:${RESET}"
  local i=1
  local -a entries=()
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    entries+=("$entry")
    echo -e "  ${CYAN}$i)${RESET} $entry"
    ((i++))
  done <<< "$managed"
  echo

  echo -e "${YELLOW}Enter one or more numbers (comma-separated), 'all' to remove every entry above, or 'r' to return.${RESET}"
  local selection
  read -rp "$(echo -e "${YELLOW}Selection: ${RESET}")" selection

  if [[ "$selection" =~ ^[rR]$ ]]; then
    echo -e "${YELLOW}Returning to main menu.${RESET}"; sleep 1; return
  fi

  local targets_file
  targets_file=$(mktemp)

  if [[ "$selection" =~ ^[Aa][Ll][Ll]$ ]]; then
    printf '%s\n' "${entries[@]}" > "$targets_file"
  else
    local cleaned="${selection// /}"
    local n
    IFS=',' read -ra nums <<< "$cleaned"
    for n in "${nums[@]}"; do
      if [[ ! "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#entries[@]} )); then
        echo -e "${RED}Invalid selection: '$n'${RESET}"
        rm -f "$targets_file"; pause; return
      fi
      printf '%s\n' "${entries[$((n-1))]}" >> "$targets_file"
    done
  fi

  echo
  echo -e "${CYAN}The following entries will be removed:${RESET}"
  sed 's/^/  - /' "$targets_file"
  echo

  local confirm
  read_or_return "${YELLOW}Confirm removal? [y/N] (or 'r' to cancel): ${RESET}" confirm || {
    rm -f "$targets_file"
    echo -e "${YELLOW}Returning to main menu.${RESET}"; sleep 1; return
  }

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    rm -f "$targets_file"
    echo -e "${YELLOW}Removal canceled.${RESET}"; pause; return
  fi

  remove_entries_by_list "$targets_file"
  rm -f "$targets_file"

  echo -e "${GREEN}${BOLD}Selected entries removed from limine.conf.${RESET}"
  prompt_reboot
}

# --- Manual editor / restore ---------------------------------------------

choose_editor() {
  echo
  echo "Choose a text editor to open the file:"
  echo "1) nano"
  echo "2) micro"
  echo "3) vim"
  echo "4) vi"
  echo "5) ne"
  echo "6) joe"
  echo "7) emacs (terminal mode)"
  echo "8) other (type the name)"
  echo
  echo -e "${YELLOW}(Type 'r' to return without opening an editor)${RESET}"
  read -rp "Option [1-8/r]: " choice

  case "$choice" in
    [rR]) return 1 ;;
    1) editor_cmd="nano" ;;
    2) editor_cmd="micro" ;;
    3) editor_cmd="vim" ;;
    4) editor_cmd="vi" ;;
    5) editor_cmd="ne" ;;
    6) editor_cmd="joe" ;;
    7) editor_cmd="emacs -nw" ;;
    8) read -rp "Enter the editor name: " editor_cmd ;;
    *) echo "Invalid option. Using nano as default."; editor_cmd="nano" ;;
  esac

  local editor_bin
  editor_bin=$(awk '{print $1}' <<< "$editor_cmd")

  if ! command -v "$editor_bin" >/dev/null 2>&1; then
    echo
    echo "[ERROR] The editor '$editor_bin' is not installed on the system."
    echo "Install it before trying again."
    echo
    return 2
  fi
  return 0
}

edit_limine_conf() {
  load_conf || return
  ensure_backup

  choose_editor
  case $? in
    1) echo -e "${YELLOW}Returning to main menu.${RESET}"; sleep 1; return ;;
    2) pause; return ;;
  esac

  echo -e "${GREEN}Opening:${RESET} $limine_conf with: ${YELLOW}$editor_cmd${RESET}"
  sleep 1
  $editor_cmd "$limine_conf"
  echo -e "${GREEN}Editing completed.${RESET}"
  pause
}

restore_backup() {
  load_conf || return

  backup_file="${limine_conf}${BACKUP_SUFFIX}"
  if [[ ! -f "$backup_file" ]]; then
    echo -e "${RED}No backup found to restore.${RESET}"; pause; return
  fi

  local confirm
  read_or_return "${YELLOW}Restore limine.conf from backup? This will overwrite current settings. [y/N] (or 'r' to return): ${RESET}" confirm || {
    echo -e "${YELLOW}Returning to main menu.${RESET}"; sleep 1; return
  }

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Restore canceled.${RESET}"; pause; return
  fi

  cp "$backup_file" "$limine_conf"
  echo -e "${GREEN}${BOLD}Backup restored to $limine_conf${RESET}"
  prompt_reboot
}

# --- Main menu ------------------------------------------------------------

while true; do
  clear
  echo
  echo -e "${BOLD}Limine Configurator${RESET}"
  echo -e "${BOLD}Choose an option:${RESET}"
  echo -e "${CYAN}1)${RESET} Set boot timeout"
  echo -e "${CYAN}2)${RESET} Set default entry"
  echo -e "${CYAN}3)${RESET} Remember last booted entry"
  echo -e "${CYAN}4)${RESET} Add multiboot entries (limine-scan)"
  echo -e "${CYAN}5)${RESET} Remove entries added by this script"
  echo -e "${CYAN}6)${RESET} Edit limine.conf manually"
  echo -e "${CYAN}7)${RESET} Restore limine.conf from backup"
  echo -e "${RED}8)${RESET} Exit"
  read -rp "$(echo -e "${YELLOW}Option: ${RESET}")" option

  case "$option" in
    1) clear; set_timeout ;;
    2) clear; set_default_entry ;;
    3) clear; set_remember_last_entry ;;
    4) clear; add_multiboot_entry ;;
    5) clear; remove_managed_entry ;;
    6) clear; edit_limine_conf ;;
    7) clear; restore_backup ;;
    8) echo -e "${YELLOW}Exiting.${RESET}"; exit 0 ;;
    *) echo -e "${RED}Invalid option.${RESET}"; sleep 1 ;;
  esac
done
