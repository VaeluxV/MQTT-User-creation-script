#!/bin/bash

# MQTT User Management Script for Mosquitto
# Requires: mosquitto_passwd
# Last updated: 2025-05-13

PASSWORD_FILE="/etc/mosquitto/passwd"

# Function to check root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo."
    exit 1
  fi
}

# Function to check if mosquitto_passwd exists
check_dependencies() {
  if ! command -v mosquitto_passwd &> /dev/null; then
    echo "mosquitto_passwd could not be found. Please install Mosquitto."
    exit 1
  fi
}

# Function to generate random password
generate_password() {
  local length=$1
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

# Function to add a single user
add_user() {
  read -p "Enter new username: " username
  grep -q "^$username:" "$PASSWORD_FILE" && { echo "User '$username' already exists."; return; }
  read -s -p "Enter password: " password
  echo
  read -s -p "Confirm password: " confirm
  echo
  [ "$password" != "$confirm" ] && { echo "Passwords do not match."; return; }
  echo "$password" | mosquitto_passwd -b "$PASSWORD_FILE" "$username" "$password"
  echo "✅ User '$username' added successfully."
}

# Function to delete a user
delete_user() {
  read -p "Enter username to delete: " username
  grep -q "^$username:" "$PASSWORD_FILE" || { echo "User '$username' not found."; return; }

  echo ""
  read -p "Are you sure you want to delete user '$username'? Type 'Y' to confirm: " confirm
  [[ "$confirm" != "Y" ]] && { echo "Cancelled."; return; }

  mosquitto_passwd -D "$PASSWORD_FILE" "$username"
  echo "🗑️  User '$username' deleted."
}

Function to list users
list_users() {
  echo "📋 Registered MQTT users:"
  cut -d: -f1 "$PASSWORD_FILE"
}

# Function to change password for a single user
change_password() {
  read -p "Enter username to change password: " username
  grep -q "^$username:" "$PASSWORD_FILE" || { echo "User '$username' not found."; return; }
  read -s -p "Enter new password: " password
  echo
  read -s -p "Confirm new password: " confirm
  echo
  [ "$password" != "$confirm" ] && { echo "Passwords do not match."; return; }
  echo "$password" | mosquitto_passwd -b "$PASSWORD_FILE" "$username" "$password"
  echo "🔑 Password for '$username' updated."
}

# Function to batch add users
batch_add_users() {
  while true; do
    echo ""
    echo "Batch user creation selected."
    echo "Choose a naming scheme:"
    echo "1 - Fixed prefix + numeric suffix (e.g., user_01, user_02)"
    echo "2 - Fixed prefix + random alphanum suffix (e.g., user_a3f9gk)"
    read -p "Enter naming scheme (1 or 2): " scheme
    [[ "$scheme" =~ ^[12]$ ]] || { echo "Invalid scheme."; continue; }

    read -p "Enter fixed part of the username (prefix): " prefix
    [[ -n "$prefix" ]] || { echo "Prefix cannot be empty."; continue; }

    read -p "How many users to create? " count
    [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] || { echo "Invalid number."; continue; }

    read -p "Enter desired password length (min 8): " pwlen
    [[ "$pwlen" =~ ^[0-9]+$ && "$pwlen" -ge 8 ]] || { echo "Password length too short."; continue; }

    declare -a usernames
    declare -a passwords
    declare -a existing_users

    for ((i=1; i<=count; i++)); do
      if [ "$scheme" == "1" ]; then
        uname="${prefix}_$(printf "%02d" "$i")"
      else
        suffix=$(tr -dc 'a-z0-9' </dev/urandom | head -c6)
        uname="${prefix}_${suffix}"
      fi

      if grep -q "^$uname:" "$PASSWORD_FILE"; then
        existing_users+=("$uname")
      fi

      usernames+=("$uname")
      passwords+=("$(generate_password "$pwlen")")
    done

    if [ "${#existing_users[@]}" -gt 0 ]; then
      echo ""
      echo "⚠️  Some usernames already exist in the password file:"
      printf ' - %s\n' "${existing_users[@]:0:5}"
      if [ "${#existing_users[@]}" -gt 5 ]; then
        echo " ...and $(( ${#existing_users[@]} - 5 )) more."
      fi
      echo ""
      echo "Options:"
      echo "  O - Overwrite existing users"
      echo "  R - Reselect naming scheme"
      echo "  C - Cancel operation"
      read -p "Choose [O/R/C]: " conflict_action
      conflict_action=${conflict_action^^}
      case "$conflict_action" in
        O) echo "Proceeding to overwrite existing users."; break ;;
        R) echo "Reselecting naming scheme..."; continue ;;
        C|*) echo "Batch creation cancelled."; return ;;
      esac
    else
      break
    fi
  done

  echo ""
  echo "Creating users..."
  for ((i=0; i<count; i++)); do
    u="${usernames[$i]}"
    p="${passwords[$i]}"
    echo "$p" | mosquitto_passwd -b "$PASSWORD_FILE" "$u" "$p" >/dev/null
    # Progress bar
    done=$((i+1))
    percent=$((done * 100 / count))
    bar=$(printf "%-${count}s" "#" | cut -c1-$done)
    printf "\r[%s] %d%%" "$bar" "$percent"
  done
  echo ""
  echo "✅ Batch user creation complete."

  echo ""
  echo "How would you like to retrieve the user list?"
  echo "  P - Print users and passwords to terminal"
  echo "  F - Only save to file"
  read -p "Choose [P/F] (must type Y to confirm): " output_choice
  [[ "$output_choice" =~ ^[PpFf]$ ]] || { echo "Invalid option. Skipping output."; return; }
  read -p "Type 'Y' to confirm and output password list: " confirm_out
  [[ "$confirm_out" == "Y" ]] || { echo "Skipped password list output."; return; }

  outfile="$HOME/mqtt_batch_users_$(date +%Y%m%d_%H%M%S).txt"
  {
    echo "MQTT Batch Users - $(date)"
    echo "================================="
    for ((i=0; i<count; i++)); do
      echo "${usernames[$i]} : ${passwords[$i]}"
    done
  } > "$outfile"

  if [[ "$output_choice" =~ ^[Pp]$ ]]; then
    echo ""
    cat "$outfile"
  fi

  echo ""
  echo "📄 Credentials saved to: $outfile"
}

