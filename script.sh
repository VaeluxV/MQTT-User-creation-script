#!/bin/bash

DEFAULT_CONFIG="/etc/mosquitto/conf.d/auth.conf"
CONFIG_FILE=""

# Parse arguments
while getopts "c:" opt; do
  case $opt in
    c) CONFIG_FILE="$OPTARG" ;;
    *) echo "Usage: $0 [-c /path/to/config]"; exit 1 ;;
  esac
done

# If no config file given, use default
if [ -z "$CONFIG_FILE" ]; then
  if [ -f "$DEFAULT_CONFIG" ]; then
    CONFIG_FILE="$DEFAULT_CONFIG"
  else
    echo "Default config file not found at $DEFAULT_CONFIG."
    read -p "Please enter the full path to your Mosquitto config file: " CONFIG_FILE
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "Error: Config file '$CONFIG_FILE' does not exist."
      exit 1
    fi
  fi
fi

# Extract password file location from config
PASSWORD_FILE=$(grep -E "^password_file\s+" "$CONFIG_FILE" | awk '{print $2}')
if [ -z "$PASSWORD_FILE" ]; then
  echo "Password file not defined in $CONFIG_FILE."
  exit 1
fi

# Check for allow_anonymous setting
ANON_LINE=$(grep -E "^allow_anonymous\s+" "$CONFIG_FILE")
ANON_STATE=$(echo "$ANON_LINE" | awk '{print tolower($2)}')

if [ "$ANON_STATE" = "true" ]; then
  echo "Anonymous authentication is currently ENABLED."
  read -p "Do you want to keep anonymous access enabled? [Y/n]: " anon_input
  anon_input=${anon_input:-Y}
  if [[ "$anon_input" =~ ^[Nn]$ ]]; then
    sudo sed -i 's/^allow_anonymous\s\+true/allow_anonymous false/' "$CONFIG_FILE"
    echo "Anonymous access DISABLED."
    sudo systemctl restart mosquitto
  else
    echo "Anonymous access remains ENABLED."
  fi
elif [ "$ANON_STATE" = "false" ]; then
  echo "Anonymous authentication is currently DISABLED."
  read -p "Do you want to keep anonymous access disabled? [Y/n]: " anon_input
  anon_input=${anon_input:-Y}
  if [[ "$anon_input" =~ ^[Nn]$ ]]; then
    sudo sed -i 's/^allow_anonymous\s\+false/allow_anonymous true/' "$CONFIG_FILE"
    echo "Anonymous access ENABLED."
    sudo systemctl restart mosquitto
  else
    echo "Anonymous access remains DISABLED."
  fi
else
  echo "Could not determine anonymous authentication state."
  exit 1
fi

# Ensure password file exists
sudo touch "$PASSWORD_FILE"
sudo chown mosquitto: "$PASSWORD_FILE"
sudo chmod 600 "$PASSWORD_FILE"

# Main menu
while true; do
  echo ""
  echo "What would you like to do?"
  echo "U - Add user"
  echo "E - Edit existing user's password"
  echo "D - Delete user"
  echo "X - Exit"
  read -p "Enter your choice: " choice
  choice=${choice^^}  # Convert to uppercase

  case "$choice" in
    U)
      read -p "Enter new username: " new_user
      if grep -q "^$new_user:" "$PASSWORD_FILE"; then
        echo "User '$new_user' already exists."
      else
        read -s -p "Enter password for '$new_user': " new_pass
        echo
        echo "$new_pass" | sudo mosquitto_passwd -b "$PASSWORD_FILE" "$new_user" "$new_pass"
        echo "User '$new_user' created."
      fi
      ;;
    E)
      read -p "Enter existing username to edit: " edit_user
      if grep -q "^$edit_user:" "$PASSWORD_FILE"; then
        read -s -p "Enter new password for '$edit_user': " new_pass
        echo
        echo "$new_pass" | sudo mosquitto_passwd -b "$PASSWORD_FILE" "$edit_user" "$new_pass"
        echo "Password updated for '$edit_user'."
      else
        echo "User '$edit_user' does not exist."
        read -p "Would you like to create this user instead? [y/N]: " create_choice
        create_choice=${create_choice:-N}
        if [[ "$create_choice" =~ ^[Yy]$ ]]; then
          read -s -p "Enter password for '$edit_user': " new_pass
          echo
          echo "$new_pass" | sudo mosquitto_passwd -b "$PASSWORD_FILE" "$edit_user" "$new_pass"
          echo "User '$edit_user' created."
        else
          echo "No action taken."
        fi
      fi
      ;;
    D)
      read -p "Enter username to delete: " del_user
      if grep -q "^$del_user:" "$PASSWORD_FILE"; then
        read -p "Are you sure you want to delete user '$del_user'? [y/N]: " confirm
        confirm=${confirm:-N}
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          sudo mosquitto_passwd -D "$PASSWORD_FILE" "$del_user"
          echo "User '$del_user' deleted."
        else
          echo "User not deleted."
        fi
      else
        echo "User '$del_user' does not exist."
      fi
      ;;
    X)
      echo "Exiting."
      exit 0
      ;;
    *)
      echo "Invalid option. Please choose U, E, D, or X."
      ;;
  esac
done
