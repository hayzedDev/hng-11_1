#!/bin/bash

# Check if the correct number of arguments is passed
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

# The second argument is the filename
filename="$1"

# Check if the file exists
if [ ! -f "$filename" ]; then
    echo "File not found: $filename"
    exit 1
fi

# Function to trim leading and trailing whitespace
trim() {
    local var="$*"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Define the file to check
user_mgt_file_path="/var/log/user_management.log"
user_mgt_dir_path=$(dirname "$user_mgt_file_path")

# Check if the directory exists
if [ ! -d "$user_mgt_dir_path" ]; then
  # Create the directory if it doesn't exist
  mkdir -p "$user_mgt_dir_path"
fi

# Check if the file exists
if [ ! -f "$user_mgt_file_path" ]; then
  # Create the file if it doesn't exist
  touch "$user_mgt_file_path"
  echo "File '$user_mgt_file_path' created."
fi

# Define the file to check
user_pass_file_path="/var/secure/user_passwords.csv"
user_pass_dir_path=$(dirname "$user_pass_file_path")

# Check if the directory exists
if [ ! -d "$user_pass_dir_path" ]; then
  # Create the directory if it doesn't exist
  mkdir -p "$user_pass_dir_path"
  echo "Directory $user_pass_dir_path created..." >> $user_mgt_file_path
fi

# Check if the file exists
if [ ! -f "$user_pass_file_path" ]; then
  # Create the file if it doesn't exist
  touch "$user_pass_file_path"
  echo "File $user_pass_file_path created..." >> $user_mgt_file_path
fi

# Loop through each line in the file
while IFS= read -r line; do
  # Process each line
  # echo "Processing: $line"

  # Define the username and password
  # Trim leading and trailing whitespace
  username=$(trim "${line%%;*}")
  password=$(LC_CTYPE=C < /dev/urandom tr -dc 'A-Za-z0-9!@#$%&*' | head -c 16)

  # Generate a random password
  echo "Password generated for user $username" >> $user_mgt_file_path


  usergroups=$(trim "${line#*;}")

  # Split the usergroups into an array
  IFS=',' read -r -a groups_array <<< "$usergroups"
  for i in "${!groups_array[@]}"; do
      groups_array[$i]=$(trim "${groups_array[$i]}")
      # groups_array[$i]=$(echo "${groups_array[$i]}" | xargs)
  done

  # Extract the primary group (first element)
  primary_group="${username}"

  # Extract the remaining groups
  if [ "${#groups_array[@]}" -gt 0 ]; then
      additional_groups=$(IFS=,; echo "${groups_array[*]:0}")
  else
      additional_groups=""
  fi

  # Function to check if a group exists, and create it if it doesn't
  create_group_if_not_exists() {
      groupname="$1"
      if ! getent group "$groupname" > /dev/null 2>&1; then
          groupadd "$groupname"
          echo "User group '$groupname' created..." >> $user_mgt_file_path
      else
          echo "User group '$groupname' already exist! Skipping" >> $user_mgt_file_path
      fi
  }

  # Check and create primary group
  create_group_if_not_exists "$primary_group"

  # Check and create additional groups
  for group in "${groups_array[@]}"; do
      create_group_if_not_exists "$group"
  done


  # Check if the group already exists
  if ! getent group "$username" > /dev/null 2>&1; then
    # Create the group if it doesn't exist
    groupadd "$username"
    echo "Directory $user_pass_dir_path created..." >> $user_mgt_file_path # TODO
  fi

  # Check if the user already exists
  if id "$username" &>/dev/null; then

    usermod -g "$primary_group" "$username"
    usermod -aG "$additional_groups" "$username"

    echo "User '$username' already exists. Adding the user to the groups and skipping..."
    echo "User '$username' already exists. Adding the user to the groups and skipping..." >> $user_mgt_file_path
  else
    # Create the user with the primary group and additional groups if any
    if [ -n "$additional_groups" ]; then
        useradd -m -g "$primary_group" -G "$additional_groups" -s /bin/bash "$username"
    else
        useradd -m -g "$primary_group" -s /bin/bash "$username"
    fi

    # Create the user with the specified group and set the password
    # useradd -m -g "$username" -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    echo "User '$username' created! Password has also been set for the user" >> $user_mgt_file_path

    # Display the created username and password
    echo "Password for user '$username' is: $password" >> $user_pass_file_path

    # Set the home directory path
    home_directory="/home/$username"

    # Set permissions and ownership for the home directory
    chown "$username:$primary_group" "$home_directory"
    chmod 755 "$home_directory"

    # Ensure appropriate permissions for additional groups
    for group in "${groups_array[@]}"; do
        if [ "$group" != "$primary_group" ]; then
            chmod g+rx "$home_directory"
            setfacl -m "g:$group:rx" "$home_directory"
        fi
    done

    echo "User $username created with home directory $home_directory" >> $user_mgt_file_path
    echo "Users created!"
  fi
done < "$filename"