# Batch delete users with a prefix
batch_delete_users() {
  echo ""
  read -p "Enter prefix used during batch create (e.g., 'user'): " prefix
  [[ -z "$prefix" ]] && { echo "Prefix cannot be empty."; return; }

  mapfile -t matches < <(cut -d: -f1 "$PASSWORD_FILE" | grep -E "^${prefix}_.+")

  if [ "${#matches[@]}" -eq 0 ]; then
    echo "No users found with prefix '${prefix}_'"
    return
  fi

  echo "Found ${#matches[@]} users with that prefix:"
  for ((i=0; i<10 && i<${#matches[@]}; i++)); do
    echo " - ${matches[$i]}"
  done
  if [ "${#matches[@]}" -gt 10 ]; then
    echo " ...and $(( ${#matches[@]} - 10 )) more."
    read -p "Show all matched users? [y/N]: " show_all
    [[ "${show_all,,}" == "y" ]] && printf ' - %s\n' "${matches[@]}"
  fi

  echo ""
  read -p "Are you sure you want to delete these ${#matches[@]} users? Type 'Y' to confirm: " confirm
  [[ "$confirm" != "Y" ]] && { echo "Cancelled."; return; }

  for u in "${matches[@]}"; do
    mosquitto_passwd -D "$PASSWORD_FILE" "$u"
  done

  echo "🗑️  Deleted ${#matches[@]} users with prefix '${prefix}_'"
}

# Batch change passwords
batch_change_passwords() {
  echo ""
  read -p "Enter prefix of users to change passwords (e.g., 'user'): " prefix
  [[ -z "$prefix" ]] && { echo "Prefix cannot be empty."; return; }

  mapfile -t matches < <(cut -d: -f1 "$PASSWORD_FILE" | grep -E "^${prefix}_.+")

  if [ "${#matches[@]}" -eq 0 ]; then
    echo "No users found with prefix '${prefix}_'"
    return
  fi

  echo "Found ${#matches[@]} users:"
  for ((i=0; i<10 && i<${#matches[@]}; i++)); do
    echo " - ${matches[$i]}"
  done
  if [ "${#matches[@]}" -gt 10 ]; then
    echo " ...and $(( ${#matches[@]} - 10 )) more."
    read -p "Show all matched users? [y/N]: " show_all
    [[ "${show_all,,}" == "y" ]] && printf ' - %s\n' "${matches[@]}"
  fi

  echo ""
  read -p "Type 'Y' to confirm changing passwords: " confirm
  [[ "$confirm" != "Y" ]] && { echo "Cancelled."; return; }

  read -p "Enter desired password length (min 8): " pwlen
  [[ "$pwlen" =~ ^[0-9]+$ && "$pwlen" -ge 8 ]] || { echo "Password length too short."; return; }

  outfile="$HOME/mqtt_batch_pwchange_$(date +%Y%m%d_%H%M%S).txt"
  {
    echo "MQTT Batch Password Change - $(date)"
    echo "==================================="
    for u in "${matches[@]}"; do
      p=$(generate_password "$pwlen")
      echo "$p" | mosquitto_passwd -b "$PASSWORD_FILE" "$u" "$p"
      echo "$u : $p"
    done
  } > "$outfile"

  echo ""
  echo "🔑 Passwords changed and saved to: $outfile"
  read -p "Print password file to terminal too? (Y to confirm): " show
  [[ "$show" == "Y" ]] && cat "$outfile"
}

# Main menu
main_menu() {
  while true; do
    echo ""
    echo "MQTT User Manager"
    echo "========================="
    echo "A) Add a user"
    echo "B) Batch add users"
    echo "BD) Batch delete users"
    echo "C) Change password for a user"
    echo "BC) Batch password change (by prefix)"
    echo "D) Delete a user"
    echo "L) List users"
    echo "Q) Quit"
    read -p "Select an option: " choice
    case "${choice^^}" in
      A) add_user ;;
      B) batch_add_users ;;
      BD) batch_delete_users ;;
      C) change_password ;;
      BC) batch_change_passwords ;;
      D) delete_user ;;
      L) list_users ;;
      Q) echo "Goodbye!"; exit 0 ;;
      *) echo "Invalid choice." ;;
    esac
  done
}

# Entry point
check_root
check_dependencies
main_menu
